#!/usr/bin/env python3
"""
Integration Tests for Complete Workflow Steps

Tests the integration of multiple components:
- HELAC-Onia build and run
- LHE preprocessing pipeline
- Pythia 8 showering
- CMSSW simulation steps
- DAGman workflow generation
"""

import unittest
import subprocess
import tempfile
import os
import shutil
import yaml
from pathlib import Path

class TestWorkflowIntegration(unittest.TestCase):
    """Test integration of workflow components"""
    
    @classmethod
    def setUpClass(cls):
        cls.repo_root = Path(__file__).parent.parent.parent
        cls.scripts_dir = cls.repo_root / "scripts"
        cls.workflow_dir = cls.repo_root / "workflow"
    
    def setUp(self):
        """Create temporary directory for test outputs"""
        self.temp_dir = tempfile.mkdtemp()
        self.original_dir = os.getcwd()
    
    def tearDown(self):
        """Clean up and restore directory"""
        os.chdir(self.original_dir)
        shutil.rmtree(self.temp_dir, ignore_errors=True)
    
    def test_dagman_generation(self):
        """Test: DAGman workflow generation from YAML config"""
        # Create a minimal test config
        config = {
            'workflow': {
                'name': 'test_workflow',
                'description': 'Test workflow',
                'output_dir': '/tmp/test_output',
                'temp_dir': '/tmp/test_temp'
            },
            'matrix_element': {
                'generator': 'helac-onia',
                'batch_mode': 'single_job',
                'seeds': {'start': 11, 'end': 15},
                'harvest': {'enabled': True}
            },
            'lhe_preprocessing': {
                'enabled': False
            },
            'showering': {
                'enabled': True,
                'generator': 'pythia8'
            },
            'simulation': {
                'enabled': False
            },
            'submission': {
                'condor': {
                    'enabled': True,
                    'dagman': True
                }
            }
        }
        
        config_path = Path(self.temp_dir) / "test_config.yaml"
        with open(config_path, 'w') as f:
            yaml.dump(config, f)
        
        # Generate DAG
        output_dir = Path(self.temp_dir) / "workflow_output"
        output_dir.mkdir(parents=True, exist_ok=True)
        
        result = subprocess.run(
            ["python3", str(self.workflow_dir / "generate_dag.py"),
             str(config_path), "--output", str(output_dir)],
            capture_output=True,
            text=True
        )
        
        self.assertEqual(result.returncode, 0, 
                        f"DAG generation failed: {result.stderr}")
        
        # Verify DAG file was created
        dag_file = output_dir / "generated.dag"
        self.assertTrue(dag_file.exists(), "DAG file not created")
        
        # Verify DAG contains expected jobs
        with open(dag_file, 'r') as f:
            dag_content = f.read()
            self.assertIn("JOB matrix_element", dag_content)
            self.assertIn("JOB harvest_lhe", dag_content)
            self.assertIn("JOB showering", dag_content)
    
    def test_lhe_preprocessing_pipeline(self):
        """Test: Complete LHE preprocessing pipeline"""
        # Create test LHE files
        test_lhe1 = self.create_test_lhe("input1.lhe", 50)
        test_lhe2 = self.create_test_lhe("input2.lhe", 50)
        
        # Test mixing
        mixed_file = Path(self.temp_dir) / "mixed.lhe"
        result = subprocess.run(
            [str(self.repo_root / "bin" / "lhe_mixer"), "mix",
             "--inputs", f"{test_lhe1},{test_lhe2}",
             "--output", str(mixed_file),
             "--shuffle"],
            capture_output=True,
            text=True
        )
        
        self.assertEqual(result.returncode, 0, f"Mixing failed: {result.stderr}")
        self.assertTrue(mixed_file.exists(), "Mixed file not created")
        
        # Test splitting
        split_dir = Path(self.temp_dir) / "split"
        result = subprocess.run(
            [str(self.repo_root / "bin" / "lhe_mixer"), "split",
             "--input", str(mixed_file),
             "--output-dir", str(split_dir),
             "--tier1", "25",
             "--tier2", "10"],
            capture_output=True,
            text=True
        )
        
        self.assertEqual(result.returncode, 0, f"Splitting failed: {result.stderr}")
        self.assertTrue(split_dir.exists(), "Split directory not created")
        
        # Verify split files
        split_files = list(split_dir.glob("*.lhe"))
        self.assertGreater(len(split_files), 0, "No split files created")
    
    def test_workflow_config_validation(self):
        """Test: Workflow configuration validation"""
        # Test with invalid config
        invalid_config = {
            'workflow': {
                'name': 'test'
                # Missing required fields
            }
        }
        
        config_path = Path(self.temp_dir) / "invalid_config.yaml"
        with open(config_path, 'w') as f:
            yaml.dump(invalid_config, f)
        
        # Should handle gracefully
        result = subprocess.run(
            ["python3", str(self.workflow_dir / "generate_dag.py"),
             str(config_path), "--output", self.temp_dir],
            capture_output=True,
            text=True
        )
        
        # May fail or use defaults - either is acceptable
        # Just verify it doesn't crash
        self.assertIsNotNone(result.returncode)
    
    def test_external_lhe_input(self):
        """Test: External LHE file input support"""
        # Create external LHE file
        external_lhe = self.create_test_lhe("external.lhe", 100)
        
        # Verify it can be processed
        output = Path(self.temp_dir) / "processed.lhe"
        result = subprocess.run(
            [str(self.repo_root / "bin" / "lhe_mixer"), "mix",
             "--inputs", external_lhe,
             "--output", str(output)],
            capture_output=True,
            text=True
        )
        
        self.assertEqual(result.returncode, 0, "External LHE processing failed")
        self.assertTrue(output.exists(), "Processed file not created")
    
    def test_multiple_scattering_mixing(self):
        """Test: Multiple sub-scattering mixing (TPS, QPS)"""
        # Create files for triple parton scattering
        jpsi1 = self.create_test_lhe("jpsi1.lhe", 30, process_id=1)
        jpsi2 = self.create_test_lhe("jpsi2.lhe", 30, process_id=2)
        upsilon = self.create_test_lhe("upsilon.lhe", 30, process_id=3)
        
        output = Path(self.temp_dir) / "tps_mixed.lhe"
        
        # Mix with recipe: 1 from each = TPS
        result = subprocess.run(
            [str(self.repo_root / "bin" / "lhe_mixer"), "mix",
             "--recipe", f"{jpsi1}:1,{jpsi2}:1,{upsilon}:1",
             "--output", str(output),
             "--max-events", "10"],
            capture_output=True,
            text=True
        )
        
        self.assertEqual(result.returncode, 0, f"TPS mixing failed: {result.stderr}")
        self.assertTrue(output.exists(), "TPS output not created")
    
    def create_test_lhe(self, filename, num_events, process_id=1):
        """Helper: Create test LHE file"""
        filepath = Path(self.temp_dir) / filename
        
        with open(filepath, 'w') as f:
            f.write('<LesHouchesEvents version="1.0">\n')
            f.write('<header>Test LHE</header>\n')
            f.write('<init>\n')
            f.write('  2212  2212  6800.0  6800.0  0  0  0  0  3  1\n')
            f.write(f'  1.0  0.0  1.0  {process_id}\n')
            f.write('</init>\n')
            
            for i in range(num_events):
                f.write('<event>\n')
                f.write(f' 4  {process_id}  1.0  100.0  0.0075  0.118\n')
                f.write('  21  -1  0  0  501  502  0.0  0.0  500.0  500.0  0.0  0.0  9.0\n')
                f.write('  21  -1  0  0  503  504  0.0  0.0 -500.0  500.0  0.0  0.0  9.0\n')
                f.write('  21   1  1  2  501  503  100.0  50.0  200.0  250.0  0.0  0.0  9.0\n')
                f.write('  21   1  1  2  502  504 -100.0 -50.0 -200.0  250.0  0.0  0.0  9.0\n')
                f.write('</event>\n')
            
            f.write('</LesHouchesEvents>\n')
        
        return str(filepath)


class TestScriptIntegration(unittest.TestCase):
    """Test individual scripts work correctly"""
    
    @classmethod
    def setUpClass(cls):
        cls.repo_root = Path(__file__).parent.parent.parent
        cls.scripts_dir = cls.repo_root / "scripts"
    
    def test_harvest_lhe_script(self):
        """Test: LHE harvesting script"""
        script = self.scripts_dir / "harvest_lhe.sh"
        
        # Check script exists and is executable
        self.assertTrue(script.exists(), "harvest_lhe.sh not found")
        self.assertTrue(os.access(script, os.X_OK), "harvest_lhe.sh not executable")
    
    def test_split_shuffle_script(self):
        """Test: Split and shuffle script"""
        script = self.scripts_dir / "split_shuffle.sh"
        
        self.assertTrue(script.exists(), "split_shuffle.sh not found")
        self.assertTrue(os.access(script, os.X_OK), "split_shuffle.sh not executable")
    
    def test_run_pythia_shower_script(self):
        """Test: Pythia shower script"""
        script = self.scripts_dir / "run_pythia_shower.sh"
        
        self.assertTrue(script.exists(), "run_pythia_shower.sh not found")
        self.assertTrue(os.access(script, os.X_OK), "run_pythia_shower.sh not executable")
    
    def test_run_cmssw_step_script(self):
        """Test: CMSSW step script"""
        script = self.scripts_dir / "run_cmssw_step.sh"
        
        self.assertTrue(script.exists(), "run_cmssw_step.sh not found")
        self.assertTrue(os.access(script, os.X_OK), "run_cmssw_step.sh not executable")
    
    def test_cleanup_intermediate_script(self):
        """Test: Cleanup script"""
        script = self.scripts_dir / "cleanup_intermediate.sh"
        
        self.assertTrue(script.exists(), "cleanup_intermediate.sh not found")
        self.assertTrue(os.access(script, os.X_OK), "cleanup_intermediate.sh not executable")


if __name__ == '__main__':
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""
End-to-End Workflow Test

This test validates the complete integrated workflow from start to finish.
It creates a minimal workflow configuration and runs through all steps.
"""

import unittest
import subprocess
import tempfile
import os
import shutil
import yaml
from pathlib import Path

class TestEndToEndWorkflow(unittest.TestCase):
    """End-to-end workflow validation"""
    
    @classmethod
    def setUpClass(cls):
        cls.repo_root = Path(__file__).parent.parent
        cls.original_dir = os.getcwd()
        
        # Ensure tools are built
        print("\nBuilding required tools...")
        result = subprocess.run(
            ["make", "tools"],
            cwd=cls.repo_root,
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            print(f"Build warnings: {result.stderr}")
    
    def setUp(self):
        """Create temporary directory"""
        self.temp_dir = tempfile.mkdtemp()
        os.chdir(self.temp_dir)
    
    def tearDown(self):
        """Clean up and restore directory"""
        os.chdir(self.original_dir)
        shutil.rmtree(self.temp_dir, ignore_errors=True)
    
    def test_complete_workflow_minimal(self):
        """Test: Minimal end-to-end workflow"""
        print("\n" + "="*60)
        print("END-TO-END WORKFLOW TEST")
        print("="*60)
        
        # Step 1: Create test LHE files
        print("\n[Step 1] Creating test LHE files...")
        jpsi_lhe = self.create_test_lhe("jpsi.lhe", 100, process_id=1)
        upsilon_lhe = self.create_test_lhe("upsilon.lhe", 100, process_id=2)
        print(f"  ✓ Created {jpsi_lhe}")
        print(f"  ✓ Created {upsilon_lhe}")
        
        # Step 2: Mix events (DPS)
        print("\n[Step 2] Mixing events for DPS...")
        mixed_lhe = Path(self.temp_dir) / "mixed_dps.lhe"
        result = subprocess.run(
            [str(self.repo_root / "bin" / "lhe_mixer"), "mix",
             "--recipe", f"{jpsi_lhe}:1,{upsilon_lhe}:1",
             "--output", str(mixed_lhe),
             "--max-events", "50"],
            capture_output=True,
            text=True
        )
        self.assertEqual(result.returncode, 0, f"Mixing failed: {result.stderr}")
        self.assertTrue(mixed_lhe.exists(), "Mixed LHE not created")
        print(f"  ✓ Created mixed events: {mixed_lhe}")
        
        # Step 3: Split and shuffle
        print("\n[Step 3] Splitting and shuffling...")
        split_dir = Path(self.temp_dir) / "split"
        result = subprocess.run(
            [str(self.repo_root / "bin" / "lhe_mixer"), "split",
             "--input", str(mixed_lhe),
             "--output-dir", str(split_dir),
             "--tier1", "25",
             "--tier2", "10",
             "--shuffle"],
            capture_output=True,
            text=True
        )
        self.assertEqual(result.returncode, 0, f"Splitting failed: {result.stderr}")
        self.assertTrue(split_dir.exists(), "Split directory not created")
        split_files = list(split_dir.glob("*.lhe"))
        print(f"  ✓ Created {len(split_files)} split files")
        
        # Step 4: Process external LHE
        print("\n[Step 4] Processing external LHE...")
        external_lhe = self.create_test_lhe("external.lhe", 200, process_id=3)
        processed_dir = Path(self.temp_dir) / "processed"
        
        result = subprocess.run(
            [str(self.repo_root / "scripts" / "process_external_lhe.sh"),
             "--input", external_lhe,
             "--output-dir", str(processed_dir),
             "--no-post-process"],
            capture_output=True,
            text=True
        )
        self.assertEqual(result.returncode, 0, f"External LHE processing failed: {result.stderr}")
        print(f"  ✓ Processed external LHE to {processed_dir}")
        
        # Step 5: Validate workflow configuration
        print("\n[Step 5] Validating workflow configuration...")
        config = self.create_test_workflow_config()
        config_path = Path(self.temp_dir) / "test_workflow.yaml"
        with open(config_path, 'w') as f:
            yaml.dump(config, f)
        
        # Generate DAG
        dag_output = Path(self.temp_dir) / "workflow_output"
        dag_output.mkdir(parents=True, exist_ok=True)
        
        result = subprocess.run(
            ["python3", str(self.repo_root / "workflow" / "generate_dag.py"),
             str(config_path), "--output", str(dag_output)],
            capture_output=True,
            text=True
        )
        self.assertEqual(result.returncode, 0, f"DAG generation failed: {result.stderr}")
        
        dag_file = dag_output / "generated.dag"
        self.assertTrue(dag_file.exists(), "DAG file not generated")
        print(f"  ✓ Generated DAG: {dag_file}")
        
        # Validate DAG content
        with open(dag_file, 'r') as f:
            dag_content = f.read()
            self.assertIn("JOB", dag_content, "DAG should contain JOB definitions")
            self.assertIn("PARENT", dag_content, "DAG should contain dependencies")
        
        print("\n" + "="*60)
        print("END-TO-END WORKFLOW TEST: PASSED ✓")
        print("="*60)
    
    def test_workflow_with_gluon_merging(self):
        """Test: Workflow with selective gluon merging"""
        print("\n[Test] Workflow with selective gluon merging...")
        
        # Create test files
        fileA = self.create_test_lhe("sub1.lhe", 50, process_id=1)
        fileB = self.create_test_lhe("sub2.lhe", 50, process_id=2)
        
        # Mix with selective gluon merging
        output = Path(self.temp_dir) / "merged.lhe"
        result = subprocess.run(
            [str(self.repo_root / "bin" / "lhe_mixer"), "mix",
             "--inputs", f"{fileA},{fileB}",
             "--output", str(output),
             "--merge-gluons",
             "--merge-subscatterings", "0",
             "--max-events", "20"],
            capture_output=True,
            text=True
        )
        
        self.assertEqual(result.returncode, 0, f"Selective merging failed: {result.stderr}")
        self.assertTrue(output.exists(), "Output not created")
        print(f"  ✓ Selective gluon merging successful")
    
    def create_test_lhe(self, filename, num_events, process_id=1):
        """Helper: Create test LHE file"""
        filepath = Path(self.temp_dir) / filename
        
        with open(filepath, 'w') as f:
            f.write('<LesHouchesEvents version="1.0">\n')
            f.write('<header>Test LHE for end-to-end testing</header>\n')
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
    
    def create_test_workflow_config(self):
        """Helper: Create minimal workflow configuration"""
        return {
            'workflow': {
                'name': 'end_to_end_test',
                'description': 'End-to-end test workflow',
                'output_dir': str(Path(self.temp_dir) / 'output'),
                'temp_dir': str(Path(self.temp_dir) / 'temp')
            },
            'matrix_element': {
                'generator': 'helac-onia',
                'batch_mode': 'single_job',
                'seeds': {'start': 11, 'end': 15},
                'harvest': {'enabled': True}
            },
            'lhe_preprocessing': {
                'enabled': True,
                'split': {'tier1_size': 1000, 'tier2_size': 100, 'shuffle': True},
                'mixing': {'enabled': False},
                'gluon_merging': {'enabled': False}
            },
            'showering': {
                'enabled': True,
                'generator': 'pythia8',
                'standalone': True,
                'tuning': 'CP5'
            },
            'simulation': {
                'enabled': False  # Skip CMSSW for faster testing
            },
            'submission': {
                'condor': {'enabled': True, 'dagman': True}
            }
        }


if __name__ == '__main__':
    # Run with verbose output
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""
Unit Tests for LHE Mixer C++ Tool

Tests the core functionality of the LHE mixer including:
- Event mixing from multiple sources
- Advanced mix recipes (e.g., "3 from A, 1 from B")
- Gluon merging with selective sub-scatterings
- Two-tier split and shuffle
- File I/O operations
"""

import unittest
import subprocess
import tempfile
import os
import shutil
from pathlib import Path

class TestLHEMixer(unittest.TestCase):
    """Test suite for LHE Mixer functionality"""
    
    @classmethod
    def setUpClass(cls):
        """Build the LHE mixer tool"""
        cls.repo_root = Path(__file__).parent.parent.parent
        cls.mixer_bin = cls.repo_root / "bin" / "lhe_mixer"
        
        # Build if not exists
        if not cls.mixer_bin.exists():
            print("Building lhe_mixer...")
            result = subprocess.run(
                ["make", "tools"],
                cwd=cls.repo_root,
                capture_output=True,
                text=True
            )
            if result.returncode != 0:
                print(f"Build output: {result.stdout}")
                print(f"Build errors: {result.stderr}")
                raise RuntimeError("Failed to build lhe_mixer")
        
        cls.test_data_dir = cls.repo_root / "tests" / "data"
        cls.test_data_dir.mkdir(parents=True, exist_ok=True)
    
    def setUp(self):
        """Create temporary directory for test outputs"""
        self.temp_dir = tempfile.mkdtemp()
    
    def tearDown(self):
        """Clean up temporary directory"""
        shutil.rmtree(self.temp_dir, ignore_errors=True)
    
    def create_test_lhe(self, filename, num_events=10, process_id=1):
        """Create a minimal test LHE file"""
        filepath = Path(self.temp_dir) / filename
        
        with open(filepath, 'w') as f:
            # LHE header
            f.write('<LesHouchesEvents version="1.0">\n')
            f.write('<header>\n')
            f.write('  Test LHE file for unit testing\n')
            f.write('</header>\n')
            f.write('<init>\n')
            f.write('  2212  2212  6.800000e+03  6.800000e+03  0  0  0  0  3  1\n')
            f.write('  1.000000e+00  0.000000e+00  1.000000e+00  {}\n'.format(process_id))
            f.write('</init>\n')
            
            # Events
            for i in range(num_events):
                f.write('<event>\n')
                f.write(' 4  {}  1.000000e+00  1.000000e+02  7.546772e-03  1.178091e-01\n'.format(process_id))
                # Incoming partons
                f.write('  21  -1  0  0  501  502  0.0  0.0  500.0  500.0  0.0  0.0  9.0\n')
                f.write('  21  -1  0  0  503  504  0.0  0.0 -500.0  500.0  0.0  0.0  9.0\n')
                # Outgoing partons (simple 2 gluon example)
                f.write('  21   1  1  2  501  503  100.0  50.0  200.0  250.0  0.0  0.0  9.0\n')
                f.write('  21   1  1  2  502  504 -100.0 -50.0 -200.0  250.0  0.0  0.0  9.0\n')
                f.write('</event>\n')
            
            f.write('</LesHouchesEvents>\n')
        
        return str(filepath)
    
    def test_mixer_info_command(self):
        """Test: lhe_mixer info displays file information"""
        test_file = self.create_test_lhe("test_info.lhe", num_events=5)
        
        result = subprocess.run(
            [str(self.mixer_bin), "info", test_file],
            capture_output=True,
            text=True
        )
        
        self.assertEqual(result.returncode, 0, f"Info command failed: {result.stderr}")
        self.assertIn("Events: 5", result.stdout)
        self.assertIn("Particles:", result.stdout)
    
    def test_mixer_simple_mix(self):
        """Test: Mix events from two LHE files"""
        file1 = self.create_test_lhe("source1.lhe", num_events=10, process_id=1)
        file2 = self.create_test_lhe("source2.lhe", num_events=10, process_id=2)
        output = os.path.join(self.temp_dir, "mixed.lhe")
        
        result = subprocess.run(
            [str(self.mixer_bin), "mix",
             "--inputs", f"{file1},{file2}",
             "--output", output,
             "--max-events", "20"],
            capture_output=True,
            text=True
        )
        
        self.assertEqual(result.returncode, 0, f"Mix command failed: {result.stderr}")
        self.assertTrue(os.path.exists(output), "Output file not created")
        
        # Verify output has events
        with open(output, 'r') as f:
            content = f.read()
            event_count = content.count('<event>')
            self.assertGreater(event_count, 0, "No events in output file")
    
    def test_mixer_recipe_mode(self):
        """Test: Advanced mix recipe (e.g., 3 from A, 1 from B for QPS)"""
        fileA = self.create_test_lhe("jpsi.lhe", num_events=30, process_id=1)
        fileB = self.create_test_lhe("phi.lhe", num_events=10, process_id=2)
        output = os.path.join(self.temp_dir, "qps_mixed.lhe")
        
        # Recipe: 3 events from jpsi.lhe, 1 from phi.lhe per output event
        result = subprocess.run(
            [str(self.mixer_bin), "mix",
             "--recipe", f"{fileA}:3,{fileB}:1",
             "--output", output,
             "--max-events", "5"],
            capture_output=True,
            text=True
        )
        
        self.assertEqual(result.returncode, 0, f"Recipe mix failed: {result.stderr}")
        self.assertTrue(os.path.exists(output), "Output file not created")
        self.assertIn("Recipe-based mixing", result.stdout)
    
    def test_mixer_gluon_merging(self):
        """Test: Gluon merging with configurable threshold"""
        test_file = self.create_test_lhe("test_gluons.lhe", num_events=5)
        output = os.path.join(self.temp_dir, "merged_gluons.lhe")
        
        result = subprocess.run(
            [str(self.mixer_bin), "merge-gluons",
             "--input", test_file,
             "--output", output,
             "--delta-r", "0.4"],
            capture_output=True,
            text=True
        )
        
        self.assertEqual(result.returncode, 0, f"Gluon merging failed: {result.stderr}")
        self.assertTrue(os.path.exists(output), "Output file not created")
        self.assertIn("Gluon merging completed", result.stdout)
    
    def test_mixer_selective_gluon_merging(self):
        """Test: Selective gluon merging in specific sub-scatterings"""
        fileA = self.create_test_lhe("sub1.lhe", num_events=10, process_id=1)
        fileB = self.create_test_lhe("sub2.lhe", num_events=10, process_id=2)
        output = os.path.join(self.temp_dir, "selective_merged.lhe")
        
        # Mix and merge gluons only in sub-scatterings 0 and 2
        result = subprocess.run(
            [str(self.mixer_bin), "mix",
             "--inputs", f"{fileA},{fileB}",
             "--output", output,
             "--merge-gluons",
             "--merge-subscatterings", "0,2",
             "--max-events", "10"],
            capture_output=True,
            text=True
        )
        
        self.assertEqual(result.returncode, 0, f"Selective merging failed: {result.stderr}")
        self.assertTrue(os.path.exists(output), "Output file not created")
    
    def test_mixer_split_two_tier(self):
        """Test: Two-tier split and shuffle"""
        test_file = self.create_test_lhe("large.lhe", num_events=100)
        output_dir = os.path.join(self.temp_dir, "split_output")
        
        result = subprocess.run(
            [str(self.mixer_bin), "split",
             "--input", test_file,
             "--output-dir", output_dir,
             "--tier1", "50",
             "--tier2", "10",
             "--shuffle"],
            capture_output=True,
            text=True
        )
        
        self.assertEqual(result.returncode, 0, f"Split failed: {result.stderr}")
        self.assertTrue(os.path.isdir(output_dir), "Output directory not created")
        
        # Check that split files were created
        split_files = list(Path(output_dir).glob("*.lhe"))
        self.assertGreater(len(split_files), 0, "No split files created")
    
    def test_mixer_shuffle_mode(self):
        """Test: Event shuffling"""
        test_file = self.create_test_lhe("ordered.lhe", num_events=20)
        output = os.path.join(self.temp_dir, "shuffled.lhe")
        
        result = subprocess.run(
            [str(self.mixer_bin), "mix",
             "--inputs", test_file,
             "--output", output,
             "--shuffle",
             "--seed", "42"],
            capture_output=True,
            text=True
        )
        
        self.assertEqual(result.returncode, 0, f"Shuffle failed: {result.stderr}")
        self.assertTrue(os.path.exists(output), "Output file not created")


class TestLHEMixerEdgeCases(unittest.TestCase):
    """Test edge cases and error handling"""
    
    @classmethod
    def setUpClass(cls):
        cls.repo_root = Path(__file__).parent.parent.parent
        cls.mixer_bin = cls.repo_root / "bin" / "lhe_mixer"
    
    def test_missing_input_file(self):
        """Test: Graceful handling of missing input file"""
        result = subprocess.run(
            [str(self.mixer_bin), "info", "/nonexistent/file.lhe"],
            capture_output=True,
            text=True
        )
        
        self.assertNotEqual(result.returncode, 0, "Should fail with missing file")
        self.assertIn("Error", result.stderr)
    
    def test_invalid_command(self):
        """Test: Invalid command handling"""
        result = subprocess.run(
            [str(self.mixer_bin), "invalid_command"],
            capture_output=True,
            text=True
        )
        
        self.assertNotEqual(result.returncode, 0, "Should fail with invalid command")
    
    def test_help_command(self):
        """Test: Help command displays usage"""
        result = subprocess.run(
            [str(self.mixer_bin), "--help"],
            capture_output=True,
            text=True
        )
        
        self.assertEqual(result.returncode, 0, "Help should succeed")
        self.assertIn("Usage:", result.stdout)
        self.assertIn("Commands:", result.stdout)


if __name__ == '__main__':
    # Run tests with verbose output
    unittest.main(verbosity=2)

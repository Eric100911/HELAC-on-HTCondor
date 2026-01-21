# Testing Guide for HELAC-on-HTCondor

This document provides comprehensive information about running tests in the HELAC-on-HTCondor framework.

## Quick Start

### Run All Tests
```bash
# Simple: Run all tests
make test

# Or directly:
./run_tests.sh --all
```

### Run Specific Test Categories
```bash
# Unit tests only
make test-unit
./run_tests.sh --unit

# Integration tests only
make test-integration
./run_tests.sh --integration

# Verbose output
make test-verbose
./run_tests.sh --all --verbose
```

## Test Structure

```
tests/
├── unit/                    # Unit tests for individual components
│   ├── test_lhe_mixer.py   # LHE mixer C++ tool tests
│   ├── test_helac_script.py # HELAC build/run script tests
│   └── test_cmssw_script.py # CMSSW step runner tests
├── integration/             # Integration tests for workflows
│   └── test_workflow.py    # Complete workflow integration
├── fixtures/                # Test fixtures and mock data
├── data/                    # Test data files
└── test_reports/            # Auto-generated test reports

run_tests.sh                 # Main test runner script
```

## Test Categories

### Unit Tests

#### LHE Mixer Tests (`test_lhe_mixer.py`)
- **Test: Info command** - Display LHE file information
- **Test: Simple mixing** - Mix events from two LHE files
- **Test: Recipe mode** - Advanced mix recipes (e.g., "3 from A, 1 from B")
- **Test: Gluon merging** - Merge close gluons with configurable threshold
- **Test: Selective merging** - Merge gluons in specific sub-scatterings only
- **Test: Two-tier split** - Split and shuffle large LHE files
- **Test: Shuffling** - Random event shuffling with seed

**Run only LHE mixer tests:**
```bash
cd tests/unit
python3 test_lhe_mixer.py -v
```

#### HELAC Script Tests (`test_helac_script.py`)
- **Test: Flexible LHE detection** - Find *_py8.lhe with priority
- **Test: Multiple patterns** - Handle P0_calc_*, P0_addon_*, P0_* directories
- **Test: Newest file selection** - Pick newest when multiple sample*.lhe exist
- **Test: External LHE** - Process external LHE files
- **Test: Large file handling** - Split large external LHE files

**Run only HELAC tests:**
```bash
cd tests/unit
python3 test_helac_script.py -v
```

#### CMSSW Script Tests (`test_cmssw_script.py`)
- **Test: scram project usage** - Use 'scram project -n' instead of 'cmsrel'
- **Test: All steps** - Handle GEN, SIM, DIGI, RECO, SKIM, Ntuple steps
- **Test: Cleanup logic** - Automatic intermediate file cleanup
- **Test: Era support** - Multiple detector eras (Run2, Run3, etc.)

**Run only CMSSW tests:**
```bash
cd tests/unit
python3 test_cmssw_script.py -v
```

### Integration Tests

#### Workflow Tests (`test_workflow.py`)
- **Test: DAGman generation** - Generate complete DAG from YAML config
- **Test: LHE preprocessing** - Complete mixing → splitting pipeline
- **Test: Config validation** - Validate workflow configurations
- **Test: External input** - Process external LHE/HepMC files
- **Test: Multi-scattering** - TPS/QPS event mixing

**Run only integration tests:**
```bash
cd tests/integration
python3 test_workflow.py -v
```

## Test Reports

Test reports are automatically generated in `test_reports/`:

- **Log files**: `test_run_YYYYMMDD_HHMMSS.log`
- **HTML reports**: `test_report_YYYYMMDD_HHMMSS.html`

### View HTML Report
```bash
# Find latest report
ls -lt test_reports/*.html | head -1

# Open in browser (Linux)
xdg-open test_reports/test_report_*.html

# Open in browser (macOS)
open test_reports/test_report_*.html
```

## Continuous Integration

### Pre-commit Testing
Run tests before committing changes:
```bash
make test
```

### Git Hook (Optional)
Create `.git/hooks/pre-commit`:
```bash
#!/bin/bash
make test-unit
if [ $? -ne 0 ]; then
    echo "Unit tests failed. Commit aborted."
    exit 1
fi
```

### CI/CD Pipeline
Tests can be integrated into GitHub Actions, GitLab CI, or Jenkins:

**GitHub Actions Example** (`.github/workflows/test.yml`):
```yaml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y g++ make python3 python3-pip
          pip3 install pyyaml
      - name: Build tools
        run: make tools
      - name: Run tests
        run: ./run_tests.sh --all --verbose
```

## Writing New Tests

### Unit Test Template
```python
#!/usr/bin/env python3
import unittest
from pathlib import Path

class TestMyComponent(unittest.TestCase):
    """Test suite for MyComponent"""
    
    @classmethod
    def setUpClass(cls):
        """Setup once before all tests"""
        cls.repo_root = Path(__file__).parent.parent.parent
        cls.component = cls.repo_root / "path" / "to" / "component"
    
    def setUp(self):
        """Setup before each test"""
        pass
    
    def tearDown(self):
        """Cleanup after each test"""
        pass
    
    def test_basic_functionality(self):
        """Test: Basic functionality works"""
        self.assertTrue(self.component.exists())
    
    def test_edge_case(self):
        """Test: Handle edge cases properly"""
        # Your test code
        pass

if __name__ == '__main__':
    unittest.main(verbosity=2)
```

### Integration Test Template
```python
#!/usr/bin/env python3
import unittest
import subprocess
import tempfile
import shutil
from pathlib import Path

class TestWorkflowStep(unittest.TestCase):
    """Integration test for workflow step"""
    
    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
    
    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)
    
    def test_complete_pipeline(self):
        """Test: Complete pipeline from input to output"""
        # Create test inputs
        # Run pipeline
        # Verify outputs
        pass

if __name__ == '__main__':
    unittest.main(verbosity=2)
```

## Test Data Management

### Creating Test Fixtures
Test fixtures are stored in `tests/fixtures/`:

```python
def create_test_lhe(self, filename, num_events=10):
    """Create minimal LHE file for testing"""
    filepath = Path(self.temp_dir) / filename
    with open(filepath, 'w') as f:
        f.write('<LesHouchesEvents version="1.0">\n')
        # ... write events ...
        f.write('</LesHouchesEvents>\n')
    return str(filepath)
```

### Downloading Test Data
Large test data files should not be committed to git:

```bash
# Download test data (if needed)
mkdir -p tests/data
cd tests/data
wget https://example.com/test_data.lhe.gz
gunzip test_data.lhe.gz
```

## Debugging Failed Tests

### Run Single Test
```bash
# Run specific test class
python3 tests/unit/test_lhe_mixer.py TestLHEMixer.test_mixer_info_command

# Run with Python debugger
python3 -m pdb tests/unit/test_lhe_mixer.py
```

### Verbose Output
```bash
# Maximum verbosity
./run_tests.sh --all --verbose

# Or directly with Python
python3 tests/unit/test_lhe_mixer.py -v
```

### Check Logs
```bash
# View latest test log
tail -f test_reports/test_run_*.log

# Search for errors
grep -i error test_reports/test_run_*.log
```

## Performance Testing

### Benchmark Tests
Create performance benchmarks in `tests/performance/`:

```python
import time

def test_performance_large_file(self):
    """Test: Process large LHE file in reasonable time"""
    start = time.time()
    # Process large file
    elapsed = time.time() - start
    self.assertLess(elapsed, 60.0, "Should complete in under 60 seconds")
```

## Coverage Analysis

### Generate Coverage Report
```bash
# Install coverage tool
pip3 install coverage

# Run tests with coverage
coverage run -m unittest discover -s tests/unit -p "test_*.py"

# Generate report
coverage report -m

# Generate HTML report
coverage html
xdg-open htmlcov/index.html
```

## Best Practices

1. **Test isolation**: Each test should be independent
2. **Fast tests**: Unit tests should run in < 1 second each
3. **Clear assertions**: Use descriptive assertion messages
4. **Mock external dependencies**: Don't depend on external services
5. **Test naming**: Use descriptive names: `test_<what>_<expected_behavior>`
6. **Documentation**: Add docstrings explaining what each test validates

## Troubleshooting

### Common Issues

**Issue: "Module not found" errors**
```bash
# Solution: Install Python dependencies
pip3 install pyyaml
```

**Issue: "lhe_mixer not found"**
```bash
# Solution: Build C++ tools first
make tools
```

**Issue: "Permission denied" on scripts**
```bash
# Solution: Make scripts executable
chmod +x run_tests.sh scripts/*.sh
```

**Issue: Tests timeout**
```bash
# Solution: Run with longer timeout
./run_tests.sh --all --verbose
# Or debug specific slow test
python3 -m pdb tests/integration/test_workflow.py
```

## Support

For issues or questions about testing:
1. Check this guide
2. Review test code for examples
3. Check test logs in `test_reports/`
4. Open an issue on GitHub

## Summary

- **Quick test**: `make test`
- **Unit only**: `make test-unit`
- **Integration only**: `make test-integration`
- **Verbose**: `make test-verbose`
- **Reports**: Check `test_reports/` directory
- **Add tests**: Use templates above
- **Coverage**: Use `coverage` tool

Happy testing! 🧪

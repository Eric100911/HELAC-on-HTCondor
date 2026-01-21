# Integrated Monte Carlo Simulation Workflow
# =========================================

A comprehensive HTCondor DAGMan-based Monte Carlo production system for CMS physics 
analysis, integrating multiple parton scattering (MPS) simulations for simultaneous
quarkonium production including J/ψ+J/ψ+Υ, J/ψ+J/ψ+φ, and J/ψ+Υ+φ final states.

## Overview

This repository provides an integrated workflow framework that combines:
- **HELAC-Onia** matrix element generation
- **Pythia 8** parton showering (normal and phi-enriched modes)
- **LHE file preprocessing** (split, shuffle, mixing, gluon merging)
- **CMS simulation chain** (GEN-SIM-DIGI-RECO-MiniAOD-Ntuple)
- **HTCondor DAGMan** workflow orchestration

## Related Repositories

This project integrates functionality from:
- [@Eric100911/HELAC-on-HTCondor](https://github.com/Eric100911/HELAC-on-HTCondor) - HELAC-Onia on HTCondor
- [@Eric100911/LHE-to-SKIM](https://github.com/Eric100911/LHE-to-SKIM) - LHE to SKIM processing
- [@Eric100911/LHE-two-tier-split](https://github.com/Eric100911/LHE-two-tier-split) - Two-tier LHE splitting
- [@Eric100911/LHEventFastMixer](https://github.com/Eric100911/LHEventFastMixer) - Fast LHE event mixing
- [@Eric100911/Ntuplizer-on-HTCondor](https://github.com/Eric100911/Ntuplizer-on-HTCondor) - Ntuple production
- [@Endymion2288/Full_MC_Production](https://github.com/Endymion2288/Full_MC_Production) - Full MC production system

## Production Chain

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Matrix Element Generation                             │
│                        (HELAC-Onia)                                     │
│     Single HTCondor job for all seeds → Auto-harvest LHE (~10GB)        │
└────────────────────────────────┬────────────────────────────────────────┘
                                 ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                     LHE Preprocessing                                    │
│   Two-tier Split/Shuffle → Event Mixing (C++) → Gluon Merging          │
└────────────────────────────────┬────────────────────────────────────────┘
                                 ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                     Parton Showering                                     │
│            Pythia 8 (Normal / Phi-enriched modes)                       │
│         HepMC output for color octets / repeated showering              │
└────────────────────────────────┬────────────────────────────────────────┘
                                 ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                   CMS Simulation Pipeline                                │
│  GEN → SIM → DIGI → RECO → SKIM (MiniAOD) → Ntuple                     │
│  Auto-cleanup intermediate files; preserve LHE/HepMC/MiniAOD/Ntuple     │
└─────────────────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
HELAC-on-HTCondor/
├── run_workflow.sh              # Main workflow orchestrator
├── workflow/
│   ├── workflow_config.yaml.example  # Example configuration
│   ├── generate_dag.py          # DAGman workflow generator
│   └── config/                  # DAGMan configuration
├── src/
│   ├── lhe_mixer.hpp            # C++ LHE mixer (header-only)
│   ├── lhe_mixer.cpp            # LHE mixer CLI
│   ├── hepmc_mixer.cpp          # HepMC event mixer (multi-source)
│   └── gluon_merger.cpp         # Gluon merging tool
├── scripts/
│   ├── helac_build_run.sh       # HELAC-Onia build and run
│   ├── run_matrix_element_batch.sh  # Batch ME generation
│   ├── harvest_lhe.sh           # LHE harvesting
│   ├── split_shuffle.sh         # Two-tier split/shuffle
│   ├── run_pythia_shower.sh     # Pythia8 showering
│   ├── run_cmssw_step.sh        # CMSSW step runner
│   └── cleanup_intermediate.sh  # Cleanup tool
├── configs/
│   ├── run_HELAC.ho.tpl         # HELAC-Onia template
│   ├── addon/                   # HELAC addon configs
│   ├── input/                   # User input configs
│   └── cmssw/                   # CMSSW configuration files
├── templates/                   # HTCondor submit templates
└── patch/                       # Source patches
```

## Physics Campaigns

### JJP Campaigns (J/ψ + J/ψ + φ)

| Campaign | Topology | Inputs | Shower Modes | Description |
|----------|----------|--------|--------------|-------------|
| JJP_SPS | SPS | 2J/ψ+g | phi | Single parton scattering |
| JJP_DPS1 | DPS | J/ψ+g × 2 | normal, phi | Two J/ψ+g mixed |
| JJP_DPS2 | DPS | 2J/ψ+g, gg | normal, phi | 2J/ψ+g with dijet |
| JJP_TPS | TPS | J/ψ+g × 2, gg | normal, normal, phi | Triple parton scattering |

### JUP Campaigns (J/ψ + Υ + φ)

| Campaign | Topology | Inputs | Shower Modes | Description |
|----------|----------|--------|--------------|-------------|
| JUP_SPS | SPS | J/ψ+Υ+g | phi | Single parton scattering |
| JUP_DPS1 | DPS | J/ψ+g, Υ+g | phi, normal | J/ψ(phi) + Υ(normal) |
| JUP_DPS2 | DPS | J/ψ+g, Υ+g | normal, phi | J/ψ(normal) + Υ(phi) |
| JUP_TPS | TPS | J/ψ+g, Υ+g, gg | normal, normal, phi | Triple parton scattering |

## Quick Start

### 1. Setup and Build

```bash
# Clone the repository
git clone https://github.com/Eric100911/HELAC-on-HTCondor.git
cd HELAC-on-HTCondor

# Build C++ tools (LHE mixer, Pythia8 shower)
make tools

# Run tests to verify installation
make test
```

### 2. Configure Workflow

Copy and edit the example configuration:

```bash
cp workflow/workflow_config.yaml.example workflow/workflow_config.yaml
# Edit settings for your physics process
```

### 2. Generate DAGMan Workflow

```bash
# Generate DAG from configuration
python workflow/generate_dag.py workflow/workflow_config.yaml --output workflow/

# Or use the orchestrator
./run_workflow.sh workflow/workflow_config.yaml --dry-run
```

### 3. Submit to HTCondor

```bash
# Make log directory
mkdir -p log

# Submit DAG
condor_submit_dag workflow/generated.dag

# Monitor progress
condor_q
tail -f workflow/generated.dag.dagman.out
```

### 4. Alternative: CRAB Submission

For larger scale production, configure CRAB submission:

```yaml
# In workflow_config.yaml
submission:
  crab:
    enabled: true
    site: "T2_CH_CERN"
```

## Key Features

### 1. Efficient Matrix Element Generation
- **Single HTCondor job** processes multiple seeds instead of thousands of separate jobs
- Automatic LHE harvesting from EOS (up to ~10GB files)
- Configurable seed range and physics parameters
- **Flexible output handling**: Automatically finds LHE files in various HELAC output locations
  (`PROC_HO_*/P0_*/output/sample*.lhe`, `sample*py8.lhe`, etc.)

### 2. High-Performance LHE Processing (C++)
- Two-tier split and shuffle for large event samples
- C++ event mixer for DPS/TPS/QPS topology generation (requirement 6)
- **Advanced mix recipes**: Specify counts per source, e.g., "3 from A, 1 from B" for QPS
- **Selective gluon merging**: Specify which sub-scatterings to merge gluons in
- Gluon merging with configurable ΔR threshold

#### Mix Recipe Examples
```bash
# Simple DPS: 1 event from each source
./bin/lhe_mixer mix --recipe "jpsi.lhe:1,upsilon.lhe:1" -o dps.lhe

# TPS: J/psi + J/psi + gg
./bin/lhe_mixer mix --recipe "jpsi.lhe:2,gg.lhe:1" -o tps.lhe

# QPS: J/psi + J/psi + J/psi + phi (3 from source A, 1 from B)
./bin/lhe_mixer mix --recipe "jpsi.lhe:3,phi.lhe:1" -o qps.lhe --merge-gluons

# Selective gluon merging (only in sub-scatterings 0 and 2)
./bin/lhe_mixer mix --recipe "a.lhe:2,b.lhe:1" -o out.lhe --merge-gluons --merge-subscatterings 0,2
```

### 3. Flexible Showering
- Normal Pythia 8 showering
- Phi-enriched mode with repeated attempts for hard φ meson production
- **Standalone Pythia 8 implementation** (not via cmsRun) - requirement fulfilled
- **Upsilon decay settings**: 553, 100553, 200553 → μ+μ- properly configured
- **CP5 tuning as default**, or user-specified tuning
- HepMC output preservation for color octet states

### 4. Automatic File Management
- Intermediate files automatically deleted after use (via cleanup job in DAGman)
- Preserves: LHE, HepMC, MiniAOD, Ntuple files
- Configurable per-step retention policy
- **CMSSW setup uses** `scram project -n` **for safety** (not `cmsrel`)

### 5. Extensible Architecture
- YAML-based workflow configuration
- Plugin system for new physics processes
- Support for non-prompt J/ψ from b quarks
- Multiple subscattering extensions

## Building C++ Tools

```bash
# Build all tools
make tools

# Or build individually
make bin/lhe_mixer          # LHE event mixer
make bin/pythia8_shower     # Standalone Pythia8 shower
```

### Prerequisites

For Pythia8 shower tool, ensure CMSSW environment is set up:
```bash
source /cvmfs/cms.cern.ch/cmsset_default.sh
cd CMSSW_*/src && cmsenv && cd -
```

## Testing

Comprehensive test suite is available for all components:

```bash
# Run all tests
make test

# Run specific test categories
make test-unit              # Unit tests only
make test-integration       # Integration tests only
make test-verbose           # Verbose output

# Or use the test runner directly
./run_tests.sh --all        # All tests
./run_tests.sh --unit       # Unit tests
./run_tests.sh --integration # Integration tests
```

Test reports are automatically generated in `test_reports/` with HTML summaries.
See [TESTING.md](TESTING.md) for detailed testing documentation.

## Key Features (Detailed)

### 1. Efficient Matrix Element Generation

## Enhanced Features

### Flexible HELAC-Onia Output Handling

The workflow now automatically searches for LHE files in various HELAC output locations:

1. **Priority for Pythia8-ready files**: `*_py8.lhe` files are preferred
2. **Multiple output patterns**: Searches in `P0_calc_*`, `P0_addon_*`, `P0_*` subdirectories
3. **Newest file selection**: When multiple `sample*.lhe` files exist, picks the newest
4. **Fallback search**: Falls back to any `.lhe` file if specific patterns not found

This flexibility ensures the workflow works with different HELAC-Onia configurations and add-ons.

### Advanced LHE Mixing Recipes

Support for complex multi-parton scattering topologies:

```bash
# Simple DPS: 1 event from each source
./bin/lhe_mixer mix --recipe "jpsi.lhe:1,upsilon.lhe:1" -o dps.lhe

# TPS: J/ψ + J/ψ + gg
./bin/lhe_mixer mix --recipe "jpsi.lhe:2,gg.lhe:1" -o tps.lhe

# QPS: 3 J/ψ + 1 φ (Quadruple Parton Scattering)
./bin/lhe_mixer mix --recipe "jpsi.lhe:3,phi.lhe:1" -o qps.lhe

# With selective gluon merging (only in sub-scatterings 0 and 2)
./bin/lhe_mixer mix --recipe "a.lhe:2,b.lhe:1" -o out.lhe \
  --merge-gluons --merge-subscatterings 0,2
```

### Standalone Pythia 8 Showering

Fully standalone Pythia 8 implementation (not via cmsRun):

```bash
# Basic usage
./bin/pythia8_shower --input events.lhe --output events.hepmc

# With CP5 tuning (default)
./bin/pythia8_shower --input events.lhe --output events.hepmc --tune CP5

# Phi-enriched mode
./bin/pythia8_shower --input events.lhe --output events.hepmc \
  --mode phi --max-phi-attempts 100

# Color-octet mode for charmonium/bottomonium
./bin/pythia8_shower --input events.lhe --output events.hepmc \
  --mode color-octet
```

Features:
- **Upsilon decays**: Properly configured for 553, 100553, 200553 → μ+μ-
- **CP5 tuning**: Default tuning, or specify Monash2013, 4C
- **Phi enrichment**: Repeated showering for hard φ meson production
- **Color octets**: Special handling for color octet states

### External LHE Input Support

The workflow supports external LHE files from other generators:

```yaml
# In workflow_config.yaml
matrix_element:
  external_lhe:
    enabled: true
    sources:
      - path: /path/to/external_jpsi.lhe
        post_process: true  # Apply splitting/shuffling
      - path: /path/to/external_upsilon.lhe
        post_process: false # Use as-is
```

Large external LHE files are automatically split if needed.

## Troubleshooting

### Build Issues

**Pythia8 shower build fails:**
```bash
# Ensure CMSSW environment is set
source /cvmfs/cms.cern.ch/cmsset_default.sh
cd CMSSW_*/src && cmsenv && cd -

# Check environment variables
echo $PYTHIA8
echo $HEPMC_DIR

# If not set, set manually or use different CMSSW version
```

**LHE mixer build fails:**
```bash
# Requires C++17 compiler
g++ --version  # Should be >= 7.0

# Build manually
cd src
g++ -std=c++17 -O2 lhe_mixer.cpp -o ../bin/lhe_mixer
```

### Workflow Issues

**No LHE files found:**
Check the HELAC output directories manually:
```bash
find . -name "*.lhe" -type f
```

The improved scripts search multiple patterns automatically.

**Tests failing:**
```bash
# Run with verbose output
./run_tests.sh --all --verbose

# Check specific test
cd tests/unit
python3 test_lhe_mixer.py -v
```

For more help, see [TESTING.md](TESTING.md) for comprehensive testing documentation.

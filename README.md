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

### 1. Configure Workflow

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

### 2. High-Performance LHE Processing (C++)
- Two-tier split and shuffle for large event samples
- C++ event mixer for DPS/TPS topology generation (requirement 6)
- Gluon merging with configurable ΔR threshold

### 3. Flexible Showering
- Normal Pythia 8 showering
- Phi-enriched mode with repeated attempts for hard φ meson production
- HepMC output preservation for color octet states

### 4. Automatic File Management
- Intermediate files automatically deleted after use
- Preserves: LHE, HepMC, MiniAOD, Ntuple files
- Configurable per-step retention policy

### 5. Extensible Architecture
- YAML-based workflow configuration
- Plugin system for new physics processes
- Support for non-prompt J/ψ from b quarks
- Multiple subscattering extensions

## Building C++ Tools

```bash
# Ensure CMSSW environment is set up
source /cvmfs/cms.cern.ch/cmsset_default.sh
cd CMSSW_*/src && cmsenv && cd -

# Build LHE mixer
g++ -std=c++17 -O2 src/lhe_mixer.cpp -o bin/lhe_mixer

# Build HepMC mixer (requires HepMC2 and HepMC3)
g++ -std=c++17 -O2 src/hepmc_mixer.cpp -o bin/hepmc_mixer \
    -I$HEPMC3/include -I$HEPMC2/include \
    -L$HEPMC3/lib64 -L$HEPMC2/lib \
    -lHepMC3 -lHepMC
```

## Configuration Reference

See `workflow/workflow_config.yaml.example` for complete documentation of all
configuration options including:
- Matrix element settings (seeds, physics cuts, generator options)
- Preprocessing (split sizes, mixing sources, gluon merging)
- Showering (modes, HepMC retention, phi enrichment)
- Simulation chain (CMSSW versions, era configs, file retention)
- Submission (HTCondor/CRAB options)

## Authors

- MC Production Team

## License

This project is available for scientific use.

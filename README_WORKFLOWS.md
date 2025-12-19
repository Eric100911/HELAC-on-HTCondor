# HELAC-on-HTCondor Workflows

This repository supports two distinct workflows for generating GENSIM files:

## Workflows

### 1. Full Workflow (HELAC Generation + Shower)
Generates events from scratch using HELAC-Onia, then showers them with Pythia8.

**Usage:**
```bash
make submit_full
```

**What it does:**
1. Builds HELAC-Onia
2. Generates LHE events with specified seed
3. Splits LHE into 30-event chunks
4. Showers each chunk with Pythia8
5. Converts to GENSIM format
6. Merges all GENSIM chunks

**Files involved:**
- `main_full.sh` - Main HTCondor wrapper
- `scripts/helac_full_workflow.sh` - Full workflow orchestration
- `scripts/process_lhe.sh` - LHE processing and showering
- `condor_submit_full.sub` - HTCondor submit file

### 2. Shower-Only Workflow (Existing LHE Files)
Processes pre-existing LHE files without running HELAC-Onia generation.

**Usage:**
```bash
make submit_shower LHE_SOURCE_DIR=/path/to/lhe/files
```

**Environment variables:**
- `LHE_SOURCE_DIR` - Directory containing existing LHE files (required)
- `LHE_ARCHIVE_DIR` - Directory to archive LHE files (optional)

**What it does:**
1. Finds LHE file for the given seed
2. Optionally archives the LHE file
3. Splits LHE into 30-event chunks
4. Showers each chunk with Pythia8
5. Converts to GENSIM format
6. Merges all GENSIM chunks

**Files involved:**
- `main_shower.sh` - Main HTCondor wrapper
- `scripts/shower_existing_lhe.sh` - Shower workflow for existing LHE
- `scripts/process_lhe.sh` - LHE processing and showering (shared)
- `condor_submit_shower.sub` - HTCondor submit file

## Modular Scripts

The workflow has been refactored into modular components:

### Core Scripts

**`scripts/common_env.sh`**
- Common environment setup for both workflows
- Sets up CVMFS, HepMC, Pythia8, and Boost libraries
- Configurable via environment variables

**`scripts/process_lhe.sh`**
- Reusable LHE processing module
- Splits LHE files into chunks
- Compiles and runs Pythia8 showering
- Optionally archives LHE files

**`scripts/helac_full_workflow.sh`**
- Full HELAC-Onia workflow
- Builds HELAC-Onia if needed
- Generates events
- Calls `process_lhe.sh` for showering

**`scripts/shower_existing_lhe.sh`**
- Workflow for existing LHE files
- Finds and prepares LHE file
- Calls `process_lhe.sh` for showering

## Configuration

### Event Splitting
Control chunk size via environment variable:
```bash
export EVENTS_PER_CHUNK=30  # Default: 30
```

### Event Splitter Tool
Override the event splitter path:
```bash
export EVENT_SPLITTER=/path/to/event_splitter
```
Default: `/afs/cern.ch/user/c/chiw/condor/LHE-split/build/slc7_amd64_gcc12/event_splitter`

### LHE Archiving
Archive processed LHE files:
```bash
export LHE_ARCHIVE_DIR=/path/to/archive
```

## Benefits of Modular Design

1. **Reusability**: `process_lhe.sh` is shared between workflows
2. **Maintainability**: Each script has a single, clear purpose
3. **Flexibility**: Easy to add new workflows or modify existing ones
4. **Testing**: Individual components can be tested independently
5. **Efficiency**: Shower-only workflow avoids HELAC-Onia build overhead

## Backward Compatibility

The original workflow is preserved:
- `scripts/helac_build_run.sh` - Original monolithic script (still functional)
- `main.sh` - Original main wrapper
- `make submit` - Alias for `make submit_full`

## LHE File Naming Convention

For shower-only workflow, LHE files should follow one of these patterns:
- `sample_${SEED}.lhe`
- `events_${SEED}.lhe`
- `lhe_${SEED}.lhe`
- `*_${SEED}.lhe`

Where `${SEED}` is the job seed number.

## Performance

**Compilation Optimization:**
- Single Pythia8 compilation per job (not per chunk)
- For 67 chunks (2000 events): Eliminates 66 redundant compilations
- Saves ~335 MB disk I/O and significant processing time

**Disk Usage:**
- Automatic cleanup of intermediate files
- Only final GENSIM output and log files retained
- Chunk-specific command files cleaned after processing

## Example Usage

### Full workflow with custom chunk size
```bash
export EVENTS_PER_CHUNK=25
make submit_full
```

### Shower-only workflow with archiving
```bash
export LHE_ARCHIVE_DIR=/eos/user/c/chiw/LHE_archive
make submit_shower LHE_SOURCE_DIR=/eos/user/c/chiw/LHE_files
```

### Local testing
```bash
# Test full workflow
bash scripts/helac_full_workflow.sh -s 11

# Test shower-only workflow
bash scripts/shower_existing_lhe.sh -l /path/to/file.lhe -s 11
```

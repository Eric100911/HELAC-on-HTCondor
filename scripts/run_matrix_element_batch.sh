#!/bin/bash
#
# run_matrix_element_batch.sh - Batch Matrix Element Generation
#
# Runs HELAC-Onia for multiple seeds in a single HTCondor job.
# This is more efficient than submitting thousands of individual jobs.
#
# Usage: ./run_matrix_element_batch.sh <start_seed> <end_seed>
#

set -e

START_SEED=${1:-11}
END_SEED=${2:-20}
WORKDIR=$(pwd)

# Colors for output
log_info() { echo "[INFO] $1"; }
log_ok() { echo "[OK] $1"; }
log_error() { echo "[ERROR] $1"; }

log_info "Starting batch matrix element generation"
log_info "  Seeds: ${START_SEED} to ${END_SEED}"
log_info "  Working directory: ${WORKDIR}"

# Fundamental environment variables
source /cvmfs/cms.cern.ch/cmsset_default.sh

# Unpack configuration and patches
if [ -f condor_submit.tar ]; then
    tar -xvf condor_submit.tar
else
    log_error "condor_submit.tar not found"
    exit 1
fi

# Check required files
if [ ! -f scripts/helac_build_run.sh ]; then
    log_error "scripts/helac_build_run.sh not found"
    exit 1
fi

# Build HELAC-Onia once
log_info "Building HELAC-Onia (first run with -n flag)..."
cmssw-el7 --command-to-run "source scripts/helac_build_run.sh -n -s ${START_SEED}"

BUILD_STATUS=$?
if [ $BUILD_STATUS -ne 0 ]; then
    log_error "HELAC-Onia build failed"
    exit 1
fi

# Collect output files
mkdir -p output

# Run for each seed (after initial build)
for seed in $(seq $START_SEED $END_SEED); do
    log_info "Processing seed: ${seed}"
    
    # Run HELAC-Onia (without rebuild)
    cmssw-el7 --command-to-run "source scripts/helac_build_run.sh -s ${seed}"
    
    RUN_STATUS=$?
    if [ $RUN_STATUS -ne 0 ]; then
        log_error "HELAC-Onia run failed for seed ${seed}"
        continue
    fi
    
    # Move LHE file to output directory
    if [ -f sample_pp_nonia_mps.lhe ]; then
        mv sample_pp_nonia_mps.lhe output/sample_pp_nonia_mps_${seed}.lhe
        log_ok "Generated LHE for seed ${seed}"
    else
        log_error "LHE file not found for seed ${seed}"
    fi
done

# Count generated files
N_GENERATED=$(ls -1 output/*.lhe 2>/dev/null | wc -l)
log_info "Generated ${N_GENERATED} LHE files"

# Create manifest
ls -la output/*.lhe > output/manifest.txt

log_ok "Batch matrix element generation complete"

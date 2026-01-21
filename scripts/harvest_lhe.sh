#!/bin/bash
#
# harvest_lhe.sh - LHE File Harvesting
#
# Collects generated LHE files and transfers them to EOS storage.
#
# Usage: ./harvest_lhe.sh <destination_dir>
#

set -e

DESTINATION=${1:-/eos/user/c/chiw/MC_samples/LHE}
WORKDIR=$(pwd)

log_info() { echo "[INFO] $1"; }
log_ok() { echo "[OK] $1"; }
log_error() { echo "[ERROR] $1"; }

log_info "Harvesting LHE files"
log_info "  Destination: ${DESTINATION}"

# Ensure destination exists
mkdir -p "${DESTINATION}" || {
    log_error "Cannot create destination directory"
    exit 1
}

# Find and copy LHE files
if [ -d "output" ]; then
    N_FILES=$(ls -1 output/*.lhe 2>/dev/null | wc -l)
    log_info "Found ${N_FILES} LHE files to harvest"
    
    for lhe_file in output/*.lhe; do
        if [ -f "$lhe_file" ]; then
            filename=$(basename "$lhe_file")
            log_info "Copying ${filename}..."
            cp "$lhe_file" "${DESTINATION}/${filename}"
        fi
    done
    
    log_ok "Harvested ${N_FILES} files to ${DESTINATION}"
else
    log_error "No output directory found"
    exit 1
fi

# Verify transfer
N_DEST=$(ls -1 ${DESTINATION}/*.lhe 2>/dev/null | wc -l)
log_info "Destination now contains ${N_DEST} LHE files"

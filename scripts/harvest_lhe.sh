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

# Find and copy LHE files from multiple possible locations
# Support requirement: flexible LHE output handling
N_HARVESTED=0

# Search patterns for LHE files:
# 1. output/*.lhe (batch script output)
# 2. PROC_HO_*/P0_*/output/sample*.lhe (direct HELAC output)
# 3. *.lhe in working directory (standalone runs)

log_info "Searching for LHE files..."

# Pattern 1: output directory
if [ -d "output" ]; then
    for lhe_file in output/*.lhe; do
        if [ -f "$lhe_file" ]; then
            filename=$(basename "$lhe_file")
            
            # Prefer *_py8.lhe files if available (requirement)
            if [[ "$filename" == *"_py8.lhe" ]]; then
                log_info "Copying Pythia8-ready: ${filename}"
            else
                log_info "Copying: ${filename}"
            fi
            
            cp "$lhe_file" "${DESTINATION}/${filename}"
            ((N_HARVESTED++))
        fi
    done
fi

# Pattern 2: HELAC output directories
while IFS= read -r lhe_file; do
    if [ -f "$lhe_file" ]; then
        # Generate unique filename based on path
        dir_path=$(dirname "$lhe_file")
        proc_name=$(echo "$dir_path" | grep -oP 'P0_\K[^/]+' || echo "unknown")
        filename=$(basename "$lhe_file")
        dest_filename="${proc_name}_${filename}"
        
        log_info "Copying from HELAC output: ${dest_filename}"
        cp "$lhe_file" "${DESTINATION}/${dest_filename}"
        ((N_HARVESTED++))
    fi
done < <(find . -path "*/PROC_HO_*/P0_*/output/*.lhe" -type f 2>/dev/null)

# Pattern 3: Working directory (but exclude already copied files)
for lhe_file in *.lhe; do
    if [ -f "$lhe_file" ] && [ ! -f "${DESTINATION}/$lhe_file" ]; then
        log_info "Copying from workdir: ${lhe_file}"
        cp "$lhe_file" "${DESTINATION}/${lhe_file}"
        ((N_HARVESTED++))
    fi
done 2>/dev/null || true

if [ $N_HARVESTED -eq 0 ]; then
    log_error "No LHE files found to harvest"
    log_info "Searched locations:"
    log_info "  - output/*.lhe"
    log_info "  - PROC_HO_*/P0_*/output/*.lhe"
    log_info "  - *.lhe (working directory)"
    exit 1
fi

log_ok "Harvested ${N_HARVESTED} files to ${DESTINATION}"

# Verify transfer
N_DEST=$(ls -1 ${DESTINATION}/*.lhe 2>/dev/null | wc -l)
log_info "Destination now contains ${N_DEST} LHE files"

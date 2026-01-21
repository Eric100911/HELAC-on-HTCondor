#!/bin/bash
#
# split_shuffle.sh - Two-tier LHE Split and Shuffle
#
# Splits large LHE files into smaller chunks with optional shuffling.
# Implements a two-tier structure for efficient processing.
#
# Usage: ./split_shuffle.sh <tier1_size> <tier2_size>
#

set -e

TIER1_SIZE=${1:-10000}
TIER2_SIZE=${2:-1000}
INPUT_DIR=${3:-.}
OUTPUT_DIR=${4:-split_output}

log_info() { echo "[INFO] $1"; }
log_ok() { echo "[OK] $1"; }
log_error() { echo "[ERROR] $1"; }

log_info "Two-tier LHE split and shuffle"
log_info "  Tier-1 size: ${TIER1_SIZE} events"
log_info "  Tier-2 size: ${TIER2_SIZE} events"
log_info "  Input dir: ${INPUT_DIR}"
log_info "  Output dir: ${OUTPUT_DIR}"

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# Check if C++ tool is available
if [ -f "bin/lhe_mixer" ]; then
    log_info "Using C++ LHE mixer"
    
    for lhe_file in ${INPUT_DIR}/*.lhe; do
        if [ -f "$lhe_file" ]; then
            basename_file=$(basename "$lhe_file" .lhe)
            log_info "Splitting ${basename_file}..."
            
            ./bin/lhe_mixer split \
                --input "$lhe_file" \
                --output-dir "${OUTPUT_DIR}/${basename_file}" \
                --tier1 ${TIER1_SIZE} \
                --tier2 ${TIER2_SIZE} \
                --shuffle
        fi
    done
else
    log_info "Using Python fallback for splitting"
    
    python3 - "${INPUT_DIR}" "${OUTPUT_DIR}" "${TIER1_SIZE}" "${TIER2_SIZE}" <<'EOF'
import sys
import os
import random
import re

input_dir = sys.argv[1]
output_dir = sys.argv[2]
tier1_size = int(sys.argv[3])
tier2_size = int(sys.argv[4])

def parse_lhe(filename):
    """Parse LHE file and return events."""
    events = []
    header = []
    init_block = []
    
    in_header = True
    in_init = False
    current_event = []
    
    with open(filename, 'r') as f:
        for line in f:
            if '<init>' in line:
                in_header = False
                in_init = True
                continue
            if '</init>' in line:
                in_init = False
                continue
            if '<event>' in line:
                current_event = [line]
                continue
            if '</event>' in line:
                current_event.append(line)
                events.append(''.join(current_event))
                current_event = []
                continue
            
            if in_header:
                header.append(line)
            elif in_init:
                init_block.append(line)
            elif current_event:
                current_event.append(line)
    
    return header, init_block, events

def write_lhe(filename, header, init_block, events):
    """Write events to LHE file."""
    with open(filename, 'w') as f:
        f.write('<LesHouchesEvents version="1.0">\n')
        f.writelines(header)
        f.write('<init>\n')
        f.writelines(init_block)
        f.write('</init>\n')
        for event in events:
            f.write(event)
        f.write('</LesHouchesEvents>\n')

# Process each LHE file
for lhe_file in os.listdir(input_dir):
    if not lhe_file.endswith('.lhe'):
        continue
    
    filepath = os.path.join(input_dir, lhe_file)
    basename = lhe_file.replace('.lhe', '')
    
    print(f"Processing {lhe_file}...")
    header, init_block, events = parse_lhe(filepath)
    
    # Shuffle events
    random.shuffle(events)
    
    # Two-tier split
    file_output_dir = os.path.join(output_dir, basename)
    os.makedirs(file_output_dir, exist_ok=True)
    
    tier1_idx = 0
    for i in range(0, len(events), tier1_size):
        tier1_events = events[i:i+tier1_size]
        
        tier2_idx = 0
        for j in range(0, len(tier1_events), tier2_size):
            tier2_events = tier1_events[j:j+tier2_size]
            
            outfile = os.path.join(file_output_dir, f"split_{tier1_idx}_{tier2_idx}.lhe")
            write_lhe(outfile, header, init_block, tier2_events)
            tier2_idx += 1
        
        tier1_idx += 1
    
    print(f"  Created {tier1_idx} tier-1 chunks")

print("Split and shuffle complete")
EOF
fi

log_ok "Split and shuffle complete"

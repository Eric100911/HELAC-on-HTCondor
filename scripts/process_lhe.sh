#! /bin/bash
# Process LHE file: split into chunks and run Pythia8 showering
# This script is reusable for both HELAC-generated and existing LHE files
#
# Usage: process_lhe.sh <lhe_file> [output_dir]
#
# Arguments:
#   lhe_file    - Path to the LHE file to process
#   output_dir  - Optional output directory for HepMC chunks (default: current directory)
#
# Environment variables:
#   EVENTS_PER_CHUNK  - Number of events per chunk (default: 30)
#   EVENT_SPLITTER    - Path to event_splitter tool
#   HEPMC_DIR         - Path to HepMC installation
#   PYTHIA_INSTALL_PATH - Path to Pythia8 installation
#   LHE_ARCHIVE_DIR   - If set, copy original LHE file here for archiving

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <lhe_file> [output_dir]"
    exit 1
fi

LHE_FILE="$1"
OUTPUT_DIR="${2:-.}"
WORKDIR=$(pwd)

if [ ! -f "$LHE_FILE" ]; then
    echo "Error: LHE file not found: $LHE_FILE"
    exit 1
fi

# Source common environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common_env.sh"

echo "Processing LHE file: $LHE_FILE"
echo "Output directory: $OUTPUT_DIR"

# Optional: Archive the original LHE file
if [ -n "$LHE_ARCHIVE_DIR" ]; then
    echo "Archiving LHE file to: $LHE_ARCHIVE_DIR"
    mkdir -p "$LHE_ARCHIVE_DIR"
    LHE_BASENAME=$(basename "$LHE_FILE")
    cp "$LHE_FILE" "$LHE_ARCHIVE_DIR/$LHE_BASENAME"
    echo "LHE file archived as: $LHE_ARCHIVE_DIR/$LHE_BASENAME"
fi

# Count events in the LHE file
EVENT_COUNT=$(grep -c '/event' "$LHE_FILE" || echo "0")
if [ "$EVENT_COUNT" -eq 0 ]; then
    echo "Error: No events found in LHE file"
    exit 1
fi
echo "Identified ${EVENT_COUNT} events in LHE file."

# Split LHE file into chunks of 30 events to avoid segmentation faults
EVENTS_PER_CHUNK=${EVENTS_PER_CHUNK:-30}
NUM_CHUNKS=$(( (EVENT_COUNT + EVENTS_PER_CHUNK - 1) / EVENTS_PER_CHUNK ))
echo "Splitting LHE file into ${NUM_CHUNKS} chunks of ${EVENTS_PER_CHUNK} events each."

# Create directory for LHE chunks
LHE_CHUNK_DIR="$WORKDIR/lhe_chunks"
mkdir -p "$LHE_CHUNK_DIR"

# Use event_splitter to split the LHE file
EVENT_SPLITTER=${EVENT_SPLITTER:-/afs/cern.ch/user/c/chiw/condor/LHE-split/build/slc7_amd64_gcc12/event_splitter}
if [ ! -x "$EVENT_SPLITTER" ]; then
    echo "Error: event_splitter not found at $EVENT_SPLITTER"
    echo "You can override the path by setting EVENT_SPLITTER environment variable"
    exit 1
fi

$EVENT_SPLITTER -i "$LHE_FILE" \
                -o "$LHE_CHUNK_DIR" \
                -n "$NUM_CHUNKS" \
                --file-prefix "chunk_" \
                --file-offset 0 \
                -seq

# Build Pythia 8 for showering
echo "Building Pythia8 executable..."
cd shower/

g++ -I$PYTHIA_INSTALL_PATH/include \
    -I$HEPMC_DIR/include \
    -L$HEPMC_DIR/lib \
    Pythia82_reshower.cc -o Pythia8.exe \
    -L$PYTHIA_INSTALL_PATH/lib -lpythia8 \
    -lboost_iostreams \
    -L$HEPMC_DIR/lib \
    -lHepMC -ldl -lz

# Process each LHE chunk with Pythia8
echo "Processing ${NUM_CHUNKS} LHE chunks with Pythia8 showering..."

# Backup the original command file since we'll create a symlink
if [ ! -f "Pythia8_lhe.cmnd.orig" ]; then
    cp Pythia8_lhe.cmnd Pythia8_lhe.cmnd.orig
fi

for (( i=0; i<NUM_CHUNKS; i++ )); do
    CHUNK_FILE="$LHE_CHUNK_DIR/chunk_$(printf "%05d" $i).lhe"
    
    if [ ! -f "$CHUNK_FILE" ]; then
        echo "Warning: Chunk file $CHUNK_FILE not found, skipping."
        continue
    fi
    
    # Count events in this chunk
    CHUNK_EVENT_COUNT=$(grep -c '/event' "$CHUNK_FILE")
    echo "Processing chunk $i with ${CHUNK_EVENT_COUNT} events..."
    
    # Create a modified command file for this chunk
    CHUNK_CMND_TEMP="Pythia8_lhe_chunk_${i}.cmnd"
    cp Pythia8_lhe.cmnd.orig "$CHUNK_CMND_TEMP"
    
    # Update the command file to point to this chunk's LHE file and event count
    sed -i -e "s,Beams:LHEF = ../helac_sample.lhe,Beams:LHEF = $CHUNK_FILE,g" "$CHUNK_CMND_TEMP"
    sed -i -e "s,Main:numberOfEvents = 50,Main:numberOfEvents = ${CHUNK_EVENT_COUNT},g" "$CHUNK_CMND_TEMP"
    sed -i -e "s,Main:spareMode1 = 50,Main:spareMode1 = ${CHUNK_EVENT_COUNT},g" "$CHUNK_CMND_TEMP"
    
    # Replace Pythia8_lhe.cmnd with symlink to the chunk-specific command file
    rm -f Pythia8_lhe.cmnd
    ln -s "$CHUNK_CMND_TEMP" Pythia8_lhe.cmnd
    
    # Run the single Pythia8 executable
    ./Pythia8.exe > "pythia8_chunk_${i}.log" 2>&1
    
    # Rename the output to a chunk-specific name
    CHUNK_OUTPUT="Pythia8_lhe_chunk_${i}.hep"
    if [ ! -f "Pythia8_lhe.hep" ]; then
        echo "Error: Failed to generate HepMC output for chunk $i"
        cat "pythia8_chunk_${i}.log"
        exit 1
    fi
    mv Pythia8_lhe.hep "$CHUNK_OUTPUT"
    
    echo "Chunk $i processed successfully, output: $CHUNK_OUTPUT"
    
    # Clean up intermediate files to save disk space
    rm -f "$CHUNK_CMND_TEMP"
done

# Restore the original command file
rm -f Pythia8_lhe.cmnd
mv Pythia8_lhe.cmnd.orig Pythia8_lhe.cmnd

# Copy HepMC chunk files to output directory
echo "Copying HepMC chunk files to output directory..."
mkdir -p "$OUTPUT_DIR"
for (( i=0; i<NUM_CHUNKS; i++ )); do
    CHUNK_HEP="Pythia8_lhe_chunk_${i}.hep"
    if [ -f "$CHUNK_HEP" ]; then
        cp "$CHUNK_HEP" "$OUTPUT_DIR/test_Jpsi1Jpsi1Y8_chunk_${i}.dat"
        echo "Copied $CHUNK_HEP to $OUTPUT_DIR/test_Jpsi1Jpsi1Y8_chunk_${i}.dat"
    else
        echo "Warning: Chunk HepMC file $CHUNK_HEP not found"
    fi
done

echo "All HepMC chunks prepared for GENSIM processing"

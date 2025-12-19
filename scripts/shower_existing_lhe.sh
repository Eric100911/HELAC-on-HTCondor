#! /bin/bash
# Workflow for processing existing LHE files (no HELAC-Onia generation)
#
# Usage: shower_existing_lhe.sh -l <lhe_file> [-s <seed>]
#
# This script processes an existing LHE file without running HELAC-Onia generation.
# Useful for re-processing previously generated LHE files with different shower settings.

set -e

LHE_FILE=""
SEED=11
WORKDIR=$(pwd)

# Parse arguments
while getopts ":l:s:" opt; do
    case $opt in
        l)
            LHE_FILE="$OPTARG"
            ;;
        s)
            SEED="$OPTARG"
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            echo "Usage: $0 -l <lhe_file> [-s <seed>]"
            exit 1
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            exit 1
            ;;
    esac
done

# Validate arguments
if [ -z "$LHE_FILE" ]; then
    echo "Error: LHE file is required"
    echo "Usage: $0 -l <lhe_file> [-s <seed>]"
    exit 1
fi

if [ ! -f "$LHE_FILE" ]; then
    echo "Error: LHE file not found: $LHE_FILE"
    exit 1
fi

if ! [[ "$SEED" =~ ^[0-9]+$ ]]; then
    echo "Error: Seed must be a number."
    exit 1
fi

echo "========================================="
echo "Processing existing LHE file workflow"
echo "LHE file: $LHE_FILE"
echo "Seed: $SEED"
echo "========================================="

# Source common environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common_env.sh"

# Copy LHE file to working directory with standard name
cp "$LHE_FILE" "$WORKDIR/helac_sample.lhe"
echo "Copied LHE file to $WORKDIR/helac_sample.lhe"

# Process the LHE file (split and shower)
"$SCRIPT_DIR/process_lhe.sh" "$WORKDIR/helac_sample.lhe" "$WORKDIR"

echo "========================================="
echo "LHE processing completed successfully!"
echo "HepMC chunk files are ready in: $WORKDIR"
echo "========================================="

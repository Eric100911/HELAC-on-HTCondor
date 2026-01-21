#!/bin/bash
#
# process_external_lhe.sh - Process External LHE Files
#
# Handles external LHE files from other generators with:
# - Automatic file size detection
# - Splitting of large files
# - Optional post-processing (shuffle, mix)
#
# Usage: ./process_external_lhe.sh --input <file> [options]
#

set -e

# Default values
INPUT_FILE=""
OUTPUT_DIR="processed_lhe"
POST_PROCESS=true
AUTO_SPLIT=true
SPLIT_THRESHOLD_MB=1000  # Split files larger than 1GB
TIER1_SIZE=10000
TIER2_SIZE=1000
SHUFFLE=true

log_info() { echo "[INFO] $1"; }
log_ok() { echo "[OK] $1"; }
log_error() { echo "[ERROR] $1"; }
log_warning() { echo "[WARNING] $1"; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --input)
            INPUT_FILE="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --post-process)
            POST_PROCESS="$2"
            shift 2
            ;;
        --no-post-process)
            POST_PROCESS=false
            shift
            ;;
        --auto-split)
            AUTO_SPLIT="$2"
            shift 2
            ;;
        --split-threshold)
            SPLIT_THRESHOLD_MB="$2"
            shift 2
            ;;
        --tier1)
            TIER1_SIZE="$2"
            shift 2
            ;;
        --tier2)
            TIER2_SIZE="$2"
            shift 2
            ;;
        --no-shuffle)
            SHUFFLE=false
            shift
            ;;
        --help|-h)
            echo "Usage: $0 --input <file> [options]"
            echo ""
            echo "Options:"
            echo "  --input FILE              Input LHE file (required)"
            echo "  --output-dir DIR          Output directory (default: processed_lhe)"
            echo "  --post-process BOOL       Apply post-processing (default: true)"
            echo "  --no-post-process         Disable post-processing"
            echo "  --auto-split BOOL         Automatically split large files (default: true)"
            echo "  --split-threshold N       File size threshold in MB (default: 1000)"
            echo "  --tier1 N                 Tier-1 split size (default: 10000)"
            echo "  --tier2 N                 Tier-2 split size (default: 1000)"
            echo "  --no-shuffle              Disable event shuffling"
            echo "  --help, -h                Show this help"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate input
if [ -z "$INPUT_FILE" ]; then
    log_error "Input file is required"
    exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
    log_error "Input file not found: $INPUT_FILE"
    exit 1
fi

log_info "Processing external LHE file"
log_info "  Input: $INPUT_FILE"
log_info "  Output directory: $OUTPUT_DIR"
log_info "  Post-process: $POST_PROCESS"
log_info "  Auto-split: $AUTO_SPLIT"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Get file size in MB
FILE_SIZE_MB=$(du -m "$INPUT_FILE" | cut -f1)
log_info "File size: ${FILE_SIZE_MB} MB"

# Check if file needs splitting
NEEDS_SPLIT=false
if [ "$AUTO_SPLIT" = true ] && [ $FILE_SIZE_MB -gt $SPLIT_THRESHOLD_MB ]; then
    NEEDS_SPLIT=true
    log_warning "File exceeds ${SPLIT_THRESHOLD_MB} MB threshold - will split"
fi

# Check LHE format validity
log_info "Validating LHE format..."
if ! grep -q "<LesHouchesEvents" "$INPUT_FILE"; then
    log_error "Invalid LHE format: missing <LesHouchesEvents> tag"
    exit 1
fi

if ! grep -q "</LesHouchesEvents>" "$INPUT_FILE"; then
    log_error "Invalid LHE format: missing closing </LesHouchesEvents> tag"
    exit 1
fi

# Count events
NUM_EVENTS=$(grep -c "<event>" "$INPUT_FILE" || echo "0")
log_info "Number of events: $NUM_EVENTS"

if [ $NUM_EVENTS -eq 0 ]; then
    log_error "No events found in LHE file"
    exit 1
fi

# Process file
if [ "$NEEDS_SPLIT" = true ] && [ "$POST_PROCESS" = true ]; then
    log_info "Splitting and post-processing..."
    
    # Use C++ tool if available
    if [ -f "bin/lhe_mixer" ]; then
        log_info "Using C++ LHE mixer for splitting"
        
        ./bin/lhe_mixer split \
            --input "$INPUT_FILE" \
            --output-dir "$OUTPUT_DIR" \
            --tier1 $TIER1_SIZE \
            --tier2 $TIER2_SIZE \
            $([ "$SHUFFLE" = true ] && echo "--shuffle")
        
        log_ok "Split and processed with C++ tool"
    else
        log_info "Using bash/Python fallback for splitting"
        bash scripts/split_shuffle.sh $TIER1_SIZE $TIER2_SIZE "$(dirname $INPUT_FILE)" "$OUTPUT_DIR"
    fi
    
elif [ "$POST_PROCESS" = true ]; then
    log_info "Post-processing (no splitting needed)..."
    
    if [ "$SHUFFLE" = true ]; then
        log_info "Shuffling events..."
        
        if [ -f "bin/lhe_mixer" ]; then
            ./bin/lhe_mixer mix \
                --inputs "$INPUT_FILE" \
                --output "$OUTPUT_DIR/$(basename $INPUT_FILE)" \
                --shuffle
        else
            # Simple copy without shuffle (fallback)
            log_warning "Shuffle not available without C++ tools - copying as-is"
            cp "$INPUT_FILE" "$OUTPUT_DIR/$(basename $INPUT_FILE)"
        fi
    else
        # Just copy
        cp "$INPUT_FILE" "$OUTPUT_DIR/$(basename $INPUT_FILE)"
    fi
    
    log_ok "Post-processed file saved to $OUTPUT_DIR"
    
else
    # No processing - just copy
    log_info "Copying without post-processing..."
    cp "$INPUT_FILE" "$OUTPUT_DIR/$(basename $INPUT_FILE)"
    log_ok "File copied to $OUTPUT_DIR"
fi

# Generate summary
SUMMARY_FILE="$OUTPUT_DIR/processing_summary.txt"
cat > "$SUMMARY_FILE" << EOF
External LHE Processing Summary
================================

Input File: $INPUT_FILE
File Size: ${FILE_SIZE_MB} MB
Number of Events: $NUM_EVENTS

Processing:
  Post-process: $POST_PROCESS
  Split: $NEEDS_SPLIT
  Shuffle: $SHUFFLE
  
Output Directory: $OUTPUT_DIR

Generated: $(date)
EOF

log_info "Summary saved to $SUMMARY_FILE"

# List output files
log_info "Output files:"
ls -lh "$OUTPUT_DIR"/*.lhe 2>/dev/null || log_warning "No LHE files in output"

log_ok "External LHE processing complete"

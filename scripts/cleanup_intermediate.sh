#!/bin/bash
#
# cleanup_intermediate.sh - Intermediate File Cleanup
#
# Cleans up intermediate files while preserving specified patterns.
# Used as the final step in the DAGman workflow.
#
# Usage: ./cleanup_intermediate.sh <preserve_pattern> [<preserve_pattern> ...]
#
# Example: ./cleanup_intermediate.sh '*.lhe' '*.hepmc' '*MiniAOD*.root'
#

set -e

log_info() { echo "[INFO] $1"; }
log_ok() { echo "[OK] $1"; }
log_warn() { echo "[WARN] $1"; }

log_info "Intermediate File Cleanup"

# Get preserve patterns from arguments
PRESERVE_PATTERNS=("$@")

if [ ${#PRESERVE_PATTERNS[@]} -eq 0 ]; then
    # Default patterns to preserve
    PRESERVE_PATTERNS=("*.lhe" "*.hepmc" "*MiniAOD*.root" "*Ntuple*.root")
fi

log_info "Preserving patterns:"
for pattern in "${PRESERVE_PATTERNS[@]}"; do
    log_info "  - ${pattern}"
done

# List of intermediate file patterns to clean
INTERMEDIATE_PATTERNS=(
    "GEN*.root"
    "SIM*.root"
    "DIGI*.root"
    "RECO*.root"
    "*.pyc"
    "__pycache__"
    "log_*.txt"
)

# Build find exclusion for preserved files
PRESERVE_ARGS=""
for pattern in "${PRESERVE_PATTERNS[@]}"; do
    PRESERVE_ARGS="${PRESERVE_ARGS} ! -name '${pattern}'"
done

# Count files before cleanup
BEFORE_COUNT=$(find . -type f 2>/dev/null | wc -l)
log_info "Files before cleanup: ${BEFORE_COUNT}"

# Clean intermediate files
DELETED_COUNT=0

for pattern in "${INTERMEDIATE_PATTERNS[@]}"; do
    # Check if pattern matches any preserved patterns
    SKIP=false
    for preserve in "${PRESERVE_PATTERNS[@]}"; do
        if [[ "$pattern" == "$preserve" ]]; then
            SKIP=true
            break
        fi
    done
    
    if [ "$SKIP" = true ]; then
        continue
    fi
    
    # Find and delete matching files
    while IFS= read -r -d '' file; do
        # Double-check not in preserve list
        PRESERVE_THIS=false
        for preserve in "${PRESERVE_PATTERNS[@]}"; do
            case "$(basename "$file")" in
                $preserve)
                    PRESERVE_THIS=true
                    break
                    ;;
            esac
        done
        
        if [ "$PRESERVE_THIS" = false ]; then
            log_info "Deleting: $file"
            rm -f "$file"
            ((DELETED_COUNT++)) || true
        fi
    done < <(find . -name "$pattern" -type f -print0 2>/dev/null)
done

# Also process files marked for deletion
if [ -f "files_to_delete.txt" ]; then
    log_info "Processing marked files from files_to_delete.txt"
    while IFS= read -r file; do
        if [ -f "$file" ]; then
            # Check preserve patterns
            PRESERVE_THIS=false
            for preserve in "${PRESERVE_PATTERNS[@]}"; do
                case "$(basename "$file")" in
                    $preserve)
                        PRESERVE_THIS=true
                        break
                        ;;
                esac
            done
            
            if [ "$PRESERVE_THIS" = false ]; then
                log_info "Deleting marked file: $file"
                rm -f "$file"
                ((DELETED_COUNT++)) || true
            else
                log_warn "Skipping preserved file: $file"
            fi
        fi
    done < files_to_delete.txt
    rm -f files_to_delete.txt
fi

# Count files after cleanup
AFTER_COUNT=$(find . -type f 2>/dev/null | wc -l)

log_info "Files after cleanup: ${AFTER_COUNT}"
log_ok "Deleted ${DELETED_COUNT} intermediate files"

# List preserved files
log_info "Preserved files:"
for pattern in "${PRESERVE_PATTERNS[@]}"; do
    find . -name "$pattern" -type f 2>/dev/null | while read -r f; do
        SIZE=$(stat -c%s "$f" 2>/dev/null || echo "?")
        echo "  - $f (${SIZE} bytes)"
    done
done

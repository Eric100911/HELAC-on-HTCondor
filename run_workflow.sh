#!/bin/bash
#
# Integrated Monte Carlo Simulation Workflow Orchestrator
# This script coordinates the entire workflow from matrix element generation
# through to final ntuple production.
#
# Usage: ./run_workflow.sh [config.yaml] [--dry-run] [--step STEP]
#

set -e

# Default configuration
CONFIG_FILE="${1:-workflow/workflow_config.yaml}"
DRY_RUN=false
SPECIFIC_STEP=""

# Parse arguments
shift || true
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --step)
            SPECIFIC_STEP="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check dependencies
check_dependencies() {
    log_info "Checking dependencies..."
    
    local missing=()
    
    # Required commands
    for cmd in python3 condor_submit_dag; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing required commands: ${missing[*]}"
        exit 1
    fi
    
    # Check Python dependencies
    python3 -c "import yaml" 2>/dev/null || {
        log_error "Python yaml module not found. Install with: pip install pyyaml"
        exit 1
    }
    
    log_success "All dependencies satisfied"
}

# Parse YAML configuration
parse_config() {
    python3 - "$CONFIG_FILE" <<'EOF'
import sys
import yaml

with open(sys.argv[1], 'r') as f:
    config = yaml.safe_load(f)

# Export key values as shell variables
def flatten_dict(d, parent_key='', sep='_'):
    items = []
    for k, v in d.items():
        new_key = f"{parent_key}{sep}{k}" if parent_key else k
        if isinstance(v, dict):
            items.extend(flatten_dict(v, new_key, sep=sep).items())
        elif isinstance(v, list):
            items.append((new_key, ','.join(str(x) for x in v)))
        else:
            items.append((new_key, str(v)))
    return dict(items)

flat = flatten_dict(config)
for k, v in flat.items():
    # Sanitize key for shell
    key = k.upper().replace('-', '_').replace('.', '_')
    print(f'export CFG_{key}="{v}"')
EOF
}

# Generate DAGman workflow
generate_dagman() {
    log_info "Generating DAGman workflow..."
    
    python3 workflow/generate_dag.py "$CONFIG_FILE" --output workflow/
    
    if [ -f "workflow/generated.dag" ]; then
        log_success "DAGman workflow generated: workflow/generated.dag"
    else
        log_error "Failed to generate DAGman workflow"
        exit 1
    fi
}

# Submit workflow
submit_workflow() {
    if [ "$DRY_RUN" = true ]; then
        log_warning "Dry run mode - not submitting"
        condor_submit_dag -dry-run dryrun.log workflow/generated.dag
        log_info "Dry run output saved to dryrun.log"
    else
        log_info "Submitting DAGman workflow..."
        condor_submit_dag workflow/generated.dag
        log_success "Workflow submitted successfully"
    fi
}

# Run a specific step only
run_step() {
    local step="$1"
    log_info "Running step: $step"
    
    case "$step" in
        "matrix_element")
            bash scripts/run_matrix_element.sh "$CONFIG_FILE"
            ;;
        "preprocessing")
            bash scripts/run_preprocessing.sh "$CONFIG_FILE"
            ;;
        "showering")
            bash scripts/run_showering.sh "$CONFIG_FILE"
            ;;
        "simulation")
            bash scripts/run_simulation.sh "$CONFIG_FILE"
            ;;
        *)
            log_error "Unknown step: $step"
            log_info "Available steps: matrix_element, preprocessing, showering, simulation"
            exit 1
            ;;
    esac
}

# Main execution
main() {
    echo "======================================"
    echo "  MC Simulation Workflow Orchestrator"
    echo "======================================"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
    
    log_info "Using configuration: $CONFIG_FILE"
    
    check_dependencies
    
    # Load configuration
    eval "$(parse_config)"
    
    # Display workflow info
    log_info "Workflow: ${CFG_WORKFLOW_NAME:-unknown}"
    log_info "Description: ${CFG_WORKFLOW_DESCRIPTION:-none}"
    
    if [ -n "$SPECIFIC_STEP" ]; then
        run_step "$SPECIFIC_STEP"
    else
        generate_dagman
        submit_workflow
    fi
    
    log_success "Workflow operation completed"
}

main

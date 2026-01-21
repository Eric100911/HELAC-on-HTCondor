#!/bin/bash
#
# Comprehensive Test Runner for HELAC-on-HTCondor
# 
# This script runs all tests and generates detailed reports.
# Usage: ./run_tests.sh [--unit] [--integration] [--all] [--coverage] [--verbose]
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test configuration
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_DIR="${REPO_ROOT}/tests"
REPORT_DIR="${REPO_ROOT}/test_reports"
LOG_FILE="${REPORT_DIR}/test_run_$(date +%Y%m%d_%H%M%S).log"

# Flags
RUN_UNIT=false
RUN_INTEGRATION=false
RUN_ALL=false
VERBOSE=false
COVERAGE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --unit)
            RUN_UNIT=true
            shift
            ;;
        --integration)
            RUN_INTEGRATION=true
            shift
            ;;
        --all)
            RUN_ALL=true
            shift
            ;;
        --coverage)
            COVERAGE=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --unit           Run unit tests only"
            echo "  --integration    Run integration tests only"
            echo "  --all            Run all tests (default)"
            echo "  --coverage       Generate coverage report"
            echo "  --verbose, -v    Verbose output"
            echo "  --help, -h       Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Default to all tests
if [ "$RUN_UNIT" = false ] && [ "$RUN_INTEGRATION" = false ]; then
    RUN_ALL=true
fi

# Logging functions
log_header() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}\n"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_section() {
    echo -e "\n${YELLOW}--- $1 ---${NC}\n"
}

# Setup
setup_test_environment() {
    log_section "Setting Up Test Environment"
    
    # Create report directory
    mkdir -p "${REPORT_DIR}"
    
    # Initialize log file
    echo "Test Run Started: $(date)" > "${LOG_FILE}"
    echo "Repository: ${REPO_ROOT}" >> "${LOG_FILE}"
    echo "" >> "${LOG_FILE}"
    
    log_info "Report directory: ${REPORT_DIR}"
    log_info "Log file: ${LOG_FILE}"
    
    # Build tools if needed
    if [ ! -f "${REPO_ROOT}/bin/lhe_mixer" ]; then
        log_info "Building C++ tools..."
        cd "${REPO_ROOT}"
        make tools 2>&1 | tee -a "${LOG_FILE}"
        cd - > /dev/null
    else
        log_success "C++ tools already built"
    fi
    
    # Check Python dependencies
    log_info "Checking Python dependencies..."
    python3 -c "import yaml" 2>/dev/null || {
        log_warning "PyYAML not installed, attempting to install..."
        pip3 install pyyaml --user 2>&1 | tee -a "${LOG_FILE}"
    }
    
    log_success "Environment setup complete"
}

# Run unit tests
run_unit_tests() {
    log_section "Running Unit Tests"
    
    local unit_dir="${TEST_DIR}/unit"
    local test_count=0
    local passed=0
    local failed=0
    
    if [ ! -d "$unit_dir" ]; then
        log_warning "No unit test directory found"
        return 0
    fi
    
    # Find all test files
    while IFS= read -r test_file; do
        ((test_count++))
        
        local test_name=$(basename "$test_file")
        log_info "Running: $test_name"
        
        # Run test
        if [ "$VERBOSE" = true ]; then
            python3 "$test_file" -v 2>&1 | tee -a "${LOG_FILE}"
        else
            python3 "$test_file" 2>&1 | tee -a "${LOG_FILE}"
        fi
        
        if [ ${PIPESTATUS[0]} -eq 0 ]; then
            log_success "$test_name passed"
            ((passed++))
        else
            log_error "$test_name failed"
            ((failed++))
        fi
        
        echo "" | tee -a "${LOG_FILE}"
    done < <(find "$unit_dir" -name "test_*.py")
    
    # Summary
    echo "" | tee -a "${LOG_FILE}"
    log_info "Unit Tests Summary:"
    echo "  Total:  $test_count" | tee -a "${LOG_FILE}"
    echo "  Passed: $passed" | tee -a "${LOG_FILE}"
    echo "  Failed: $failed" | tee -a "${LOG_FILE}"
    
    return $failed
}

# Run integration tests
run_integration_tests() {
    log_section "Running Integration Tests"
    
    local integration_dir="${TEST_DIR}/integration"
    local test_count=0
    local passed=0
    local failed=0
    
    if [ ! -d "$integration_dir" ]; then
        log_warning "No integration test directory found"
        return 0
    fi
    
    # Find all test files
    while IFS= read -r test_file; do
        ((test_count++))
        
        local test_name=$(basename "$test_file")
        log_info "Running: $test_name"
        
        # Run test
        if [ "$VERBOSE" = true ]; then
            python3 "$test_file" -v 2>&1 | tee -a "${LOG_FILE}"
        else
            python3 "$test_file" 2>&1 | tee -a "${LOG_FILE}"
        fi
        
        if [ ${PIPESTATUS[0]} -eq 0 ]; then
            log_success "$test_name passed"
            ((passed++))
        else
            log_error "$test_name failed"
            ((failed++))
        fi
        
        echo "" | tee -a "${LOG_FILE}"
    done < <(find "$integration_dir" -name "test_*.py")
    
    # Summary
    echo "" | tee -a "${LOG_FILE}"
    log_info "Integration Tests Summary:"
    echo "  Total:  $test_count" | tee -a "${LOG_FILE}"
    echo "  Passed: $passed" | tee -a "${LOG_FILE}"
    echo "  Failed: $failed" | tee -a "${LOG_FILE}"
    
    return $failed
}

# Run coverage analysis
run_coverage() {
    log_section "Generating Coverage Report"
    
    log_warning "Coverage analysis not yet implemented"
    log_info "To add coverage:"
    echo "  1. Install coverage: pip install coverage"
    echo "  2. Run: coverage run -m unittest discover"
    echo "  3. Generate report: coverage report -m"
}

# Generate HTML report
generate_html_report() {
    log_section "Generating HTML Report"
    
    local html_report="${REPORT_DIR}/test_report_$(date +%Y%m%d_%H%M%S).html"
    
    cat > "$html_report" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Test Report - HELAC-on-HTCondor</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        .summary { background: #f0f0f0; padding: 15px; border-radius: 5px; margin: 20px 0; }
        .pass { color: green; font-weight: bold; }
        .fail { color: red; font-weight: bold; }
        .warn { color: orange; font-weight: bold; }
        pre { background: #f9f9f9; padding: 10px; border: 1px solid #ddd; overflow-x: auto; }
        .timestamp { color: #666; font-size: 0.9em; }
    </style>
</head>
<body>
    <h1>Test Report - HELAC-on-HTCondor</h1>
    <p class="timestamp">Generated: $(date)</p>
    
    <div class="summary">
        <h2>Test Summary</h2>
        <p>See detailed log: <code>${LOG_FILE}</code></p>
    </div>
    
    <h2>Test Log</h2>
    <pre>
$(cat "${LOG_FILE}")
    </pre>
</body>
</html>
EOF
    
    log_success "HTML report generated: $html_report"
    log_info "Open in browser: file://$html_report"
}

# Main execution
main() {
    log_header "HELAC-on-HTCondor Test Suite"
    
    echo "Test Configuration:"
    echo "  Unit tests:        $([ "$RUN_UNIT" = true ] || [ "$RUN_ALL" = true ] && echo "Yes" || echo "No")"
    echo "  Integration tests: $([ "$RUN_INTEGRATION" = true ] || [ "$RUN_ALL" = true ] && echo "Yes" || echo "No")"
    echo "  Coverage:          $([ "$COVERAGE" = true ] && echo "Yes" || echo "No")"
    echo "  Verbose:           $([ "$VERBOSE" = true ] && echo "Yes" || echo "No")"
    echo ""
    
    # Setup
    setup_test_environment
    
    local total_failures=0
    
    # Run tests
    if [ "$RUN_UNIT" = true ] || [ "$RUN_ALL" = true ]; then
        run_unit_tests
        total_failures=$((total_failures + $?))
    fi
    
    if [ "$RUN_INTEGRATION" = true ] || [ "$RUN_ALL" = true ]; then
        run_integration_tests
        total_failures=$((total_failures + $?))
    fi
    
    # Coverage
    if [ "$COVERAGE" = true ]; then
        run_coverage
    fi
    
    # Generate report
    generate_html_report
    
    # Final summary
    log_header "Test Run Complete"
    
    if [ $total_failures -eq 0 ]; then
        log_success "All tests passed!"
        echo ""
        log_info "Test reports available in: ${REPORT_DIR}"
        exit 0
    else
        log_error "$total_failures test(s) failed"
        echo ""
        log_info "Check logs for details: ${LOG_FILE}"
        exit 1
    fi
}

# Run main
main

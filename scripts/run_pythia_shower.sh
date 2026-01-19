#!/bin/bash
#
# run_pythia_shower.sh - Pythia 8 Parton Showering
#
# Runs Pythia 8 showering on LHE events with support for:
# - Normal showering mode
# - Phi-enriched mode (repeated attempts for hard phi production)
# - Color octet states (HepMC output preservation)
#
# Usage: ./run_pythia_shower.sh [options]
#   --input FILE        Input LHE file
#   --output FILE       Output HepMC file
#   --mode MODE         Shower mode: normal, phi
#   --keep-hepmc BOOL   Keep HepMC output (true/false)
#   --max-attempts N    Max attempts for phi mode (default: 100)
#

set -e

# Default values
INPUT_FILE=""
OUTPUT_FILE=""
MODE="normal"
KEEP_HEPMC="false"
MAX_ATTEMPTS=100

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --input)
            INPUT_FILE="$2"
            shift 2
            ;;
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --mode)
            MODE="$2"
            shift 2
            ;;
        --keep-hepmc)
            KEEP_HEPMC="$2"
            shift 2
            ;;
        --max-attempts)
            MAX_ATTEMPTS="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

log_info() { echo "[INFO] $1"; }
log_ok() { echo "[OK] $1"; }
log_error() { echo "[ERROR] $1"; }

log_info "Pythia 8 Parton Showering"
log_info "  Input: ${INPUT_FILE}"
log_info "  Output: ${OUTPUT_FILE}"
log_info "  Mode: ${MODE}"
log_info "  Keep HepMC: ${KEEP_HEPMC}"

# Setup environment
source /cvmfs/cms.cern.ch/cmsset_default.sh

# Find CMSSW installation
if [ -d "${CMSSW_BASE}/src" ]; then
    cd "${CMSSW_BASE}/src"
    eval $(scramv1 runtime -sh)
    cd -
else
    log_error "CMSSW environment not set"
    exit 1
fi

# Create Pythia configuration
PYTHIA_CONFIG=$(mktemp /tmp/pythia_config_XXXXXX.cmnd)

cat > "${PYTHIA_CONFIG}" << EOF
! Pythia8 configuration for parton showering

! Basic settings
Main:numberOfEvents = -1
Main:timesAllowErrors = 10

! LHE input
Beams:frameType = 4
Beams:LHEF = ${INPUT_FILE}

! General Pythia settings
Tune:pp = 14  ! Monash 2013 tune
PartonLevel:MPI = on
PartonLevel:ISR = on
PartonLevel:FSR = on
HadronLevel:Hadronize = on

! Process-specific settings
ProcessLevel:all = off
EOF

# Mode-specific settings
if [ "$MODE" = "phi" ]; then
    cat >> "${PYTHIA_CONFIG}" << EOF

! Phi-enriched mode settings
! Try to produce hard phi mesons
333:mayDecay = off  ! Keep phi stable initially
StringFlavorMesonS = 0.4  ! Increase strangeness

! Repeated showering for phi production
PhaseSpace:pTHatMin = 4.0
EOF
    log_info "Phi-enriched mode enabled"
fi

# Run appropriate shower program
if [ -f "bin/shower_${MODE}" ]; then
    log_info "Using dedicated shower_${MODE} program"
    ./bin/shower_${MODE} "${INPUT_FILE}" "${OUTPUT_FILE}" ${MAX_ATTEMPTS}
else
    log_info "Using generic Pythia runner"
    
    # Use CMSSW's Pythia8 via cmsRun if available
    if [ -f "configs/pythia8_shower_cfg.py" ]; then
        cmsRun configs/pythia8_shower_cfg.py \
            inputFile="${INPUT_FILE}" \
            outputFile="${OUTPUT_FILE}" \
            mode="${MODE}"
    else
        log_error "No shower program found"
        exit 1
    fi
fi

# Check output
if [ -f "${OUTPUT_FILE}" ]; then
    log_ok "Showering completed: ${OUTPUT_FILE}"
    
    # Handle HepMC preservation
    if [ "$KEEP_HEPMC" = "true" ]; then
        log_info "Keeping HepMC file"
    else
        log_info "HepMC will be used for GEN-SIM then deleted"
    fi
else
    log_error "Showering failed - no output file"
    exit 1
fi

# Cleanup
rm -f "${PYTHIA_CONFIG}"

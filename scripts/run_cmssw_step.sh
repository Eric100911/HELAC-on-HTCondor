#!/bin/bash
#
# run_cmssw_step.sh - CMSSW Simulation Step Runner
#
# Runs individual CMSSW simulation steps with proper environment setup
# and automatic intermediate file cleanup.
#
# Usage: ./run_cmssw_step.sh <step> <config_file> <cmssw_version> <keep|delete>
#
# Steps: gen, sim, digi, reco, skim, ntuple
#

set -e

STEP="${1:-gen}"
CONFIG_FILE="${2:-configs/cmssw/GEN_cfg.py}"
CMSSW_VERSION="${3:-CMSSW_14_0_0}"
KEEP_OUTPUT="${4:-delete}"

log_info() { echo "[INFO] $1"; }
log_ok() { echo "[OK] $1"; }
log_error() { echo "[ERROR] $1"; }

log_info "CMSSW Step Runner"
log_info "  Step: ${STEP}"
log_info "  Config: ${CONFIG_FILE}"
log_info "  CMSSW: ${CMSSW_VERSION}"
log_info "  Keep output: ${KEEP_OUTPUT}"

# Setup CMS environment
source /cvmfs/cms.cern.ch/cmsset_default.sh

# Find or setup CMSSW
CMSSW_BASE_DIR=""

# Check common locations
for dir in "/afs/cern.ch/user/c/chiw/condor/${CMSSW_VERSION}" \
           "/cvmfs/cms.cern.ch/slc7_amd64_gcc*/cms/cmssw/${CMSSW_VERSION}" \
           "./${CMSSW_VERSION}"; do
    if [ -d "$dir/src" ]; then
        CMSSW_BASE_DIR="$dir"
        break
    fi
done

if [ -z "$CMSSW_BASE_DIR" ]; then
    log_info "Setting up new CMSSW area..."
    cmsrel ${CMSSW_VERSION}
    CMSSW_BASE_DIR="./${CMSSW_VERSION}"
fi

cd "${CMSSW_BASE_DIR}/src"
eval $(scramv1 runtime -sh)
cd - > /dev/null

log_info "CMSSW environment ready: ${CMSSW_VERSION}"

# Determine input and output files based on step
case ${STEP} in
    gen)
        INPUT_FILE="${INPUT_LHE:-input.lhe}"
        OUTPUT_FILE="GEN.root"
        ;;
    sim)
        INPUT_FILE="${INPUT_GEN:-GEN.root}"
        OUTPUT_FILE="SIM.root"
        ;;
    digi)
        INPUT_FILE="${INPUT_SIM:-SIM.root}"
        OUTPUT_FILE="DIGI.root"
        ;;
    reco)
        INPUT_FILE="${INPUT_DIGI:-DIGI.root}"
        OUTPUT_FILE="RECO.root"
        ;;
    skim)
        INPUT_FILE="${INPUT_RECO:-RECO.root}"
        OUTPUT_FILE="MiniAOD.root"
        ;;
    ntuple)
        INPUT_FILE="${INPUT_MINIAOD:-MiniAOD.root}"
        OUTPUT_FILE="Ntuple.root"
        ;;
    *)
        log_error "Unknown step: ${STEP}"
        exit 1
        ;;
esac

log_info "Input: ${INPUT_FILE}"
log_info "Output: ${OUTPUT_FILE}"

# Check input exists
if [ ! -f "${INPUT_FILE}" ]; then
    log_error "Input file not found: ${INPUT_FILE}"
    exit 1
fi

# Check config exists
if [ ! -f "${CONFIG_FILE}" ]; then
    log_error "Config file not found: ${CONFIG_FILE}"
    exit 1
fi

# Run cmsRun
log_info "Running cmsRun..."
cmsRun "${CONFIG_FILE}" \
    inputFiles="file:${INPUT_FILE}" \
    outputFile="${OUTPUT_FILE}" \
    2>&1 | tee "log_${STEP}.txt"

RUN_STATUS=${PIPESTATUS[0]}

if [ $RUN_STATUS -ne 0 ]; then
    log_error "cmsRun failed with status ${RUN_STATUS}"
    exit 1
fi

# Verify output
if [ -f "${OUTPUT_FILE}" ]; then
    OUTPUT_SIZE=$(stat -c%s "${OUTPUT_FILE}" 2>/dev/null || echo "0")
    log_ok "Created ${OUTPUT_FILE} (${OUTPUT_SIZE} bytes)"
else
    log_error "Output file not created: ${OUTPUT_FILE}"
    exit 1
fi

# Handle cleanup based on KEEP_OUTPUT
if [ "${KEEP_OUTPUT}" = "delete" ]; then
    log_info "Marking input for cleanup (will be deleted by cleanup job)"
    echo "${INPUT_FILE}" >> files_to_delete.txt
else
    log_info "Keeping output file"
fi

log_ok "Step ${STEP} completed successfully"

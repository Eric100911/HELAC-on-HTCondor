#! /bin/bash
# This script is used to run HELAC-Onia on HTCondor.
# It runs scripts/helac_build_run.sh in an cmssw-el7 container.
# It accepts arguments: one argument <seed> to set the random seed.
MY_SEED=11

if [ $# -eq 1 ]; then
    MY_SEED=$1
fi

# Check if extra arguments are provided

if [ $# -gt 1 ]; then
    echo "Usage: $0 [seed]"
    echo "Error: Too many arguments provided."
    exit 1
fi

# Check if the seed is a valid number

if ! [[ "$MY_SEED" =~ ^[0-9]+$ ]]; then
    echo "Error: Seed must be a valid integer."
    exit 1
fi

# Check if the seed is too small ( <= 10 ) or too big ( >= 10000 )
if [ "$MY_SEED" -le 10 ] || [ "$MY_SEED" -ge 10000 ]; then
    echo "Error: Seed must be between 11 and 9999."
    exit 1
fi

# Check if the condor_submit.tar file exists

if [ ! -f condor_submit.tar ]; then
    echo "Error: condor_submit.tar file not found."
    exit 1
fi

# Fundamental environment variables.
source /cvmfs/cms.cern.ch/cmsset_default.sh

# Unpack configuration and patches
tar -xvf condor_submit.tar

# Check if the scripts/helac_build_run.sh file exists
if [ ! -f scripts/helac_build_run.sh ]; then
    echo "Error: scripts/helac_build_run.sh file not found."
    exit 1
fi

# Load the cmssw-el7 container and run.
cmssw-el7 --command-to-run "bash -x scripts/helac_build_run.sh -s $MY_SEED"

# Check if HepMC chunk files were created
HEPMC_CHUNKS=(./test_Jpsi1Jpsi1Y8_chunk_*.dat)
if [ ! -e "${HEPMC_CHUNKS[0]}" ]; then
    echo "Error: No HepMC chunk files found (test_Jpsi1Jpsi1Y8_chunk_*.dat)."
    exit 1
fi

NUM_HEPMC_CHUNKS=${#HEPMC_CHUNKS[@]}
echo "HELAC-Onia run completed successfully with seed $MY_SEED."
echo "Found ${NUM_HEPMC_CHUNKS} HepMC chunk files."
echo "Begin CMS simulation steps to GENSIM..."

# Set up CMSSW environment
export SCRAM_ARCH=el8_amd64_gcc10
scram project -n CMSSW_12_4_14_patch3 CMSSW_12_4_14_patch3
cd CMSSW_12_4_14_patch3/src
eval `scram runtime -sh`
cp ../../scripts/step1_Jpsi1Jpsi1Y8_cfg.py .

# Process each HepMC chunk to produce GENSIM files
GENSIM_FILES=()
for HEPMC_FILE in "${HEPMC_CHUNKS[@]}"; do
    HEPMC_BASENAME=$(basename "$HEPMC_FILE")
    CHUNK_ID=$(echo "$HEPMC_BASENAME" | sed -n 's/.*_chunk_\([0-9]*\)\.dat/\1/p')
    
    echo "Processing HepMC chunk: $HEPMC_BASENAME (chunk ID: $CHUNK_ID)"
    
    # Copy the HepMC file
    cp "../../$HEPMC_BASENAME" test_Jpsi1Jpsi1Y8.dat
    
    # Create a modified config file for this chunk
    CHUNK_CFG="step1_Jpsi1Jpsi1Y8_cfg_chunk_${CHUNK_ID}.py"
    CHUNK_OUTPUT="JJY1S_Y1S-Octet_SPS_6Mu_13p6TeV_TuneCP5_pythia8_Run3Summer22_GENSIM_chunk_${CHUNK_ID}.root"
    
    # Modify the output filename in the config
    sed -e "s/JJY1S_Y1S-Octet_SPS_6Mu_13p6TeV_TuneCP5_pythia8_Run3Summer22_GENSIM.root/$CHUNK_OUTPUT/g" \
        step1_Jpsi1Jpsi1Y8_cfg.py > "$CHUNK_CFG"
    
    # Run CMS simulation step to GENSIM for this chunk
    cmsRun "$CHUNK_CFG"
    
    if [ ! -f "$CHUNK_OUTPUT" ]; then
        echo "Error: GENSIM output file $CHUNK_OUTPUT not created for chunk $CHUNK_ID"
        exit 1
    fi
    
    echo "GENSIM step completed for chunk $CHUNK_ID. Output file: $CHUNK_OUTPUT"
    GENSIM_FILES+=("$CHUNK_OUTPUT")
    
    # Clean up the temporary HepMC file
    rm -f test_Jpsi1Jpsi1Y8.dat
done

# Merge all GENSIM files using hadd
echo "Merging ${#GENSIM_FILES[@]} GENSIM files using hadd..."
MERGED_GENSIM="JJY1S_Y1S-Octet_SPS_6Mu_13p6TeV_TuneCP5_pythia8_Run3Summer22_GENSIM.root"

hadd -f "$MERGED_GENSIM" "${GENSIM_FILES[@]}"

if [ ! -f "$MERGED_GENSIM" ]; then
    echo "Error: Failed to merge GENSIM files"
    exit 1
fi

echo "GENSIM files merged successfully into $MERGED_GENSIM"

# Clean up intermediate GENSIM chunk files to save disk space
echo "Cleaning up intermediate GENSIM chunk files..."
for GENSIM_CHUNK in "${GENSIM_FILES[@]}"; do
    rm -f "$GENSIM_CHUNK"
done

# Also clean up intermediate config files
rm -f step1_Jpsi1Jpsi1Y8_cfg_chunk_*.py

# Transfer the merged GENSIM output file back to the output directory
cp "$MERGED_GENSIM" \
    /eos/user/c/chiw/JpsiJpsiPhi/MC_samples/GENSIM/DPS-JpsiJpsi-Phi/filter_JPsi_PtMin6p0_Phi_PtMin6p0/DPS-JpsiJpsi-Phi1020_JJPhi_4Mu2K_13p6TeV_TuneCP5_pythia8_Run3Summer22_GENSIM_${MY_SEED}.root

cd ../../
echo "All steps completed successfully."
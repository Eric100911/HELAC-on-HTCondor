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
cmssw-el7 --command-to-run "source scripts/helac_build_run.sh -s $MY_SEED"

# Check if the LHE file was created.
if [ ! -f sample_pp_nonia_mps.lhe ]; then
    echo "Error: LHE file sample_pp_nonia_mps.lhe not found."
    exit 1
fi

# Move the LHE file to eos.
cp sample_pp_nonia_mps.lhe /eos/user/c/chiw/JpsiJpsiUps/MC_samples/LHE/TPS-JpsiJpsiY2S/sample_pp_nonia_mps_helac_${MY_SEED}.lhe

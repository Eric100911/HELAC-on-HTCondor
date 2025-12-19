#! /bin/bash
# Full HELAC-Onia workflow: build, generate events, and shower
# This is the refactored version of the original helac_build_run.sh

set -e

AS_NEW=0
SEED=11
WORKDIR=$(pwd)
DRYRUN=0

# Parse arguments
while getopts ":nds:" opt; do
    case $opt in
        n)
            AS_NEW=1
            ;;
        d)
            DRYRUN=1
            ;;
        s)
            SEED="$OPTARG"
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit 1
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            exit 1
            ;;
    esac
done

# Validate seed
if [ -z "$SEED" ]; then
    echo "Usage: $0 [-n] [-d] -s <seed>"
    exit 1
fi
if ! [[ "$SEED" =~ ^[0-9]+$ ]]; then
    echo "Error: Seed must be a number."
    exit 1
fi
if [ "$SEED" -lt 11 ]; then
    echo "Error: Seed must be greater than 10."
    exit 1
fi

echo "========================================="
echo "Full HELAC-Onia workflow"
echo "Seed: $SEED"
echo "New build: $AS_NEW"
echo "Dry run: $DRYRUN"
echo "========================================="

# Source common environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common_env.sh"

# Check if we need to build HELAC-Onia
if [ ! -d "HELAC-Onia-2.7.6" ]; then
    AS_NEW=1
    if [ ! -f "sources/HELAC-Onia-2.7.6.tar.gz" ]; then
        echo "Error: No HELAC-Onia-2.7.6 available"
        exit 1
    fi
fi

# Build HELAC-Onia
if [ $AS_NEW -eq 1 ]; then
    echo "Building HELAC-Onia..."
    rm -rf HELAC-Onia-2.7.6
    tar -xzf sources/HELAC-Onia-2.7.6.tar.gz
    
    # Apply patches
    if [ -f "patch/addon/pp_NOnia_MPS/src/pp_NOnia_MPS.f90" ]; then 
        cp patch/addon/pp_NOnia_MPS/src/pp_NOnia_MPS.f90 HELAC-Onia-2.7.6/addon/pp_NOnia_MPS/src/pp_NOnia_MPS.f90
        cp HELAC-Onia-2.7.6/src/RANDA_init.inc HELAC-Onia-2.7.6/addon/pp_NOnia_MPS/src/
    fi
    
    cd HELAC-Onia-2.7.6
    
    # Block lhapdfobj setting
    if egrep -q "^\W*lhapdfobj" addon/pp_psiY_SPS/src/makefile ; then
        echo "Blocking lhapdfobj setting in addon/pp_psiY_SPS/src/makefile"
        sed -i -r -e 's/^.*lhapdfobj.*/#lhapdfobj=/' addon/pp_psiY_SPS/src/makefile
    fi
    
    # Configure HepMC and Pythia8 paths
    sed -i -r -e "s|^# hepmc_path.*$|hepmc_path = $HEPMC_DIR|" input/ho_configuration.txt
    sed -i -r -e "s|^# pythia8_path.*$|pythia8_path = $PYTHIA_INSTALL_PATH|" input/ho_configuration.txt
    
    # Compile HELAC-Onia
    if [[ $DRYRUN -eq 0 ]]; then
        ./config
    else
        echo "Dryrun mode: HELAC-Onia build command:"
        echo "./config"
    fi
else
    echo "Using existing HELAC-Onia build"
    cd HELAC-Onia-2.7.6
fi

# Run HELAC-Onia to generate events
echo "Running HELAC-Onia event generation..."
sed -e "s/MY_SEED/$SEED/" ../configs/run_HELAC.ho.tpl > ../configs/run_HELAC.ho

# Copy config files
if [ -f "../configs/input/py8_onia_user.inp" ]; then
    cp ../configs/input/py8_onia_user.inp input/py8_onia_user.inp
fi
if [ -f "../configs/input/user.inp" ]; then
    cp ../configs/input/user.inp input/user.inp
fi
if [ -f "../configs/addon/pp_NOnia_MPS/input/states.inp" ]; then
    cp ../configs/addon/pp_NOnia_MPS/input/states.inp addon/pp_NOnia_MPS/input/states.inp
fi
if [ -f "../configs/addon/pp_psiY_SPS/input/states.inp" ]; then
    cp ../configs/addon/pp_psiY_SPS/input/states.inp addon/pp_psiY_SPS/input/states.inp
fi

# Run HELAC-Onia
./ho_cluster < ../configs/run_HELAC.ho | tee ../run_HELAC.log

# Collect output
RUN_DIR=$(egrep "INFO: Results are collected in" ../run_HELAC.log | \
            sed -r -e "s,^.*(PROC_HO_[0-9]+)\/.*$,\1,g")

# Copy the resulting LHE file
if [ -f "$RUN_DIR/P0_addon_pp_psiY_SPS/output/sample_pp_psiY_sps.lhe" ]; then
    # Potentially fix "</event></LesHouchesEvents>" issue
    if [ -f "$WORKDIR/shower/shuffle_lhe.cpp" ]; then
        sed -i -e '$ s,</event></LesHouchesEvents>,</event>\n</LesHouchesEvents>,' "$RUN_DIR/P0_addon_pp_psiY_SPS/output/sample_pp_psiY_sps.lhe"
        echo "Shuffling LHE events using shower/shuffle_lhe.cpp"
        g++ --std=c++11 -g "$WORKDIR/shower/shuffle_lhe.cpp" -o "$WORKDIR/shower/shuffle_lhe"
        "$WORKDIR/shower/shuffle_lhe" "$RUN_DIR/P0_addon_pp_psiY_SPS/output/sample_pp_psiY_sps.lhe" "$WORKDIR/helac_sample.lhe"
    else
        echo "No shower/shuffle_lhe.cpp found, copying LHE file directly."
        cp "$RUN_DIR/P0_addon_pp_psiY_SPS/output/sample_pp_psiY_sps.lhe" "$WORKDIR/helac_sample.lhe"
    fi
else
    echo "Error: No output LHE file found in $RUN_DIR"
    exit 1
fi

cd "$WORKDIR"

# Process the LHE file (split and shower)
echo "Processing LHE file with Pythia8 showering..."
"$SCRIPT_DIR/process_lhe.sh" "$WORKDIR/helac_sample.lhe" "$WORKDIR"

echo "========================================="
echo "Full workflow completed successfully!"
echo "HepMC chunk files are ready in: $WORKDIR"
echo "========================================="

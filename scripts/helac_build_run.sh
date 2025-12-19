#! /bin/bash

# This script is used to build and run HELAC-Onia in a compact way.
# - Accept arguments: -n for new build, -s for seed.
AS_NEW=0
SEED=11
WORKDIR=$(pwd)
DRYRUN=0
HEPMC_DIR=/afs/cern.ch/user/c/chiw/public/cms-utils/HepMC-2.06.11/install
PYTHIA_INSTALL_PATH=/afs/cern.ch/user/c/chiw/public/cms-utils/pythia8245
MY_LIBBOOST_A=/cvmfs/sft.cern.ch/lcg/releases/LCG_88b/Boost/1.62.0/x86_64-centos7-gcc62-opt/lib/libboost_iostreams-gcc62-mt-1_62.a
MY_LIBBOOST_SO=/cvmfs/sft.cern.ch/lcg/releases/LCG_88b/Boost/1.62.0/x86_64-centos7-gcc62-opt/lib/libboost_iostreams-gcc62-mt-1_62.so

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

# Check if the seed is provided and valid.
if [ -z "$SEED" ]; then
    echo "Usage: $0 <seed>"
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

if [ ! -d "HELAC-Onia-2.7.6" ]; then
    AS_NEW=1
    if [ ! -f "sources/HELAC-Onia-2.7.6.tar.gz" ]; then
        echo "Error: No HELAC-Onia-2.7.6 available"
        exit 1
    fi
fi

# Environment variables for the first part of the script.
source ~/.bash_profile
source /cvmfs/cms.cern.ch/cmsset_default.sh
source /cvmfs/sft.cern.ch/lcg/views/LCG_88b/x86_64-centos7-gcc62-opt/setup.sh
export LD_LIBRARY_PATH=/cvmfs/sft.cern.ch/lcg/releases/LCG_88b/Boost/1.62.0/x86_64-centos7-gcc62-opt/lib:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=/cvmfs/sft.cern.ch/lcg/contrib/gcc/6.2.0/x86_64-centos7-gcc62-opt/lib64:/opt/rh/gcc-toolset-12/root/usr/lib64:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=/cvmfs/sft.cern.ch/lcg/releases/LCG_88b/Boost/1.62.0/x86_64-centos7-gcc62-opt/lib:$LD_LIBRARY_PATH

# With HepMC installed, we can set the environment variables for the rest of the script.
export PATH=$HEPMC_DIR:$PATH
export LD_LIBRARY_PATH=$HEPMC_DIR/lib:$LD_LIBRARY_PATH

# For Pythia 8 to correctly locate some libboost_iostream files, create a soft link.
ln -s $MY_LIBBOOST_A $HEPMC_DIR/lib/libboost_iostreams.a
ln -s $MY_LIBBOOST_SO $HEPMC_DIR/lib/libboost_iostreams.so

# Build HELAC-Onia.
if [ $AS_NEW -eq 1 ]; then
    # - Remove any existing build
    rm -rf HELAC-Onia-2.7.6
    tar -xzf sources/HELAC-Onia-2.7.6.tar.gz
    # - Before compilation, apply patches
    if [ -f "patch/addon/pp_NOnia_MPS/src/pp_NOnia_MPS.f90" ]; then 
        cp patch/addon/pp_NOnia_MPS/src/pp_NOnia_MPS.f90 HELAC-Onia-2.7.6/addon/pp_NOnia_MPS/src/pp_NOnia_MPS.f90
	    cp HELAC-Onia-2.7.6/src/RANDA_init.inc HELAC-Onia-2.7.6/addon/pp_NOnia_MPS/src/
    fi
    # - Enter directory and check that the lhapdfobj setting in pp_psiY_SPS is already blocked.
    cd HELAC-Onia-2.7.6
    if egrep -q "^\W*lhapdfobj" addon/pp_psiY_SPS/src/makefile ; then
        echo "Blocking lhapdfobj setting in addon/pp_psiY_SPS/src/makefile"
        sed -i -r -e 's/^.*lhapdfobj.*/#lhapdfobj=/' addon/pp_psiY_SPS/src/makefile
    fi

    # - Check that the HepMC installation directory is set in input/ho_configuration.txt
    sed -i -r -e "s|^# hepmc_path.*$|hepmc_path = $HEPMC_DIR|" input/ho_configuration.txt

    # - Connect Pythia 8 installation also
    sed -i -r -e "s|^# pythia8_path.*$|pythia8_path = $PYTHIA_INSTALL_PATH|" input/ho_configuration.txt

    # - Compile HELAC-Onia
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


# Run HELAC-Onia with the configuration file in ../configs/run_HELAC.ho
# - Modify the random seed first:
sed -e "s/MY_SEED/$SEED/" ../configs/run_HELAC.ho.tpl > ../configs/run_HELAC.ho

# - More config file changes
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

# - Run HELAC-Onia
./ho_cluster < ../configs/run_HELAC.ho | tee ../run_HELAC.log

# Collect output and input info from the run.
RUN_DIR=$(egrep "INFO: Results are collected in" ../run_HELAC.log | \
            sed -r -e "s,^.*(PROC_HO_[0-9]+)\/.*$,\1,g")

# - Copy the resulting LHE file to the current directory.
if [ -f "$RUN_DIR/P0_addon_pp_psiY_SPS/output/sample_pp_psiY_sps.lhe" ]; then
    # - Random shuffle the events in the LHE file if shower/shuffle_lhe.cpp is present.
    if [ -f "$WORKDIR/shower/shuffle_lhe.cpp" ]; then
        # - Potentially having "</event></LesHouchesEvents>" at the end of the LHE file can cause issues.
        # - Separate the last line if it contains these tags.
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

# - Count events in the LHE file
EVENT_COUNT=$(grep -c /event "$WORKDIR/helac_sample.lhe")
echo "Identified ${EVENT_COUNT} events in LHE file."

# - Split LHE file into chunks of 30 events to avoid segmentation faults
# Allow override via environment variable, otherwise use default of 30 events per chunk
EVENTS_PER_CHUNK=${EVENTS_PER_CHUNK:-30}
NUM_CHUNKS=$(( (EVENT_COUNT + EVENTS_PER_CHUNK - 1) / EVENTS_PER_CHUNK ))
echo "Splitting LHE file into ${NUM_CHUNKS} chunks of ${EVENTS_PER_CHUNK} events each."

# - Create directory for LHE chunks
LHE_CHUNK_DIR="$WORKDIR/lhe_chunks"
mkdir -p "$LHE_CHUNK_DIR"

# - Use event_splitter to split the LHE file
# Allow override via environment variable, otherwise use default path
EVENT_SPLITTER=${EVENT_SPLITTER:-/afs/cern.ch/user/c/chiw/condor/LHE-split/build/slc7_amd64_gcc12/event_splitter}
if [ ! -x "$EVENT_SPLITTER" ]; then
    echo "Error: event_splitter not found at $EVENT_SPLITTER"
    echo "You can override the path by setting EVENT_SPLITTER environment variable"
    exit 1
fi

$EVENT_SPLITTER -i "$WORKDIR/helac_sample.lhe" \
                -o "$LHE_CHUNK_DIR" \
                -n "$NUM_CHUNKS" \
                --file-prefix "chunk_" \
                --file-offset 0 \
                -seq

# Build Pythia 8 for showering:
cd shower/

g++  -I/afs/cern.ch/user/c/chiw/public/cms-utils/pythia8245/include \
  -I/afs/cern.ch/user/c/chiw/public/cms-utils/HepMC-2.06.11/install/include \
  -L/afs/cern.ch/user/c/chiw/public/cms-utils/HepMC-2.06.11/install/lib   Pythia82_reshower.cc -o Pythia8.exe  \
  -L/afs/cern.ch/user/c/chiw/public/cms-utils/pythia8245/lib -lpythia8 -I -L -lboost_iostreams \
  -L/afs/cern.ch/user/c/chiw/public/cms-utils/HepMC-2.06.11/install/lib -I/afs/cern.ch/user/c/chiw/public/cms-utils/HepMC-2.06.11/install//include -L/afs/cern.ch/user/c/chiw/public/cms-utils/HepMC-2.06.11/install//lib -lHepMC -ldl -lz

# - Process each LHE chunk with Pythia8
echo "Processing ${NUM_CHUNKS} LHE chunks with Pythia8 showering..."

# Backup the original command file since we'll create a symlink
if [ ! -f "Pythia8_lhe.cmnd.orig" ]; then
    cp Pythia8_lhe.cmnd Pythia8_lhe.cmnd.orig
fi

# Track successful and failed chunks
SUCCESSFUL_CHUNKS=0
FAILED_CHUNKS=0
FAILED_CHUNK_LIST=()

# Maximum number of retries for a failed chunk
MAX_RETRIES=2

for (( i=0; i<NUM_CHUNKS; i++ )); do
    CHUNK_FILE="$LHE_CHUNK_DIR/chunk_$(printf "%05d" $i).lhe"
    
    if [ ! -f "$CHUNK_FILE" ]; then
        echo "Warning: Chunk file $CHUNK_FILE not found, skipping."
        continue
    fi
    
    # Count events in this chunk
    CHUNK_EVENT_COUNT=$(grep -c /event "$CHUNK_FILE")
    echo "Processing chunk $i with ${CHUNK_EVENT_COUNT} events..."
    
    # Attempt to process this chunk with retries
    CHUNK_SUCCESS=0
    for (( retry=0; retry<=MAX_RETRIES; retry++ )); do
        if [ $retry -gt 0 ]; then
            echo "  Retry attempt $retry for chunk $i..."
        fi
        
        # Create a modified command file for this chunk
        CHUNK_CMND_TEMP="Pythia8_lhe_chunk_${i}.cmnd"
        cp Pythia8_lhe.cmnd.orig "$CHUNK_CMND_TEMP"
        
        # Update the command file to point to this chunk's LHE file and event count
        sed -i -e "s,Beams:LHEF = ../helac_sample.lhe,Beams:LHEF = $CHUNK_FILE,g" "$CHUNK_CMND_TEMP"
        sed -i -e "s,Main:numberOfEvents = 50,Main:numberOfEvents = ${CHUNK_EVENT_COUNT},g" "$CHUNK_CMND_TEMP"
        sed -i -e "s,Main:spareMode1 = 50,Main:spareMode1 = ${CHUNK_EVENT_COUNT},g" "$CHUNK_CMND_TEMP"
        
        # Replace Pythia8_lhe.cmnd with symlink to the chunk-specific command file
        rm -f Pythia8_lhe.cmnd
        ln -s "$CHUNK_CMND_TEMP" Pythia8_lhe.cmnd
        
        # Run the single Pythia8 executable and capture exit status
        set +e  # Don't exit on error
        ./Pythia8.exe > "pythia8_chunk_${i}.log" 2>&1
        PYTHIA_EXIT_CODE=$?
        set -e  # Re-enable exit on error
        
        # Check if Pythia8 completed successfully
        CHUNK_OUTPUT="Pythia8_lhe_chunk_${i}.hep"
        if [ $PYTHIA_EXIT_CODE -eq 0 ] && [ -f "Pythia8_lhe.hep" ]; then
            # Success! Move the output file
            mv Pythia8_lhe.hep "$CHUNK_OUTPUT"
            echo "Chunk $i processed successfully, output: $CHUNK_OUTPUT"
            CHUNK_SUCCESS=1
            SUCCESSFUL_CHUNKS=$((SUCCESSFUL_CHUNKS + 1))
            break
        else
            # Failure detected
            if [ $PYTHIA_EXIT_CODE -ne 0 ]; then
                echo "  Warning: Pythia8 exited with code $PYTHIA_EXIT_CODE for chunk $i"
            else
                echo "  Warning: Pythia8 did not produce output file for chunk $i"
            fi
            
            # Check for segfault or memory corruption in log
            if grep -q -i "segmentation fault\|double free\|corruption\|core dumped" "pythia8_chunk_${i}.log"; then
                echo "  Detected memory error (segfault/corruption) in Pythia8 for chunk $i"
            fi
            
            # Clean up any partial output
            rm -f Pythia8_lhe.hep
            
            # If this was the last retry, mark as failed
            if [ $retry -eq $MAX_RETRIES ]; then
                echo "  Failed to process chunk $i after $((MAX_RETRIES + 1)) attempts"
                FAILED_CHUNKS=$((FAILED_CHUNKS + 1))
                FAILED_CHUNK_LIST+=($i)
                
                # Save the error log for debugging
                if [ -f "pythia8_chunk_${i}.log" ]; then
                    echo "  Last 20 lines of error log:"
                    tail -20 "pythia8_chunk_${i}.log" | sed 's/^/    /'
                fi
            fi
        fi
        
        # Clean up intermediate files
        rm -f "$CHUNK_CMND_TEMP"
        
        # Small delay between retries to help with any timing-related issues
        if [ $retry -lt $MAX_RETRIES ] && [ $CHUNK_SUCCESS -eq 0 ]; then
            sleep 1
        fi
    done
    
    # Optionally keep log files for debugging
    # rm -f "pythia8_chunk_${i}.log"
done

# Restore the original command file
rm -f Pythia8_lhe.cmnd
mv Pythia8_lhe.cmnd.orig Pythia8_lhe.cmnd

# Print summary
echo ""
echo "========================================"
echo "Pythia8 Processing Summary"
echo "========================================"
echo "Total chunks: $NUM_CHUNKS"
echo "Successful: $SUCCESSFUL_CHUNKS"
echo "Failed: $FAILED_CHUNKS"
if [ $FAILED_CHUNKS -gt 0 ]; then
    echo "Failed chunk IDs: ${FAILED_CHUNK_LIST[*]}"
    echo ""
    echo "Warning: Some chunks failed to process due to Pythia8 errors."
    echo "Continuing with available chunks. Events from failed chunks will be lost."
fi
echo "Success rate: $(awk "BEGIN {printf \"%.1f\", ($SUCCESSFUL_CHUNKS/$NUM_CHUNKS)*100}")%"
echo "========================================"
echo ""

# Determine if we should continue or fail
if [ $SUCCESSFUL_CHUNKS -eq 0 ]; then
    echo "Error: No chunks were successfully processed!"
    exit 1
fi

# - Copy HepMC chunk files to WORKDIR for later GENSIM processing
echo "Copying HepMC chunk files to WORKDIR..."
COPIED_CHUNKS=0
for (( i=0; i<NUM_CHUNKS; i++ )); do
    CHUNK_HEP="Pythia8_lhe_chunk_${i}.hep"
    if [ -f "$CHUNK_HEP" ]; then
        cp "$CHUNK_HEP" "$WORKDIR/test_Jpsi1Jpsi1Y8_chunk_${i}.dat"
        echo "Copied $CHUNK_HEP to $WORKDIR/test_Jpsi1Jpsi1Y8_chunk_${i}.dat"
        COPIED_CHUNKS=$((COPIED_CHUNKS + 1))
    else
        echo "Warning: Chunk HepMC file $CHUNK_HEP not found (skipped or failed)"
    fi
done

echo ""
echo "Copied $COPIED_CHUNKS HepMC chunks to WORKDIR"

# Allow processing to continue even with some failures
if [ $FAILED_CHUNKS -gt 0 ]; then
    # Calculate the percentage of events lost
    EVENTS_LOST=$((FAILED_CHUNKS * EVENTS_PER_CHUNK))
    echo "Note: Approximately $EVENTS_LOST events were lost due to processing failures"
fi

echo "HepMC chunks prepared for GENSIM processing (${SUCCESSFUL_CHUNKS}/${NUM_CHUNKS} chunks)"

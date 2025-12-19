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
EVENTS_PER_CHUNK=30
NUM_CHUNKS=$(( (EVENT_COUNT + EVENTS_PER_CHUNK - 1) / EVENTS_PER_CHUNK ))
echo "Splitting LHE file into ${NUM_CHUNKS} chunks of ${EVENTS_PER_CHUNK} events each."

# - Create directory for LHE chunks
LHE_CHUNK_DIR="$WORKDIR/lhe_chunks"
mkdir -p "$LHE_CHUNK_DIR"

# - Use event_splitter to split the LHE file
EVENT_SPLITTER=/afs/cern.ch/user/c/chiw/condor/LHE-split/build/event_splitter
if [ ! -x "$EVENT_SPLITTER" ]; then
    echo "Error: event_splitter not found at $EVENT_SPLITTER"
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

for (( i=0; i<NUM_CHUNKS; i++ )); do
    CHUNK_FILE="$LHE_CHUNK_DIR/chunk_$(printf "%05d" $i).lhe"
    
    if [ ! -f "$CHUNK_FILE" ]; then
        echo "Warning: Chunk file $CHUNK_FILE not found, skipping."
        continue
    fi
    
    # Count events in this chunk
    CHUNK_EVENT_COUNT=$(grep -c /event "$CHUNK_FILE")
    echo "Processing chunk $i with ${CHUNK_EVENT_COUNT} events..."
    
    # Create a copy of the Pythia8 command file for this chunk
    CHUNK_CMND="Pythia8_lhe_chunk_${i}.cmnd"
    cp Pythia8_lhe.cmnd "$CHUNK_CMND"
    
    # Update the command file to point to this chunk
    sed -i -e "s,Beams:LHEF = ../helac_sample.lhe,Beams:LHEF = $CHUNK_FILE,g" "$CHUNK_CMND"
    sed -i -e "s,Main:numberOfEvents = 50,Main:numberOfEvents = ${CHUNK_EVENT_COUNT},g" "$CHUNK_CMND"
    sed -i -e "s,Main:spareMode1 = 50,Main:spareMode1 = ${CHUNK_EVENT_COUNT},g" "$CHUNK_CMND"
    
    # Create a modified version of the Pythia8 source with chunk-specific filenames
    CHUNK_OUTPUT="Pythia8_lhe_chunk_${i}.hep"
    sed -e "s/Pythia8_lhe.cmnd/$CHUNK_CMND/g" \
        -e "s/Pythia8_lhe.hep/$CHUNK_OUTPUT/g" \
        Pythia82_reshower.cc > "pythia8_chunk_${i}.cc"
    
    # Compile the modified version
    g++ -I/afs/cern.ch/user/c/chiw/public/cms-utils/pythia8245/include \
        -I/afs/cern.ch/user/c/chiw/public/cms-utils/HepMC-2.06.11/install/include \
        -L/afs/cern.ch/user/c/chiw/public/cms-utils/HepMC-2.06.11/install/lib \
        "pythia8_chunk_${i}.cc" -o "pythia8_chunk_${i}.exe" \
        -L/afs/cern.ch/user/c/chiw/public/cms-utils/pythia8245/lib -lpythia8 \
        -lboost_iostreams \
        -L/afs/cern.ch/user/c/chiw/public/cms-utils/HepMC-2.06.11/install/lib \
        -lHepMC -ldl -lz
    
    # Run the chunk-specific executable
    "./pythia8_chunk_${i}.exe" > "pythia8_chunk_${i}.log" 2>&1
    
    if [ ! -f "$CHUNK_OUTPUT" ]; then
        echo "Error: Failed to generate HepMC output for chunk $i"
        cat "pythia8_chunk_${i}.log"
        exit 1
    fi
    
    echo "Chunk $i processed successfully, output: $CHUNK_OUTPUT"
done

# - Copy HepMC chunk files to WORKDIR for later GENSIM processing
echo "Copying HepMC chunk files to WORKDIR..."
for (( i=0; i<NUM_CHUNKS; i++ )); do
    CHUNK_HEP="Pythia8_lhe_chunk_${i}.hep"
    if [ -f "$CHUNK_HEP" ]; then
        cp "$CHUNK_HEP" "$WORKDIR/test_Jpsi1Jpsi1Y8_chunk_${i}.dat"
        echo "Copied $CHUNK_HEP to $WORKDIR/test_Jpsi1Jpsi1Y8_chunk_${i}.dat"
    else
        echo "Warning: Chunk HepMC file $CHUNK_HEP not found"
    fi
done

echo "All HepMC chunks prepared for GENSIM processing"

#! /bin/bash

# This script is used to build and run HELAC-Onia in a compact way.
# - Accept arguments: -n for new build, -s for seed.
AS_NEW=0
SEED=11
WORKDIR=$(pwd)

while getopts ":ns:" opt; do
    case $opt in
        n)
            AS_NEW=1
            ;;
        s)
            SEED=$OPTARG
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

# Environment variables for the first part of the script.
source ~/.bash_profile
source /cvmfs/cms.cern.ch/cmsset_default.sh
source /cvmfs/sft.cern.ch/lcg/views/LCG_88b/x86_64-centos7-gcc62-opt/setup.sh
export LD_LIBRARY_PATH=/cvmfs/sft.cern.ch/lcg/releases/LCG_88b/Boost/1.62.0/x86_64-centos7-gcc62-opt/lib:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=/cvmfs/sft.cern.ch/lcg/contrib/gcc/6.2.0/x86_64-centos7-gcc62-opt/lib64:/opt/rh/gcc-toolset-12/root/usr/lib64:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=/cvmfs/sft.cern.ch/lcg/releases/LCG_88b/Boost/1.62.0/x86_64-centos7-gcc62-opt/lib:$LD_LIBRARY_PATH

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

# Check file package integrity.
if [ ! -d "HepMC/HepMC-2.06.11" ]; then
    AS_NEW=1
    if [ ! -f "sources/hepmc2.06.11.tgz" ]; then
        echo "Error: No HepMC-2.06.11 available"
        exit 1
    fi
fi

if [ ! -d "HELAC-Onia-2.7.6" ]; then
    AS_NEW=1
    if [ ! -f "sources/HELAC-Onia-2.7.6.tar.gz" ]; then
        echo "Error: No HELAC-Onia-2.7.6 available"
        exit 1
    fi
fi

# Build HepMC
if [ $AS_NEW -eq 1 ]; then
    rm -rf HepMC
    mkdir -p HepMC
    cd HepMC
    tar -xzvf ../sources/hepmc2.06.11.tgz
    HEPMC_DIR=$(pwd)/HepMC-2.06.11
    mkdir -p build
    mkdir -p install
    cd build
    $HEPMC_DIR/configure --prefix=$HEPMC_DIR/install --with-momentum=GEV --with-length=MM
    make
    make check
    make install
    cd ../../
else
    echo "Using existing HepMC build"
fi

# With HepMC installed, we can set the environment variables for the rest of the script.
export PATH=$HEPMC_DIR/install:$PATH
export LD_LIBRARY_PATH=$HEPMC_DIR/install/lib:$LD_LIBRARY_PATH

# Build HELAC-Onia.
if [ $AS_NEW -eq 1 ]; then
    # - Remove any existing build
    rm -rf HELAC-Onia-2.7.6
    tar -xzvf sources/HELAC-Onia-2.7.6.tar.gz
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
    sed -i -r -e "s|^#.*hepmc_path.*$|hepmc_path = $HEPMC_DIR/install|" input/ho_configuration.txt

    # - Compile HELAC-Onia
    ./config
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

if [ -f "../configs/addon/pp_NOnia_MPS/input/states.inp" ]; then
    cp ../configs/addon/pp_NOnia_MPS/input/states.inp addon/pp_NOnia_MPS/input/states.inp
fi

# - Run HELAC-Onia
./ho_cluster < ../configs/run_HELAC.ho | tee ../run_HELAC.log

# Collect output and input info from the run.
RUN_DIR=$(egrep "INFO: Results are collected in" ../run_HELAC.log | \
            sed -r -e "s,^.*(PROC_HO_[0-9]+)\/.*$,\1,g")

# - Copy the resulting LHE file to the current directory.
if [ -f "$RUN_DIR/P0_addon_pp_NOnia_MPS/output/sample_pp_nonia_mps.lhe" ]; then
    cp "$RUN_DIR/P0_addon_pp_NOnia_MPS/output/sample_pp_nonia_mps.lhe" "$WORKDIR/sample_pp_nonia_mps.lhe"
else
    echo "Error: No output LHE file found in $RUN_DIR/P0_addon_pp_NOnia_MPS/output/"
    exit 1
fi

cd "$WORKDIR"

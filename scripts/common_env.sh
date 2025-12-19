#! /bin/bash
# Common environment setup for HELAC-Onia and Pythia8 workflows

# Default paths - can be overridden by environment variables
HEPMC_DIR=${HEPMC_DIR:-/afs/cern.ch/user/c/chiw/public/cms-utils/HepMC-2.06.11/install}
PYTHIA_INSTALL_PATH=${PYTHIA_INSTALL_PATH:-/afs/cern.ch/user/c/chiw/public/cms-utils/pythia8245}
MY_LIBBOOST_A=${MY_LIBBOOST_A:-/cvmfs/sft.cern.ch/lcg/releases/LCG_88b/Boost/1.62.0/x86_64-centos7-gcc62-opt/lib/libboost_iostreams-gcc62-mt-1_62.a}
MY_LIBBOOST_SO=${MY_LIBBOOST_SO:-/cvmfs/sft.cern.ch/lcg/releases/LCG_88b/Boost/1.62.0/x86_64-centos7-gcc62-opt/lib/libboost_iostreams-gcc62-mt-1_62.so}

# Setup environment
source ~/.bash_profile
source /cvmfs/cms.cern.ch/cmsset_default.sh
source /cvmfs/sft.cern.ch/lcg/views/LCG_88b/x86_64-centos7-gcc62-opt/setup.sh
export LD_LIBRARY_PATH=/cvmfs/sft.cern.ch/lcg/releases/LCG_88b/Boost/1.62.0/x86_64-centos7-gcc62-opt/lib:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=/cvmfs/sft.cern.ch/lcg/contrib/gcc/6.2.0/x86_64-centos7-gcc62-opt/lib64:/opt/rh/gcc-toolset-12/root/usr/lib64:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=/cvmfs/sft.cern.ch/lcg/releases/LCG_88b/Boost/1.62.0/x86_64-centos7-gcc62-opt/lib:$LD_LIBRARY_PATH

# HepMC environment
export PATH=$HEPMC_DIR:$PATH
export LD_LIBRARY_PATH=$HEPMC_DIR/lib:$LD_LIBRARY_PATH

# Create symbolic links for Boost libraries (if not already exist)
if [ ! -L "$HEPMC_DIR/lib/libboost_iostreams.a" ]; then
    ln -s $MY_LIBBOOST_A $HEPMC_DIR/lib/libboost_iostreams.a 2>/dev/null || true
fi
if [ ! -L "$HEPMC_DIR/lib/libboost_iostreams.so" ]; then
    ln -s $MY_LIBBOOST_SO $HEPMC_DIR/lib/libboost_iostreams.so 2>/dev/null || true
fi

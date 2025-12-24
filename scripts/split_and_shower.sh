#! /bin/bash
# set -euo pipefail
# Arguments: <INPUT_LHE> <PYTHIA_CMND> <OUTPUT_HEPMC>
INPUT_LHE="$1"
PYTHIA_CMND="$2"
OUTPUT_HEPMC="$3"
PYTHIA_CMND_TPL="$2".template

# Unless otherwise specified, use a pre-defined shower executable and other utilities.
LHE_SPLITTER="/afs/cern.ch/user/c/chiw/condor/LHE-split/build/slc7_amd64_gcc12/event_splitter"
LHE_SHUFFLE="/afs/cern.ch/user/c/chiw/condor/LHE-to-SKIM/build/slc7_amd64_gcc12/shuffleLHE"
SHOWER_EXECUTABLE="/afs/cern.ch/user/c/chiw/condor/LHE-to-SKIM/Pythia8.exe"
HEPMC_CONCATENNATE="/afs/cern.ch/user/c/chiw/condor/LHE-to-SKIM/hepmcConcat"
# - Determine if shuffling is carried out
DO_LHE_SHUFFLE=1

# Split parameters
SPLIT_SIZE=30
SPLIT_PER_DIR=1000
SPLIT_FILE_DIGITS=4
SPLIT_SUBDIR_DIGITS=4
EVENT_COUNT=$(grep -c "<event>" "$INPUT_LHE")
SPLIT_LHE_DIR=$(pwd)/lhe_split
SPLIT_LHE_PREFIX=split_
SPLIT_FILE_COUNT=$(( (EVENT_COUNT + SPLIT_SIZE - 1) / SPLIT_SIZE ))
SPLIT_SUBDIR_COUNT=$(( (SPLIT_FILE_COUNT + SPLIT_PER_DIR - 1) / SPLIT_PER_DIR ))
# - Use awk to generate all split product file names.
# - Be careful with the subdirectories.
SPLIT_FILES=$( \
    awk -v splitDir="$SPLIT_LHE_DIR" \
        -v splitDigit="$SPLIT_FILE_DIGITS" \
        -v splitCount="$SPLIT_FILE_COUNT" \
        -v splitPerSubdir="$SPLIT_PER_DIR" \
        -v splitPrefix="$SPLIT_LHE_PREFIX" \
        -v subdirDigit="$SPLIT_SUBDIR_DIGITS" \
        'BEGIN{
            for(i=0;i<splitCount;i++) {
                printf("%s/%0*d/%s%0*d.lhe\n", splitDir, subdirDigit, i/splitPerSubdir, splitPrefix, splitDigit, i%splitPerSubdir)
            }
        }'

)

HEPMC_SHOWERED_DIR=$(pwd)/hepmc_showered
HEPMC_SHOWERED_SUBDIRS=$(
    awk -v hepmcDir="$HEPMC_SHOWERED_DIR" \
        -v subdirCount="$SPLIT_SUBDIR_COUNT" \
        -v subdirDigit="$SPLIT_SUBDIR_DIGITS" \
    'BEGIN{
        for(i=0;i<subdirCount;i++) {
            printf("%s/%0*d\n", hepmcDir, subdirDigit, i)
        }
    }'
)
HEPMC_SHOWERED_FILES=$( \
    awk -v hepmcDir="$HEPMC_SHOWERED_DIR" \
        -v splitDigit="$SPLIT_FILE_DIGITS" \
        -v splitCount="$SPLIT_FILE_COUNT" \
        -v splitPerSubdir="$SPLIT_PER_DIR" \
        -v splitPrefix="$SPLIT_LHE_PREFIX" \
        -v subdirDigit="$SPLIT_SUBDIR_DIGITS" \
        'BEGIN{
            for(i=0;i<splitCount;i++) {
                printf("%s/%0*d/%s%0*d.hepmc\n", hepmcDir, subdirDigit, i/splitPerSubdir, splitPrefix, splitDigit, i%splitPerSubdir)
            }
        }'

)

# 1. Split the LHE file into smaller chunks, ideally 20-30 events each.
mkdir -p "$SPLIT_LHE_DIR"
# - Split "</event></LesHouchesEvents>" lines.
sed -i -e 's,</event></LesHouchesEvents>,</event>\n</LesHouchesEvents>,g' "$INPUT_LHE"
# - Then, the splitter does its job.
"$LHE_SPLITTER" --input "$INPUT_LHE" --output-dir "$SPLIT_LHE_DIR" --num-files "$SPLIT_FILE_COUNT" --file-prefix "$SPLIT_LHE_PREFIX" --file-width "$SPLIT_FILE_DIGITS" --subdirs --subdir-width "$SPLIT_SUBDIR_DIGITS" --files-per-subdir "$SPLIT_PER_DIR"

# exit 0
# 2. Shower each splitted LHE file using Pythia8. Take caution of the subdirectories.
for SUBDIR in $HEPMC_SHOWERED_SUBDIRS; do
    mkdir -p "$SUBDIR"
done

# Temporatily keep the template Pythia 8 command
cp "$PYTHIA_CMND" "$PYTHIA_CMND_TPL"

for LHE_FILE in $SPLIT_FILES; do
    DIR_PATH=$(dirname "$LHE_FILE")
    # Extract relative subdirectory (e.g., "0000") by removing the base directory prefix
    SUBDIR_REL=${DIR_PATH#$SPLIT_LHE_DIR/}
    BASENAME=$(basename -s .lhe "$LHE_FILE")
        
    # Shuffle
    if [ $DO_LHE_SHUFFLE -eq 1 ]; then
        LHE_FILE_TEMP="$DIR_PATH/${BASENAME}_temp.lhe"
        "$LHE_SHUFFLE" "$LHE_FILE" "$LHE_FILE_TEMP" && mv "$LHE_FILE_TEMP" "$LHE_FILE"
    fi

    OUTPUT_FILE="$HEPMC_SHOWERED_DIR/$SUBDIR_REL/$BASENAME.hepmc"
    
    # Count number of events in the split file.
    SPLIT_LHE_EVENT_COUNT=$(grep -c '<event>' "$LHE_FILE")
    # Generate the corresponding command.
    sed -e "s,Main:numberOfEvents = 50,Main:numberOfEvents = ${SPLIT_LHE_EVENT_COUNT},g" \
        -e "s,Main:spareMode1 = 50,Main:spareMode1 = ${SPLIT_LHE_EVENT_COUNT},g" \
        "$PYTHIA_CMND_TPL" > "$PYTHIA_CMND"

    # Adding a failsafe for Pythia8 stageout with segmentation fault.
    # Directly check the exit code of the command.
    if ! "$SHOWER_EXECUTABLE" --lhef "$LHE_FILE" --cmnd "$PYTHIA_CMND" --output "$OUTPUT_FILE"; then
        echo "Error occurred while processing $LHE_FILE"
    fi
done

cp "$PYTHIA_CMND_TPL" "$PYTHIA_CMND"

# 3. Concatenate all the showered HepMC files into a single output file.
echo ">>> Concatenating HepMC files into: $OUTPUT_HEPMC"
"$HEPMC_CONCATENNATE" "$OUTPUT_HEPMC" $(echo "$HEPMC_SHOWERED_FILES" | tr '\n' ' ')

rm -r "$HEPMC_SHOWERED_DIR" "$SPLIT_LHE_DIR"

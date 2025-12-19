# This Makefile is used to manage HELAC-on-HTCondor workflows

.PHONY: submit submit_full submit_shower dryrun help

# Default target
help:
	@echo "Available targets:"
	@echo "  submit_full   - Submit full workflow (HELAC generation + shower) to HTCondor"
	@echo "  submit_shower - Submit shower-only workflow (use existing LHE files) to HTCondor"
	@echo "  submit        - Alias for submit_full (backward compatibility)"
	@echo "  dryrun        - Dry run of full workflow"
	@echo "  seeds.txt     - Generate seed file"
	@echo ""
	@echo "Environment variables for submit_shower:"
	@echo "  LHE_SOURCE_DIR - Directory containing existing LHE files (required)"
	@echo "  LHE_ARCHIVE_DIR - Directory to archive LHE files (optional)"

# Full workflow: HELAC generation + shower
submit_full: condor_submit_full.tar condor_submit_full.sub seeds.txt
	mkdir -p log
	condor_submit condor_submit_full.sub

# Shower-only workflow: process existing LHE files
submit_shower: condor_submit_shower.tar seeds.txt
	@if [ -z "$(LHE_SOURCE_DIR)" ]; then \
		echo "Error: LHE_SOURCE_DIR must be set"; \
		echo "Usage: make submit_shower LHE_SOURCE_DIR=/path/to/lhe/files"; \
		exit 1; \
	fi
	mkdir -p log
	@echo "Generating condor_submit_shower.sub with LHE_SOURCE_DIR=$(LHE_SOURCE_DIR)"
	@sed -e 's|LHE_SOURCE_DIR_PLACEHOLDER|$(LHE_SOURCE_DIR)|g' \
	     -e 's|LHE_ARCHIVE_DIR_PLACEHOLDER|$(LHE_ARCHIVE_DIR)|g' \
	     condor_submit_shower.sub.template > condor_submit_shower.sub
	condor_submit condor_submit_shower.sub

# Backward compatibility
submit: submit_full

dryrun: condor_submit_full.tar condor_submit_full.sub seeds.txt
	mkdir -p log
	condor_submit condor_submit_full.sub -dry-run dryrun.log

seeds.txt:
	seq 11 20 > $@

# Full workflow tarball
condor_submit_full.tar: configs/* patch/* scripts/* sources/HELAC-Onia-2.7.6.tar.gz shower/*
	tar -cvf $@ $^

# Shower-only workflow tarball (no HELAC sources needed)
condor_submit_shower.tar: configs/* scripts/* shower/*
	tar -cvf $@ $^

# Backward compatibility
condor_submit.tar: condor_submit_full.tar
	cp $< $@

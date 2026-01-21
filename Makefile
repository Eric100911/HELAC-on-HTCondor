# Makefile for HELAC-on-HTCondor Integrated MC Workflow
#
# Targets:
#   make submit      - Submit traditional HELAC jobs
#   make workflow    - Generate and submit DAGman workflow
#   make tools       - Build C++ tools (lhe_mixer, hepmc_mixer)
#   make clean       - Clean build artifacts
#

# Compiler settings
CXX = g++
CXXFLAGS = -std=c++17 -O2 -Wall -Wextra
LDFLAGS =

# HepMC paths (set these or use CMSSW environment)
HEPMC2_DIR ?= $(shell echo $$HEPMC_DIR)
HEPMC3_DIR ?= $(shell echo $$HEPMC3_DIR)

# Phony targets
.PHONY: all submit dryrun workflow workflow-dryrun tools clean help test test-unit test-integration

# Default target
all: tools

help:
	@echo "Available targets:"
	@echo "  make submit        - Submit traditional HELAC jobs (individual seeds)"
	@echo "  make dryrun        - Dry run of traditional submission"
	@echo "  make workflow      - Generate and submit DAGman workflow"
	@echo "  make workflow-dryrun - Dry run of DAGman workflow"
	@echo "  make tools         - Build C++ tools"
	@echo "  make test          - Run all tests"
	@echo "  make test-unit     - Run unit tests only"
	@echo "  make test-integration - Run integration tests only"
	@echo "  make clean         - Clean build artifacts"

# =============================================================================
# Traditional submission (original functionality)
# =============================================================================

submit: condor_submit.tar condor_submit.sub seeds.txt
	mkdir -p log
	condor_submit condor_submit.sub

dryrun: condor_submit.tar condor_submit.sub seeds.txt
	mkdir -p log
	condor_submit condor_submit.sub -dry-run dryrun.log

seeds.txt:
	seq 11 20 > $@

condor_submit.tar: configs/* patch/* scripts/* sources/HELAC-Onia-2.7.6.tar.gz sources/hepmc2.06.11.tgz
	tar -cvf $@ $^

sources/HELAC-Onia-2.7.6.tar.gz:
	mkdir -p sources
	wget http://www.lpthe.jussieu.fr/~hshao/download/HELAC-Onia-2.7.6.tar.gz -O sources/HELAC-Onia-2.7.6.tar.gz

sources/hepmc2.06.11.tgz:
	mkdir -p sources
	wget http://hepmc.web.cern.ch/hepmc/releases/hepmc2.06.11.tgz -O sources/hepmc2.06.11.tgz

# =============================================================================
# Integrated DAGman workflow
# =============================================================================

workflow: workflow/generated.dag condor_submit.tar
	mkdir -p log
	condor_submit_dag workflow/generated.dag

workflow-dryrun: workflow/generated.dag
	mkdir -p log
	condor_submit_dag -dry-run dryrun_dag.log workflow/generated.dag

workflow/generated.dag: workflow/workflow_config.yaml workflow/generate_dag.py
	python3 workflow/generate_dag.py workflow/workflow_config.yaml --output workflow/

workflow/workflow_config.yaml: workflow/workflow_config.yaml.example
	@if [ ! -f $@ ]; then \
		echo "Creating workflow config from example..."; \
		cp $< $@; \
		echo "Please edit workflow/workflow_config.yaml for your setup"; \
	fi

# =============================================================================
# C++ Tools
# =============================================================================

tools: bin/lhe_mixer bin/pythia8_shower

bin/lhe_mixer: src/lhe_mixer.cpp src/lhe_mixer.hpp
	mkdir -p bin
	$(CXX) $(CXXFLAGS) -o $@ src/lhe_mixer.cpp $(LDFLAGS)
	@echo "Built lhe_mixer"

# Standalone Pythia 8 shower (requirement: not via cmsRun)
bin/pythia8_shower: src/pythia8_shower.cpp
	@echo "Building standalone Pythia8 shower..."
	@if [ -z "$(PYTHIA8)" ]; then \
		echo "Error: PYTHIA8 environment variable not set"; \
		echo "  Source CMSSW environment or set PYTHIA8 path manually"; \
		echo "  Example: export PYTHIA8=/cvmfs/cms.cern.ch/slc7_amd64_gcc900/external/pythia8/244-ghbfee"; \
		exit 1; \
	fi
	@if [ -z "$(HEPMC_DIR)" ] && [ -z "$(HEPMC2_DIR)" ]; then \
		echo "Error: HEPMC_DIR or HEPMC2_DIR must be set"; \
		echo "  Source CMSSW environment or set path manually"; \
		exit 1; \
	fi
	mkdir -p bin
	$(CXX) $(CXXFLAGS) -o $@ src/pythia8_shower.cpp \
		-I$(PYTHIA8)/include \
		-I$(or $(HEPMC_DIR),$(HEPMC2_DIR))/include \
		-L$(PYTHIA8)/lib \
		-L$(or $(HEPMC_DIR),$(HEPMC2_DIR))/lib \
		-Wl,-rpath,$(PYTHIA8)/lib \
		-Wl,-rpath,$(or $(HEPMC_DIR),$(HEPMC2_DIR))/lib \
		-lpythia8 -lHepMC
	@echo "Built pythia8_shower"

# HepMC mixer requires HepMC2 and HepMC3 libraries
bin/hepmc_mixer: src/hepmc_mixer.cpp
	@if [ -z "$(HEPMC2_DIR)" ] || [ -z "$(HEPMC3_DIR)" ]; then \
		echo "Error: HEPMC2_DIR and HEPMC3_DIR must be set"; \
		echo "  Source CMSSW environment or set paths manually"; \
		exit 1; \
	fi
	mkdir -p bin
	$(CXX) $(CXXFLAGS) -o $@ src/hepmc_mixer.cpp \
		-I$(HEPMC3_DIR)/include -I$(HEPMC2_DIR)/include \
		-L$(HEPMC3_DIR)/lib64 -L$(HEPMC3_DIR)/lib \
		-L$(HEPMC2_DIR)/lib64 -L$(HEPMC2_DIR)/lib \
		-Wl,-rpath,$(HEPMC3_DIR)/lib64 -Wl,-rpath,$(HEPMC3_DIR)/lib \
		-Wl,-rpath,$(HEPMC2_DIR)/lib64 -Wl,-rpath,$(HEPMC2_DIR)/lib \
		-lHepMC3 -lHepMC
	@echo "Built hepmc_mixer"

# =============================================================================
# Cleanup
# =============================================================================

clean:
	rm -rf bin/
	rm -f condor_submit.tar
	rm -f seeds.txt
	rm -f dryrun.log dryrun_dag.log
	rm -f workflow/generated.dag workflow/generated.dag.*
	rm -f workflow/*.sub
	rm -rf log/

distclean: clean
	rm -rf sources/

# =============================================================================
# Testing
# =============================================================================

test: tools
	@echo "Running all tests..."
	./run_tests.sh --all

test-unit: tools
	@echo "Running unit tests..."
	./run_tests.sh --unit

test-integration: tools
	@echo "Running integration tests..."
	./run_tests.sh --integration

test-verbose: tools
	@echo "Running all tests (verbose)..."
	./run_tests.sh --all --verbose
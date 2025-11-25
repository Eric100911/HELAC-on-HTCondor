# This Makefile is used to keep track of the files in the HELAC-on-HTCondor directory.

.PHONY: submit dryrun local

submit: condor_submit.tar condor_submit.sub seeds.txt main.sh
	mkdir -p log
	condor_submit condor_submit.sub

dryrun: condor_submit.tar condor_submit.sub seeds.txt main.sh
	mkdir -p log
	condor_submit condor_submit.sub -dry-run dryrun.log

local: condor_submit.tar condor_submit.sub main.sh
	rm -rf local/
	mkdir -p local
	cp condor_submit.tar local/
	cp condor_submit.sub local/
	cp main.sh local/
	@echo "Run the following commands to execute locally:"
	@echo "cd local"
	@echo "bash main.sh <your_seed>"

seeds.txt:
	seq 11 20 > $@

condor_submit.tar: configs/* patch/* scripts/* sources/HELAC-Onia-2.7.6.tar.gz
	tar -cvf $@ $^

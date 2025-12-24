# This Makefile is used to keep track of the files in the HELAC-on-HTCondor directory.

.PHONY: submit dryrun

submit: condor_submit.tar condor_submit.sub seeds.txt
	mkdir -p log
	condor_submit condor_submit.sub

prepLocalShower: condor_submit.tar main.sh helac_sample.lhe
	@ echo ">>> Will test shower workflow. Based on helac_sample.lhe"
	@ rm -rf local/*
	@ mkdir -p local/
	@ cp helac_sample.lhe local/
	@ cp main.sh local/
	@ cp condor_submit.tar local/
	@ echo ">>> To proceed with local test, execute: 'cd local && bash main.sh <YOUR_SEED>' "


prepLocalFull: condor_submit.tar main.sh
	echo ">>> Will test full workflow."
	@ mkdir -p local/
	@ rm -r local/*
	@ cp main.sh local/
	@ cp condor_submit.tar local/
	echo ">>> To proceed with local test, execute: 'cd local && bash main.sh <YOUR_SEED>' "


dryrun: condor_submit.tar condor_submit.sub seeds.txt
	mkdir -p log
	condor_submit condor_submit.sub -dry-run dryrun.log

seeds.txt:
	seq 11 20 > $@

condor_submit.tar: configs/* patch/* scripts/* sources/HELAC-Onia-2.7.6.tar.gz shower/*
	tar -cvf $@ $^

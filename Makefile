# This Makefile is used to keep track of the files in the HELAC-on-HTCondor directory.

.PHONY: submit dryrun

submit: condor_submit.tar condor_submit.sub seeds.txt
	mkdir -p log
	condor_submit condor_submit.sub

dryrun: condor_submit.tar condor_submit.sub seeds.txt
	mkdir -p log
	condor_submit condor_submit.sub -dry-run dryrun.log

seeds.txt:
	seq 11 20 > $@

condor_submit.tar: configs/* patch/* scripts/* sources/*
	tar -cvf $@ $^

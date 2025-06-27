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

condor_submit.tar: configs/* patch/* scripts/* sources/HELAC-Onia-2.7.6.tar.gz sources/hepmc2.06.11.tgz
	tar -cvf $@ $^

sources/HELAC-Onia-2.7.6.tar.gz:
	mkdir -p sources
	wget http://www.lpthe.jussieu.fr/~hshao/download/HELAC-Onia-2.7.6.tar.gz -O sources/HELAC-Onia-2.7.6.tar.gz

sources/hepmc2.06.11.tgz:
	mkdir -p sources
	wget http://hepmc.web.cern.ch/hepmc/releases/hepmc2.06.11.tgz -O sources/hepmc2.06.11.tgz
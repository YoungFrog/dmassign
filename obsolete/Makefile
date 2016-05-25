### WARNING: Do not use this Makefile at all. If you want to know why,
### then:
### README FIRST ###
### This file was written with the purpose of being helpful while
### using the perl program *but* that target was missed by far.
### Problems are :
### - It is not easy at all
### - Keep data and program together is doomed to fail : the data
### changes both when a newyear begins and when the program evolves
### for accepting new information. Those two types of evolution are
### incompatible (older data should not have to migrate to newer
### format !)
### - It is trying to detect when the program (pl, pm) and the data
### (txt, etc.) change, but since they live in different directories
### it makes the detection a tough problem, which was solved through
### variables but those are in turn annoying to set from command line.
### - We are keeping modules in a subdirectory, which adds to the
### previous mess of paths.

### As a consequence THIS FILE IS NOT MAINTAINED ANYMORE, I only keep
### it to keep track of my mistakes.


# Used for releasing.
RELEASE_DATE=$(shell date +%F-%H:%M)
RELEASE_DIR=2014-2015/draft-$(RELEASE_DATE)

# # Used for compiling into an executable
# RELEASE_EXECFILE=dmassign-$(RELEASE_DATE)

# Options passed to main.pl. Useful are: --quiet, -0123456789 (or a
# subset of that), etc. They are separated by space. See "perl main.pl
# --help" for more options.

# OPTIONS="--quiet -123"
OPTIONS=

PERLDIR=$(error Please define PERLDIR)
DATADIR=$(error Please define DATADIR)
OUTPUTDIR=$(error Please define OUTPUTDIR)
PROGRAM=perl -I"$(PERLDIR)" "$(PERLDIR)/main.pl" $(OPTIONS) --indir	\
"$(DATADIR)" --outdir "$(OUTPUTDIR)"

VPATH=$(DATADIR):$(PERLDIR):$(OUTPUTDIR)

## Define files :
PROGRAM_FILES=main.pl AdministrativeTask.pm Course.pm           \
CreneauHoraire.pm HMS.pm Horaire.pm Modulation.pm MyDebug.pm    \
Teacher.pm TeachingTask.pm report-skeleton.tex Makefile
EL_FILES=dmassign.el
SOURCE_FILES=cours.txt profs.txt repartition.txt sciences.txt   \
taches.txt catalogue-sciences.csv
SECONDARY_FILES=all.tex load.data load.gnuplot load.pdf
INTERMEDIATE_FILES=all.log all.aux all.fdb_latexmk all.fls
END_FILES=all.pdf

USEFUL_FILES=$(PROGRAM_FILES) $(EL_FILES) $(SOURCE_FILES) $(SECONDARY_FILES) $(END_FILES)

.PHONY: all release run-perl-program clean releasewithperl charges conflicts help
.SECONDARY: $(SECONDARY_FILES) run-perl-program

all.pdf: all.tex load.pdf
	cd "$(OUTPUTDIR)"; latexmk -pdf all.tex
# dmassign: main.cpp
# 	g++ main.cpp -o $(RELEASE_EXECFILE)
# 	ln -svf $(RELEASE_EXECFILE) dmassign
load.gnuplot load.data all.tex: run-perl-program
load.pdf: load.eps
	cd "$(OUTPUTDIR)"; ps2pdf load.eps 
load.eps: load.gnuplot load.data
	cd "$(OUTPUTDIR)"; gnuplot load.gnuplot

dmassign: dmassign.pl
	pp -M Text::CSV_PP -M Class::Load::XS -M PerlIO::encoding -o dmassign dmassign.pl
run-perl-program: $(SOURCE_FILES) $(PROGRAM_FILES)
	$(PROGRAM) --report
TAGS:
	find . -name "*.[ch]" -print | xargs etags -a

releasewithperl: $(END_FILES)
	mkdir -p $(RELEASE_DIR)
	@echo Copying files...
	cp -i $(USEFUL_FILES) $(RELEASE_DIR)
	@echo Released at $(RELEASE_DIR)
	$(MAKE) clean
clean:
	rm -f $(SECONDARY_FILES) $(INTERMEDIATE_FILES)
conflicts:
	$(PROGRAM) --teacher-conflicts
chargesparquadri:
	$(PROGRAM) -0 --teacher-charges --quadri Q1
	$(PROGRAM) -1 --teacher-charges --quadri Q1
	$(PROGRAM) -2 --teacher-charges --quadri Q1
	$(PROGRAM) -0 --teacher-charges --quadri Q2
	$(PROGRAM) -1 --teacher-charges --quadri Q2
	$(PROGRAM) -2 --teacher-charges --quadri Q2
charges:
	$(PROGRAM) -0 --teacher-charges
	$(PROGRAM) -1 --teacher-charges
	$(PROGRAM) -2 --teacher-charges

help:
	$(info )
	$(info make help              - This message)
	$(info make all.pdf           - Make a temporary build for checking)
	$(info make main              - (not working) Bundle perl into an executable)
	$(info make run-perl-program  - Output a report as .tex file)
	$(info make TAGS              - TAGS file suitable for use by emacs)
	$(info make releasewithperl   - Save all files (program+output) to the)
	$(info                          directory pointed at by the RELEASE_DIR)
	$(info                          make variable)
	$(info                          (default is $(RELEASE_DIR)))
	$(info make clean             - Remove intermediate files)
	$(info make conflicts         - Output a report on conflicts)
	$(info make chargesparquadri  - Output a report on assistants\' workload)
	$(info make charges           - Ditto, not split by quadri)

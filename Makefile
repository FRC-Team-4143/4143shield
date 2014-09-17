# Symbols and footprints in the current directory are symlinks to their
# built versions in subdirectories.

# vim: set foldmethod=marker

# Make sure we can use bashisms.
SHELL= /bin/bash

# Don't automagically remove 'intermediate' files.
.SECONDARY:

# Delete files produces by rules whose commands fail (return non-zero).
.DELETE_ON_ERROR:

# Part-related stuff {{{1

# Helper Scripts {{{2

# None of these helper scripts get cleaned by make clean, though the ones
# that get pulled in from elsewhere will get updated if they change.
HELPER_SCRIPTS := \
  Makefile \
  check_pin_names.perl \
  check_refdes_uniqueness.perl \
  guess_value \
  set_symbol_attribute \
  tragesym

# For mainly historical reasons we keep the master copy of this script
# elsewhere.
check_pin_names.perl: ~/.helper_scripts/check_pin_names.perl
	cp $< .

# For mainly historical reasons we keep the master copy of this script
# elsewhere.
check_refdes_uniqueness.perl: ~/.helper_scripts/check_refdes_uniqueness.perl
	cp $< .

# Make a local copy of the tragesym script.
tragesym: $(shell which tragesym)
	cp $< $@

# }}}2

# Symbols and Footprints Files to Generate {{{2

# Each symbol has a source (or model really) in its part directory.  NOTE:
# its quite possible -L could get us in trouble here somehow.  We use it so
# we can have parts directories that are symbolic links into other projects.
# This also seems to work if we want to have a symbol.src that is itself
# a link: find seems to still report the name of the link rather than
# its target.
SYMBOL_SRCS := $(shell find -L . -name symbol.src)
# A built version of the symbol is produced from the model in the part dir.
BUILT_SYMBOLS :=  $(patsubst %.src,%.built,$(SYMBOL_SRCS))
# A symbolic link to the built symbol is created in the containing dir.
SYMBOLS := $(patsubst ./%/symbol.built,%.sym,$(BUILT_SYMBOLS))
# The part names (equivalent to part directory names), without suffixes.
PART_NAMES := $(patsubst %.sym,%,$(SYMBOLS))

# Things are mostly analogous to symols for footprints, but we use a slightly
# different extension fo the link since gschem or gsch2pcb or pcb or something
# requires it.  NOTE: see comments about -L above SYMBOL_SRCS variable above.
FOOTPRINT_SRCS := $(shell find -L . -name footprint.src)
BUILT_FOOTPRINTS := $(patsubst %.src,%.built,$(FOOTPRINT_SRCS))
FOOTPRINTS := $(patsubst ./%/footprint.built,%_fpt,$(BUILT_FOOTPRINTS))

# }}}2

.PHONY: symbols
symbols: $(SYMBOLS) diff_check

# NOTE: we use static pattern rules here to get better error messages for
# missing source files.

# Symbols in the current directory are links to their built versions
# in subdirs.  See above NOTE about static pattern rule use.
$(SYMBOLS): %.sym: %/symbol.built %_fpt
	(! test -e $@) || test -L $@ || false
	ln --symbolic --force $< $@

# Footprints in the current directory are links to their built versions
# in subdirs.  See above NOTE about static pattern rule use.
$(FOOTPRINTS): %_fpt: %/footprint.built
	(! test -e $@) || test -L $@ || false
	ln --symbolic --force  $< $@

# Build a symbol in its directory (according to its file type).  We start
# with the guessed value of the value parameter (which might be empty).
# See above NOTE about static pattern rule use.
%/symbol.built: GVV = \
  $(shell ./guess_value $(dir $<) 2>/tmp/GVV_err || \
            echo "guess_value failed: `cat /tmp/GVV_err`")
$(BUILT_SYMBOLS): %/symbol.built: %/symbol.src $(HELPER_SCRIPTS) %_fpt
	if grep '\[pins\]' $<; then \
          cd $(dir $<); \
          ../tragesym symbol.src symbol.partly_built && \
          ../check_pin_names.perl symbol.partly_built && \
          ../set_symbol_attribute symbol.partly_built \
            footprint $(lastword $+) >$(notdir $@) && \
          rm symbol.partly_built; \
        else \
          ./set_symbol_attribute $< footprint $(lastword $+) >$@; \
        fi
	if ( echo '$(GVV)' | grep --silent 'guess_value failed' ); then \
          echo -e "\n"'$(GVV)'"\n" && false; \
        fi
	if [ -n '$(GVV)' ]; then \
          NSTF=$$(mktemp); \
          ./set_symbol_attribute $@ value '$(GVV)' >$$NSTF; \
           cp $$NSTF $@; \
        fi
	./check_pin_names.perl $@

# Build a footprint in its directory (according to its file type).  See above
# NOTE about static pattern rule use.
$(BUILT_FOOTPRINTS): %/footprint.built: %/footprint.src Makefile
	if [ -x $< ]; then \
          cd $(dir $<); \
          perl -I.. footprint.src footprint.built; \
        else \
          cp $< $@; \
        fi

# Built symbol and footprint files and symbolic links.
PART_FILES := $(BUILT_SYMBOLS) $(BUILT_FOOTPRINTS) $(SYMBOLS) $(FOOTPRINTS)

# Stupid little helper to grab a symbol from where we happen to keep them.
.PHONY: grab_symbol
grab_symbol:
	cp $$(find ~/opt/geda -name "$(NS)*" -print | head -n 1) .

define GSCHEM2PCB_COMMANDS
  test -x check_refdes_uniqueness.perl
  ./check_refdes_uniqueness.perl $<
  # Note that this command puts output files in the same directory as input
  # files when $< has a directory part.
  gsch2pcb --use-files $(FOOTPRINT_LIB_FLAGS) $<
endef

# For part development: now "make checksym_some_part will rebuild the gschem
# symbol for the part and open gschem on it.
CHECKSYM_TARGETS := $(patsubst %,checksym_%,$(PART_NAMES))
$(CHECKSYM_TARGETS): checksym_%: %.sym
	gschem $<

# For part development: now "make checkfpt_some_part" will rebuild the part,
# recreate the associated checkfpt.pcb file, and open pcb on it.
CHECKFPT_TARGETS := $(patsubst %,checkfpt_%,$(PART_NAMES))
$(CHECKFPT_TARGETS): checkfpt_%: %/checkfpt.sch %.sym %_fpt \
                     $(HELPER_SCRIPTS) diff_check
	rm -f $(patsubst %.sch,%.pcb,$<)
	$(GSCHEM2PCB_COMMANDS)
	pcb $(patsubst %.sch,%.pcb,$<)

# Junk that gets created when building things from $(CHECKFPT_TARGETS) that
# clean should remove.
CHECKFPT_FILES := $(addsuffix /checkfpt.cmd,$(PART_NAMES)) \
                  $(addsuffix /checkfpt.net,$(PART_NAMES)) \
                  $(addsuffix /checkfpt.pcb,$(PART_NAMES)) \
                  $(addsuffix /checkfpt.pcb-,$(PART_NAMES))

# }}}1

# Publish symbols on the web {{{1

# Create a targzball containing the built symbols (and all the junk that
# went into making them).
.PHONY: symbols_targzball
ifeq ($(filter symbols_targzball,$(MAKECMDGOALS)),symbols_targzball)
  ifneq ($(origin VERSION),command line)
    $(error origin of VERSION: $(origin VERSION))
    $(error symbols_targzball target specified, but VERSION not given on \
            command line)
  endif
endif
symbols_targzball: symbols
	[ -n "$(VERSION)" ] || (echo VERSION not set 1>&2 && false)
	cd /tmp ; cp -rf $(shell pwd) .
	# It might cause users confusion to have a hidden .git directory,
	# so we do not include it in the tarball.
	DN=$(shell basename `pwd`); \
        cd /tmp ; \
          rm -rf $$DN/.git ; \
          rm -rf $$DN-$(VERSION) ; \
          mv $$DN $$DN-$(VERSION) ; \
          tar czvf $$DN-$(VERSION).tgz $$DN-$(VERSION)

# FIXME: this should run checklink script after install.
# Upload html documentation for the symbols package.
.PHONY: upload_html
ifeq ($(filter upload_html,$(MAKECMDGOALS)),upload_html)
  ifneq ($(origin WEB_SSH),command line)
    $(error upload_html target specified, but WEB_SSH not given on \
            command line)
  endif
  ifneq ($(origin WEB_ROOT),command line)
    $(error upload_html target specified, but WEB_ROOT not given on \
            command line)
  endif
endif
upload_html:
	scp *.html *.png $(WEB_SSH):$(WEB_ROOT)
	ssh $(WEB_SSH) ln -s --force home_page.html $(WEB_ROOT)/index.html

# Make a $(VERSION) symbols_targzball and upload it to $(WEB_SSH):$(WEB_ROOT).
.PHONY: upload
ifeq ($(filter upload,$(MAKECMDGOALS)),upload)
  ifneq ($(origin VERSION),command line)
    $(error upload target specified, but VERSION not given on command line)
  endif
  ifneq ($(origin WEB_SSH),command line)
    $(error uploadtarget specified, but WEB_SSH not given on command line)
  endif
  ifneq ($(origin WEB_ROOT),command line)
    $(error uploadtarget specified, but WEB_ROOT not given on command line)
  endif
endif
upload: symbols_targzball upload_html
	ssh $(WEB_SSH) test -d $(WEB_ROOT)
	ssh $(WEB_SSH) test -d $(WEB_ROOT)/releases/
	DN=$(shell basename `pwd`) && \
          scp /tmp/$$DN-$(VERSION).tgz $(WEB_SSH):$(WEB_ROOT)/releases/ && \
          ssh $(WEB_SSH) rm -f '$(WEB_ROOT)/releases/LATEST_IS_*' && \
          ssh $(WEB_SSH) ln -s --force $$DN-$(VERSION).tgz \
            $(WEB_ROOT)/releases/LATEST_IS_$$DN-$(VERSION).tgz

# }}}1

# Entire schematic and PCB stuff {{{1

# Note that footprint files can apparently be interdependent, so when we
# create a footprint.src by copying and twaking something from (for example)
# Luciana's collection, we might need to have a reference to that whole
# footprint library available.
FOOTPRINT_LIB_FLAGS = \
  -d $(HOME)/opt/geda/geda-install/share/luciana_pcb_symbols \
  -d $(shell pwd)

%.pcb: %.sch $(SYMBOLS) $(HELPER_SCRIPTS)
	$(GSCHEM2PCB_COMMANDS)

# We have an old tradition of copying the pcb file to whole_thing_routed.pcb
# after working on it, this rule tried to make sure it doesn't get nuked
# easily.
whole_thing_routed.pcb: whole_thing_routed.sch $(SYMBOLS) \
                        $(HELPER_SCRIPTS)
	@echo -n "\nWARNING: This will modify $@.  Continue (y/n)?  ";
	@read line; if [ $$line = 'y' ]; then echo Ok; else false; fi
	$(GSCHEM2PCB_COMMANDS)

# }}}1

# Simulation with ngspice {{{1

# Its probably unlikely that complete "whole_thing.sch" designs are entirely
# instrumented with ngspice model attributes, so this variable might need
# to be set to whatever .sch file we're using to drive the simulation.
# A assign-if-unassigned type assignment is used here so that an environment
# variable can be used for this setting.
SPICE_SCHEMATIC ?= full_bridge.sch

# Run a simulation in ngspice.  The sim_commands.txt should contain things
# like for example '.TRAN 0.1ms 1s'.
.PHONY: ngsim
ngsim: $(SPICE_SCHEMATIC) sim_commands.txt
	gnetlist -g spice-sdb -o spice.net $(SPICE_SCHEMATIC)
	ngspice --autorun spice.net sim_commands.txt

# }}}1

# Gerber generation {{{1

# Board makers need a whole set of files that they often like packed in a zip.
GERBER_EXTENSIONS := back.gbr \
                     backmask.gbr \
                     fab.gbr \
                     front.gbr \
                     frontmask.gbr \
                     frontpaste.gbr \
                     frontsilk.gbr \
                     plated-drill.cnc \
                     xy


GERBER_PATTERNS := $(addprefix %.,$(GERBER_EXTENSIONS))

$(GERBER_PATTERNS): %.pcb
	false # This new pattern approach needs testing, but I did simple
	false # mock-ups of the principles involved and they work.
	@echo ""
	@echo "You must run pcb $< and export the layout in gerber form"
	@echo "You must also export in bom form to create a .xy file (and"
	@echo "also a .bom file which will need tweaking to be useful)."
	@echo ""
	@false

%.gerbers.zip: $(GERBER_PATTERNS)
	echo $+
	rm -rf /tmp/gerberstage
	mkdir /tmp/gerberstage
	cp $+ /tmp/gerberstage
	(cd /tmp/gerberstage ; zip $@ $+)
	cp /tmp/gerberstage/$@ .

# This is the old fixed name way of doing things.
# GERBERFILES := $(foreach ext,$(GERBER_EXTENSIONS),whole_thing.$(ext))
#
# $(GERBERFILES): whole_thing_routed.pcb
# 	@echo ""
# 	@echo "You must run pcb $< and export the layout in gerber form"
# 	@echo "You must also export in bom form to create a .xy file (and"
# 	@echo "also a .bom file which will need tweaking to be useful)."
# 	@echo ""
# 	@false
#
# whole_thing.gerbers.zip: $(GERBERFILES)
# 	echo $(GERBERFILES)
# 	rm -rf /tmp/gerberstage
# 	mkdir /tmp/gerberstage
# 	cp $(GERBERFILES) /tmp/gerberstage
# 	(cd /tmp/gerberstage ; zip $@ $(GERBERFILES))
# 	cp /tmp/gerberstage/$@ .

# }}}1

# Cleaning {{{1

.PHONY: clean
clean:
	rm --force $(PART_FILES)
	rm --force $(CHECKFPT_FILES)
	find . -name "*~" -exec rm -f \{\} \;
	rm -f whole_thing.pcb-
	rm -f whole_thing.net
	rm -f whole_thing.cmd
	rm -f whole_thing.png
	rm -f whole_thing.ps
	rm -f *.bak
	rm -f $(GERBERFILES)

# Delete many files that were originally automatically constructed, even if
# they have since been edited further.
.PHONY: brutally_clean
brutally_clean: clean
	@echo -n "\nTHIS WILL BE BRUTAL.  Continue (y/n)?  ";
	@read line; if [ $$line = 'y' ]; then echo Ok; else false; fi
	rm -f whole_thing.pcb

# }}}1

# Verify and set file identicalness accross projects {{{1

# NOTE: the stuff in this fold is for the sanity of the developer and
# humors his particular crazy clone-and-modify development habits.  You can
# ignore it.

symbols: diff_check

# Ensure that some stuff cloned between projects stays in sync.
.PHONY: diff_check
diff_check: diff_check_makefiles diff_check_set_symbol_attribute

# Make function which expands to shell code that fails if all of the files
# listed in the space- (NOT comma-) seperated list of files given as an
# argument aren't identical.  NOTE: files that are totally missing don't cause
# this test to fail (though its easy to change that with a quick edit below).
# NOTE: somewhat weirdly we need to use '||' after the subshell '(echo... exit
# 1) to prevent the shell from somehow eating our diff output and error
# message... I suppose because '||' guarantees via short-circuit execution
# that the command before it is fully executed, and '&&' doesn't.  Then we
# need another 'exit 1' to exit the shell executing the loop, rather than
# just the subshell (because for doesn't care if commands return non-zero).
DIFFN = for fa in $(1); do \
          for fb in $(1); \
            do (! (test -e $$fa && test -e $$fb)) || diff -u $$fa $$fb || \
               (echo "Files $(1) are not all identical" 1>&2 && exit 1) || \
               exit 1; \
          done; \
        done

# Cponvenience variable.
PD := ~/projects

.PHONY: diff_check_generic--through_hole--2_wire
diff_check_generic--through_hole--2_wire:
	$(call DIFFN, \
          $(PD)/smartcord/through_hole_pcb/generic--through_hole--2_wire \
          $(PD)/temp_logger/through_hole_pcb/generic--through_hole--2_wire  \
          $(PD)/power_meter/generic--through_hole--2_wire \
          $(PD)/utility_meter/hub/hardware/generic--through_hole--2_wire)

.PHONY: diff_check_guess_value
diff_check_guess_value:
	$(call DIFFN, \
          $(PD)/smartcord/through_hole_pcb/guess_value \
          $(PD)/temp_logger/through_hole_pcb/guess_value \
          $(PD)/power_meter/guess_value \
          $(PD)/utility_meter/hub/hardware/guess_value \
          $(PD)/arduino_symbol/guess_value \
          $(PD)/beaglebone_symbol/guess_value)

.PHONY: diff_check_makefiles
diff_check_makefiles:
	$(call DIFFN, \
          $(PD)/smartcord/through_hole_pcb/Makefile.new_parts \
          $(PD)/temp_logger/through_hole_pcb/Makefile \
          $(PD)/power_meter/Makefile \
          $(PD)/utility_meter/hub/hardware/Makefile \
          $(PD)/arduino_symbol/Makefile \
          $(PD)/beaglebone_symbol/Makefile)

.PHONY: diff_check_set_symbol_attribute
diff_check_set_symbol_attribute:
	$(call DIFFN, \
          $(PD)/smartcord/through_hole_pcb/set_symbol_attribute \
          $(PD)/temp_logger/through_hole_pcb/set_symbol_attribute \
          $(PD)/power_meter/set_symbol_attribute \
          $(PD)/utility_meter/hub/hardware/set_symbol_attribute \
          $(PD)/arduino_symbol/set_symbol_attribute \
          $(PD)/beaglebone_symbol/set_symbol_attribute)

# Forcibly propagate the files that have the same names and are supposed to
# be the same between projects from the current project to the others, after
# prompting user to accept the dangerousness of this operation.  NOTE that
# this doesn't work for syncing the files that have different names, and
# it doesn't sync things when the file its trying to sync doesn't exist in
# the current directory.  Read the ignored error messages :)
.PHONY: force_sync
force_sync:
	@echo -n DANGEROUS.  ARE YOU SURE "(y/n)?" " "
	@read RESPONSE && echo $$RESPONSE | grep --silent '^[yY]$$'
	
	# This target doesn't support the smartcord dir because it doesn't
	# use the same name.
	pwd | grep --invert-match smartcord || false
	
	# We have to ignore errors because we copy file to itself as well
	# (so that this file itself can be identical between projects :)
	# It doesn't matter hopefully as the diff checks will pick up
	# problems anyway.
	
	-cp generic--through_hole--2_wire \
            $(PD)/smartcord/through_hole_pcb/generic--through_hole--2_wire
	-cp generic--through_hole--2_wire \
            $(PD)/temp_logger/through_hole_pcb/generic--through_hole--2_wire
	-cp generic--through_hole--2_wire \
            $(PD)/power_meter/generic--through_hole--2_wire
	-cp generic--through_hole--2_wire \
            $(PD)/utility_meter/hub/hardware/generic--through_hole--2_wire
	
	-cp guess_value $(PD)/smartcord/through_hole_pcb/guess_value
	-cp guess_value $(PD)/temp_logger/through_hole_pcb/guess_value
	-cp guess_value $(PD)/power_meter/guess_value
	-cp guess_value $(PD)/utility_meter/hub/hardware/guess_value
	-cp guess_value $(PD)/arduino_symbol/guess_value
	-cp guess_value $(PD)/beaglebone_symbol/guess_value
	
	-cp Makefile $(PD)/smartcord/through_hole_pcb/Makefile.new_parts
	-cp Makefile $(PD)/temp_logger/through_hole_pcb/Makefile
	-cp Makefile $(PD)/power_meter/Makefile
	-cp Makefile $(PD)/utility_meter/hub/hardware/Makefile
	-cp Makefile $(PD)/arduino_symbol/Makefile
	-cp Makefile $(PD)/beaglebone_symbol/Makefile
	
	-cp set_symbol_attribute \
            $(PD)/smartcord/through_hole_pcb/set_symbol_attribute
	-cp set_symbol_attribute \
            $(PD)/temp_logger/through_hole_pcb/set_symbol_attribute
	-cp set_symbol_attribute \
            $(PD)/power_meter/set_symbol_attribute
	-cp set_symbol_attribute \
            $(PD)/utility_meter/hub/hardware/set_symbol_attribute
	-cp set_symbol_attribute \
            $(PD)/arduino_symbol/set_symbol_attribute
	-cp set_symbol_attribute \
            $(PD)/beaglebone_symbol/set_symbol_attribute

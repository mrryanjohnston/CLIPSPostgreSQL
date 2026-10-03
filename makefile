# An ordinary user can install without asking anyone, which is why this is
# under $HOME and not /usr/local. A privileged location is named on the
# command line: "sudo make install PREFIX=/usr/local". Naming it is required
# rather than implied -- see check-install-prefix.
PREFIX        ?= $(HOME)/.local
BINDIR        := $(PREFIX)/bin
LIBDIR        := $(PREFIX)/lib
DESTINATION   := CLIPSPostgreSQL
VERSION       ?= 0.1.0

# Private, versioned location for the real binary (never on PATH)
LIBEXECDIR    := $(PREFIX)/libexec/$(DESTINATION)-$(VERSION)

# System-wide share dir for CLIPSPostgreSQL data
DATADIR       := $(PREFIX)/share/$(DESTINATION)

WRAPPER       := $(DESTINATION)-$(VERSION)

# ---------------------------------------------------------------------------
# Which CLIPS to build against.
#
#   6.4.2    the 6.4.2 release tarball from SourceForge (the default)
#   svn-6x   branches/64x of the CLIPS Subversion repository
#   svn-7x   branches/70x
#
# The two branches are pinned to a revision, so a build today and a build
# next month are the same build. Override CLIPS_SVN_REV to move one:
#
#   make CLIPS_VERSION=svn-7x
#   make CLIPS_VERSION=svn-7x CLIPS_SVN_REV=978
#   make CLIPS_VERSION=svn-7x CLIPS_SVN_REV=HEAD
#
# Each version is fetched and built under its own directory, so switching
# between them does not mean rebuilding the one you left -- and neither does
# switching PostgreSQL versions underneath one of them.
# ---------------------------------------------------------------------------

CLIPS_VERSION  ?= 6.4.2
CLIPS_VERSIONS := 6.4.2 svn-6x svn-7x

ARCHIVE     := clips_core_source_642.tar.gz
ARCHIVE_URL ?= https://sourceforge.net/projects/clipsrules/files/CLIPS/6.4.2/$(ARCHIVE)

CLIPS_SVN_ROOT   ?= https://svn.code.sf.net/p/clipsrules/code
CLIPS_SVN_6X_REV ?= 967
CLIPS_SVN_7X_REV ?= 978

ifeq ($(CLIPS_VERSION),6.4.2)
  CLIPS_TAG    := 6.4.2
  CLIPS_FETCH  := tarball "$(ARCHIVE_URL)" "$(ARCHIVE)"
  CLIPS_ORIGIN := the 6.4.2 release tarball
else ifeq ($(CLIPS_VERSION),svn-6x)
  CLIPS_SVN_URL ?= $(CLIPS_SVN_ROOT)/branches/64x/core
  CLIPS_SVN_REV ?= $(CLIPS_SVN_6X_REV)
  CLIPS_TAG     := svn-6x-r$(CLIPS_SVN_REV)
  CLIPS_FETCH   := svn "$(CLIPS_SVN_URL)" "$(CLIPS_SVN_REV)"
  CLIPS_ORIGIN  := branches/64x at r$(CLIPS_SVN_REV)
else ifeq ($(CLIPS_VERSION),svn-7x)
  CLIPS_SVN_URL ?= $(CLIPS_SVN_ROOT)/branches/70x/core
  CLIPS_SVN_REV ?= $(CLIPS_SVN_7X_REV)
  CLIPS_TAG     := svn-7x-r$(CLIPS_SVN_REV)
  CLIPS_FETCH   := svn "$(CLIPS_SVN_URL)" "$(CLIPS_SVN_REV)"
  CLIPS_ORIGIN  := branches/70x at r$(CLIPS_SVN_REV)
else
  $(error CLIPS_VERSION is '$(CLIPS_VERSION)': expected one of $(CLIPS_VERSIONS))
endif

# The tree as fetched is kept apart from the tree built in, so that throwing
# the objects away does not mean fetching the sources again -- and so that
# CI has something worth caching.
CLIPS_SRC_DIR := vendor/clips-source/$(CLIPS_TAG)
BUILD_DIR     := vendor/clips-build/$(CLIPS_TAG)
TARGET        := $(BUILD_DIR)/clips

CLIPS_SRC_STAMP := $(CLIPS_SRC_DIR)/.clips-source
BUILD_STAMP     := $(BUILD_DIR)/.clips-source

# vendor/clips follows whichever version was built last, so the paths in the
# README, in the examples and in tests/run.sh keep meaning something.
CLIPS_LINK := vendor/clips

# Which binary the tests run: the one just built, unless something else was
# named in the environment or on the command line.
CLIPS     ?=
CLIPS_BIN  = $(if $(strip $(CLIPS)),$(CLIPS),$(TARGET))

UNAME_S       := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
  CLIPS_OS       := DARWIN
  PG_SONAME      := libpq.dylib
  # The shared library and its version links, and nothing else that shares
  # the directory: the static library and the pkg-config file are not what
  # the installed binary loads.
  PG_SHARED_GLOB := libpq*.dylib
else
  CLIPS_OS       := LINUX
  PG_SONAME      := libpq.so
  PG_SHARED_GLOB := libpq.so*
endif

# ---------------------------------------------------------------------------
# PostgreSQL.
#
# By default the pinned source release is downloaded, checked against the
# SHA-256 postgresql.org publishes for it, and libpq is built from it into
# vendor/, so the library this binding calls is the one its documentation
# describes. Only libpq is built: the server is a separate target, needed
# only by the tests, and building it is minutes rather than seconds.
#
# PG_SYSTEM=1 goes back to linking whatever libpq the machine has, for a
# packager who would rather ship against the system library than a copy of it.
# ---------------------------------------------------------------------------

# The versions this binding is built and tested against. Any of them can be
# pinned; 18.6 is what a plain "make" builds.
#
#     make PG_VERSION=17.11
#     make PG_VERSION=19beta3
#
# A version that is not in the table below needs its digest passed with it:
#
#     make PG_VERSION=18.7 PG_SHA256=<the digest postgresql.org publishes>
#
PG_VERSION    ?= 18.6

PG_SHA256_14.24   := a7fa7ed3d558172355f51406097a7bd4f6b473be80f311ef7cda96bf383d8897
PG_SHA256_15.19   := e1a64a87a46b825b88c082e4518161a47aab53c45694964f8ba1df28f7859f89
PG_SHA256_16.15   := c1575341fa7bd40f5274ea465b34390f4dc64cdd0770af327005caaeb9f6b7ed
PG_SHA256_17.11   := dd27f2b3c59e73ed14aa3324901242bf69a032a6347805f274e6260322d42979
PG_SHA256_18.6    := 555610c24d53e4316da5b7d3fc25c279d96856d5e0e23ee308c328c5fa881d9f
PG_SHA256_19beta3 := ea4ad8933121930a58f23c73dc99c26a4184faca26faefa77d15ce0fba7dfe2c

PG_SHA256     ?= $(PG_SHA256_$(PG_VERSION))

PG_MIRROR     ?= https://ftp.postgresql.org/pub/source
PG_TARBALL    := postgresql-$(PG_VERSION).tar.bz2
PG_URL        ?= $(PG_MIRROR)/v$(PG_VERSION)/$(PG_TARBALL)
PG_ARCHIVE    := $(CURDIR)/vendor/$(PG_TARBALL)
PG_SRC        ?= $(CURDIR)/vendor/postgresql-$(PG_VERSION)
PG_PREFIX     ?= $(CURDIR)/vendor/pgsql-$(PG_VERSION)

# Nothing here needs the parts these would pull in, and every one of them is a
# development package the builder would otherwise have to install first.
PG_CONFIGURE_OPTS ?= --without-readline --without-zlib --without-icu \
                     --without-lz4 --without-zstd

PG_CONFIG     ?= pg_config

ifeq ($(PG_SYSTEM),1)
  # pg_config knows where its own headers and library are; pkg-config is the
  # fallback for a machine that installed libpq without it.
  PG_INCDIR ?= $(shell $(PG_CONFIG) --includedir 2>/dev/null || \
                       pkg-config --variable=includedir libpq 2>/dev/null)
  PG_LIBDIR ?= $(shell $(PG_CONFIG) --libdir 2>/dev/null || \
                       pkg-config --variable=libdir libpq 2>/dev/null)
  # The system library is already on the loader's path.
  PG_RPATH  :=
  PG_DEP    :=
else
  PG_INCDIR ?= $(PG_PREFIX)/include
  PG_LIBDIR ?= $(PG_PREFIX)/lib
  # Only the build tree, so that the binary in vendor/ and the tests run
  # against the libpq that was just built. Where the installed copy finds it
  # is the wrapper's business, which is what keeps PREFIX out of the link
  # and lets one build be installed anywhere.
  PG_RPATH  := -Wl,-rpath,$(PG_LIBDIR)
  PG_DEP    := $(PG_LIBDIR)/$(PG_SONAME)
endif

# ---------------------------------------------------------------------------
# Which PostgreSQL this is being built against, as a number.
#
# The source is what the wrappers are compiled with: a libpq older than 18
# does not have the cancel connection, the chunked-rows mode or the rest of
# what arrived in 17 and 18, and the wrappers for those are compiled out
# rather than failing to link. A vendored build knows the version because it
# pinned it; a PG_SYSTEM=1 build asks pg_config.
#
# 18.6 is 180006 and 19beta3 is 190000, which is how PostgreSQL numbers
# itself: the beta of a release is the release with no minor version yet.
# ---------------------------------------------------------------------------

ifeq ($(PG_SYSTEM),1)
  PG_LIBPQ_VERSION ?= $(shell $(PG_CONFIG) --version 2>/dev/null | \
                              awk '{print $$2}' | tr -cd '0-9.betarc')
else
  PG_LIBPQ_VERSION ?= $(PG_VERSION)
endif

# 18.6 -> "18 6"; 19beta3 -> "19"
pg_v      := $(subst ., ,$(firstword $(subst beta, ,$(subst rc, ,$(PG_LIBPQ_VERSION)))))
PG_MAJOR  := $(word 1,$(pg_v))
PG_MINOR  := $(word 2,$(pg_v))
PG_VERSION_NUM := $(shell printf '%d%04d' $(if $(PG_MAJOR),$(PG_MAJOR),0) \
                                          $(if $(PG_MINOR),$(PG_MINOR),0))

CFLAGS += -DCLIPSPG_PG_VERSION_NUM=$(PG_VERSION_NUM)

PG_LIB := $(PG_LIBDIR)/$(PG_SONAME)

# The directory the installed wrapper adds to the loader's path. A PG_SYSTEM=1
# build installs no libpq of its own, so it stays empty and the wrapper does
# nothing with it.
ifeq ($(PG_SYSTEM),1)
  WRAPPER_LIBDIR :=
else
  WRAPPER_LIBDIR := $(LIBDIR)
endif

# Only used for the messages; both are empty when the tree is unconfigured.
PG_BINDIR ?= $(PG_PREFIX)/bin

CFLAGS += -I$(PG_INCDIR)
LDLIBS := -lm -L$(PG_LIBDIR) -lpq $(PG_RPATH)

# ---------------------------------------------------------------------------
# Documentation.
#
# API.md carries the wording of the PostgreSQL documentation for the version
# being built against, taken from libpq.sgml -- the source of the libpq chapter
# of the manual. The vendored source tree has it; a PG_SYSTEM=1 build has no
# source tree, so the one file is fetched from the matching release tag.
# ---------------------------------------------------------------------------

# The reference covers every version this binding supports and says which
# functions need which, so it is generated from the newest manual of the set
# -- the pinned one -- however old the libpq being linked is. Generating it
# from an older manual would be generating a reference with entries missing.
PG_DOC_VERSION := $(PG_VERSION)

# 18.6 -> REL_18_6; 19beta3 -> REL_19_BETA3
PG_DOC_TAG := REL_$(subst .,_,$(subst rc,_RC,$(subst beta,_BETA,$(PG_DOC_VERSION))))
SGML_CACHE := $(CURDIR)/vendor/doc/libpq-$(PG_DOC_VERSION).sgml
SGML_URL   ?= https://raw.githubusercontent.com/postgres/postgres/$(PG_DOC_TAG)/doc/src/sgml/libpq.sgml

ifeq ($(PG_SYSTEM),1)
  LIBPQ_SGML ?= $(SGML_CACHE)
else
  LIBPQ_SGML ?= $(PG_SRC)/doc/src/sgml/libpq.sgml
endif

DOCS_GEN   := docs/gen-api-docs.sh
DOCS_INPUT := $(DOCS_GEN) docs/api-overrides.md docs/api-template.md \
              userfunctions.c $(LIBPQ_SGML)

# ---------------------------------------------------------------------------
# What the last build was built with.
#
# Which functions are compiled in depends on CFLAGS, and which library they
# are resolved against depends on LDLIBS, and make tracks neither: without
# this, switching PostgreSQL versions in the same tree would relink yesterday's
# object files and quietly produce a binary for the wrong version. It sits in
# the build tree, one per CLIPS version, because that is what the objects it
# describes belong to.
# ---------------------------------------------------------------------------

BUILD_FLAGS := $(BUILD_DIR)/.build-flags

VALGRIND       ?= valgrind
VALGRIND_FLAGS ?= --leak-check=full --errors-for-leak-kinds=none \
                  --num-callers=12 --error-exitcode=1

COVDIR     := $(CURDIR)/coverage
COV_CC     ?= gcc
GCOV       ?= gcov
COV_CFLAGS := -std=c99 -O0 -g --coverage

.PHONY: all clips clips-source debug deps libpq pg-server install install-bin \
        uninstall clean distclean test test-suite test-examples test-valgrind \
        coverage check-versions test-versions test-clips \
        docs docs-check \
        help check-pg-build-tools check-libpq-version check-install-prefix \
        print-pg-version \
        print-pg-version-num print-pg-libdir \
        print-clips print-clips-versions print-clips-target FORCE

all: clips

clips: $(TARGET)
	@:

deps: $(PG_DEP) $(CLIPS_SRC_STAMP)

libpq: $(PG_DEP)

$(BUILD_FLAGS): FORCE
	@mkdir -p $(@D)
	@printf '%s\n' '$(CFLAGS) $(LDLIBS)' | cmp -s - $@ 2>/dev/null || \
	    printf '%s\n' '$(CFLAGS) $(LDLIBS)' > $@

FORCE:

# ---------------------------------------------------------------------------
# Fetching and building CLIPS.
#
# scripts/fetch-clips.sh puts a pristine tree in $(CLIPS_SRC_DIR); the build
# happens in a copy of it, because userfunctions.c has to be dropped in beside
# the CLIPS sources for the CLIPS makefile to find it. The copy is made once,
# so an edit to userfunctions.c still recompiles one file rather than all of
# them.
# ---------------------------------------------------------------------------

$(CLIPS_SRC_STAMP): | scripts/fetch-clips.sh
	./scripts/fetch-clips.sh $(CLIPS_FETCH) "$(CLIPS_SRC_DIR)"

$(BUILD_STAMP): $(CLIPS_SRC_STAMP)
	mkdir -p "$(BUILD_DIR)"
	cp -R "$(CLIPS_SRC_DIR)/." "$(BUILD_DIR)/"
	touch "$@"

# vendor/clips is a symlink to the version built last. An older checkout
# unpacked the sources there directly, so a real directory in its place is the
# leftover of one and goes.
define point_clips_link
	@[ ! -e "$(CLIPS_LINK)" ] || [ -L "$(CLIPS_LINK)" ] || rm -rf "$(CLIPS_LINK)"
	@ln -sfn "clips-build/$(CLIPS_TAG)" "$(CLIPS_LINK)"
	@echo "$(CLIPS_LINK) -> clips-build/$(CLIPS_TAG)  ($(CLIPS_ORIGIN))"
endef

$(TARGET): userfunctions.c $(PG_DEP) $(BUILD_FLAGS) $(BUILD_STAMP)
	@$(MAKE) --no-print-directory check-libpq-version
	cp userfunctions.c $(BUILD_DIR)/
	$(MAKE) -C $(BUILD_DIR) LDLIBS="$(LDLIBS)" CFLAGS="$(CFLAGS)"
	$(point_clips_link)

debug: userfunctions.c $(PG_DEP) $(BUILD_FLAGS) $(BUILD_STAMP)
	@$(MAKE) --no-print-directory check-libpq-version
	cp userfunctions.c $(BUILD_DIR)/
	$(MAKE) -C $(BUILD_DIR) debug LDLIBS="$(LDLIBS)" CFLAGS="$(CFLAGS)"
	$(point_clips_link)

# Fetching the selected CLIPS without building it, for priming a cache or for
# looking at what a branch is doing.
clips-source: $(CLIPS_SRC_STAMP)
	@cat "$(CLIPS_SRC_STAMP)"

# ---------------------------------------------------------------------------
# The vendored PostgreSQL.
#
# PostgreSQL 17 stopped shipping pre-generated parser files in its releases, so
# bison, flex and perl are needed to build one -- the tools, not the libraries,
# which is why this is a check and not a configure option.
# ---------------------------------------------------------------------------

# Which functions are compiled in depends on this number, so a build that
# cannot work it out is a build that would quietly bind the wrong set.
check-libpq-version:
	@[ -n "$(PG_MAJOR)" ] || { \
	    echo "makefile: cannot tell which PostgreSQL this libpq belongs to." >&2; \
	    echo >&2; \
	    echo "  PG_SYSTEM=1 asks '$(PG_CONFIG) --version', which said nothing." >&2; \
	    echo "  Point at the right one, or say which version it is:" >&2; \
	    echo >&2; \
	    echo "      make PG_SYSTEM=1 PG_CONFIG=/usr/lib/postgresql/18/bin/pg_config" >&2; \
	    echo "      make PG_SYSTEM=1 PG_LIBPQ_VERSION=18.6" >&2; \
	    exit 1; \
	}

check-pg-build-tools:
	@missing=; \
	for t in bison flex perl; do \
	    command -v $$t >/dev/null 2>&1 || missing="$$missing $$t"; \
	done; \
	[ -z "$$missing" ] || { \
	    echo "makefile: cannot build PostgreSQL $(PG_VERSION) from source:$$missing not found." >&2; \
	    echo >&2; \
	    echo "  PostgreSQL 17 and later generate their parsers at build time." >&2; \
	    echo "  Debian/Ubuntu:  sudo apt-get install bison flex perl" >&2; \
	    echo "  Fedora/RHEL:    sudo dnf install bison flex perl" >&2; \
	    echo "  macOS:          brew install bison flex" >&2; \
	    echo >&2; \
	    echo "  Or build against the libpq already on this machine:" >&2; \
	    echo "      make PG_SYSTEM=1" >&2; \
	    exit 1; \
	}

$(PG_ARCHIVE): | scripts/fetch-postgresql.sh
	@[ -n "$(PG_SHA256)" ] || { \
	    echo "makefile: no digest is pinned for PostgreSQL $(PG_VERSION)." >&2; \
	    echo >&2; \
	    echo "  The versions with one are:" >&2; \
	    echo "      14.24  15.19  16.15  17.11  18.6  19beta3" >&2; \
	    echo >&2; \
	    echo "  For any other, pass the digest postgresql.org publishes:" >&2; \
	    echo "      make PG_VERSION=$(PG_VERSION) PG_SHA256=<digest>" >&2; \
	    echo "  It is at $(PG_URL).sha256" >&2; \
	    exit 1; \
	}
	./scripts/fetch-postgresql.sh "$(PG_URL)" "$(PG_SHA256)" "$@"

$(PG_SRC)/configure: $(PG_ARCHIVE)
	mkdir -p "$(dir $(PG_SRC))"
	tar -xf "$(PG_ARCHIVE)" -C "$(dir $(PG_SRC))"
	touch "$@"

# The tool check belongs to configure rather than being a prerequisite of it:
# a phony prerequisite would make config.status out of date on every run, and
# the tools are only needed when configure is actually about to run.
$(PG_SRC)/config.status: $(PG_SRC)/configure
	$(MAKE) check-pg-build-tools
	cd "$(PG_SRC)" && ./configure --prefix="$(PG_PREFIX)" $(PG_CONFIGURE_OPTS)

# libpq, its two supporting static libraries and the headers that go with them.
# src/include install brings postgres_ext.h and pg_config_ext.h along, which
# libpq-fe.h includes; pg_config is installed because a PG_SYSTEM=1 build of
# this same tree is how someone would point at it later.
#
# A vendor/pgsql-<version> that is already populated -- built here earlier,
# restored from a cache, or copied from an installation -- is used as it
# stands: no tarball is fetched, nothing is configured, and nothing is
# compiled for it. Hence the two rules rather than one; a prerequisite that
# is missing gets built even when the target it belongs to is not, so the
# source tree has to be out of the picture entirely rather than merely
# order-only.
ifeq ($(wildcard $(PG_LIB)),)

$(PG_LIB): $(PG_SRC)/config.status
	# libpq compiles against headers PostgreSQL generates rather than ships
	# -- utils/errcodes.h among them -- and a build of the whole tree would
	# have made them on its way past. This builds libpq alone, so it asks
	# for them itself.
	$(MAKE) -C "$(PG_SRC)/src/backend" generated-headers
	$(MAKE) -C "$(PG_SRC)/src/interfaces/libpq"
	# PostgreSQL's install makes the version symlinks with a plain ln -s,
	# which fails rather than replaces if one is already there -- so a build
	# interrupted part way through its install would leave a prefix that
	# could never be rebuilt. This is the one artifact that gets in its own
	# way; everything else is installed over cleanly.
	rm -f $(PG_LIBDIR)/libpq.so* $(PG_LIBDIR)/libpq*.dylib
	$(MAKE) -C "$(PG_SRC)/src/interfaces/libpq" install
	$(MAKE) -C "$(PG_SRC)/src/include" install
	$(MAKE) -C "$(PG_SRC)/src/bin/pg_config" install
	touch "$@"

else

$(PG_LIB): ;

endif

# The server, for the tests. Everything else here is happy without it.
pg-server: $(PG_SRC)/config.status
	$(MAKE) -C "$(PG_SRC)"
	# As in the libpq rule above: the install remakes the library symlinks
	# with a plain ln -s, and this prefix usually has them already.
	rm -f $(PG_LIBDIR)/libpq.so* $(PG_LIBDIR)/libpq*.dylib
	$(MAKE) -C "$(PG_SRC)" install
	@echo
	@echo "PostgreSQL $(PG_VERSION) installed in $(PG_PREFIX)"
	@echo "'make test' will start a throwaway cluster with it."

print-pg-version:
	@echo '$(PG_VERSION)'

print-pg-version-num:
	@echo '$(PG_VERSION_NUM)'

print-pg-libdir:
	@echo '$(PG_LIBDIR)'

print-clips-versions:
	@echo '$(CLIPS_VERSIONS)'

print-clips-target:
	@echo '$(TARGET)'

print-clips:
	@echo 'CLIPS_VERSION $(CLIPS_VERSION)'
	@echo 'origin        $(CLIPS_ORIGIN)'
	@echo 'source        $(CLIPS_SRC_DIR)'
	@echo 'build         $(BUILD_DIR)'
	@echo 'binary        $(TARGET)'
	@[ -f "$(CLIPS_SRC_STAMP)" ] && printf 'fetched       ' && cat "$(CLIPS_SRC_STAMP)" || true

install: check-install-prefix clips install-bin
	@echo
	@echo "installed $(DESTINATION) $(VERSION) in $(PREFIX)"
	@echo "  $(BINDIR)/$(DESTINATION)"
ifneq ($(PG_SYSTEM),1)
	@echo "  $(LIBDIR)/$(PG_SONAME) (the libpq it was built against)"
endif
	@case ":$$PATH:" in \
	    *":$(BINDIR):"*) ;; \
	    *) echo; echo "note: $(BINDIR) is not on your PATH." ;; \
	esac

# ---------------------------------------------------------------------------
# sudo resets HOME to root's, so a "sudo make install" that did not name a
# PREFIX would quietly install into /root/.local -- everything reported as
# succeeding and nothing where the user is going to look for it. Naming the
# location is the whole point of using sudo here, so not naming it is the
# error.
# ---------------------------------------------------------------------------

PREFIX_NAMED := $(if $(filter command line environment,$(origin PREFIX)),yes,no)

check-install-prefix:
	@if [ "$$(id -u)" -eq 0 ] && [ "$(PREFIX_NAMED)" = no ]; then \
	    echo "makefile: running as root with no PREFIX named." >&2; \
	    echo >&2; \
	    echo "  sudo resets HOME, so this would install into $(PREFIX)," >&2; \
	    echo "  which is almost certainly not what you meant. Name the" >&2; \
	    echo "  location instead:" >&2; \
	    echo >&2; \
	    echo "      sudo make install PREFIX=/usr/local" >&2; \
	    echo >&2; \
	    echo "  Or install as yourself, which needs no sudo at all:" >&2; \
	    echo >&2; \
	    echo "      make install" >&2; \
	    exit 1; \
	fi

install-bin:
	install -d "$(LIBEXECDIR)" "$(BINDIR)"
	install -m755 "$(TARGET)" "$(LIBEXECDIR)/clips"
	sed -e 's|@REAL@|$(LIBEXECDIR)/clips|g' \
	    -e 's|@VERSION@|$(VERSION)|g' \
	    -e 's|@LIBPQ_DIR@|$(WRAPPER_LIBDIR)|g' \
	    CLIPSPostgreSQL.in > "$(BINDIR)/$(WRAPPER)"
	chmod 755 "$(BINDIR)/$(WRAPPER)"
	ln -sfn "$(WRAPPER)" "$(BINDIR)/$(DESTINATION)"
ifneq ($(PG_SYSTEM),1)
	install -d "$(LIBDIR)"
	cp -P $(PG_LIBDIR)/$(PG_SHARED_GLOB) "$(LIBDIR)/"
endif

uninstall:
	rm -f "$(BINDIR)/$(WRAPPER)" "$(BINDIR)/$(DESTINATION)"
	rm -rf "$(LIBEXECDIR)"
ifneq ($(PG_SYSTEM),1)
	rm -f $(LIBDIR)/$(PG_SHARED_GLOB)
endif
	rmdir "$(DATADIR)" 2>/dev/null || true

# The trees under vendor/clips-source are left alone: they are the slow half
# to get back, and nothing a build writes goes there. So are the PostgreSQL
# sources and the libpq built from them, which distclean is for.
clean:
	-rm -rf vendor/clips-build "$(CLIPS_LINK)"
	-rm -rf "$(COVDIR)" tests/tmp

distclean:
	rm -rf vendor
	rm -f "$(ARCHIVE)"

# ---------------------------------------------------------------------------
# Tests. tests/run.sh runs the suite against a throwaway cluster it starts
# itself, from the vendored server if 'make pg-server' has built one and from
# PATH otherwise. With neither, the suites that need a server are skipped and
# the rest still run; CLIPSPG_DSN=<conninfo> points the whole suite at a
# server that is already running.
#
# "test" runs the examples too, each against the same server and checked
# against the .expected file beside it, because an example nobody runs is a
# claim nobody checks.
# ---------------------------------------------------------------------------

test: all
	PG_BINDIR="$(PG_BINDIR)" CLIPS="$(CLIPS_BIN)" ./tests/run.sh

test-suite: all
	PG_BINDIR="$(PG_BINDIR)" CLIPS="$(CLIPS_BIN)" ./tests/run.sh suite

# Does the source still compile against every supported libpq, and bind what
# it should? Two headers per version, fetched once into vendor/headers, and
# the CLIPS headers of whichever version is selected -- so a branch that
# renames something under this file is a compile error here first.
check-versions: $(CLIPS_SRC_STAMP)
	CLIPS_INCLUDE="$(CLIPS_SRC_DIR)" ./scripts/check-versions.sh

# The whole suite against every supported major, one after another: each
# version's libpq is built (or reused if it is already in vendor/), and all of
# them are run against one server, since what varies here is the client.
test-versions:
	./scripts/test-versions.sh

# The whole suite against every CLIPS this binds to, one after another. What
# varies here is the interpreter underneath, so one libpq serves all of them.
#
# CLIPS= empties whatever was inherited: each version has to be tested against
# its own binary for this to mean anything.
test-clips:
	@for v in $(CLIPS_VERSIONS); do \
	    echo; \
	    echo "=== CLIPS_VERSION=$$v ==="; \
	    $(MAKE) --no-print-directory CLIPS= CLIPS_VERSION="$$v" test || exit 1; \
	done

test-examples: all
	PG_BINDIR="$(PG_BINDIR)" CLIPS="$(CLIPS_BIN)" ./tests/run.sh examples

test-valgrind: all
	@command -v $(VALGRIND) >/dev/null 2>&1 || { \
	    echo "$(VALGRIND) not found: install valgrind, or point at it with VALGRIND=/path/to/valgrind" >&2; \
	    exit 1; \
	}
	PG_BINDIR="$(PG_BINDIR)" \
	CLIPS="$(VALGRIND) $(VALGRIND_FLAGS) $(CLIPS_BIN)" ./tests/run.sh suite

# ---------------------------------------------------------------------------
# API.md, generated from the PostgreSQL documentation for the libpq being
# built against.
# ---------------------------------------------------------------------------

docs: API.md

API.md: $(DOCS_INPUT)
	LIBPQ_SGML="$(LIBPQ_SGML)" PG_VERSION="$(PG_DOC_VERSION)" $(DOCS_GEN) "$@"

$(SGML_CACHE):
	mkdir -p "$(dir $@)"
	wget -O "$@" "$(SGML_URL)"

$(PG_SRC)/doc/src/sgml/libpq.sgml: $(PG_SRC)/configure
	@:

docs-check: $(DOCS_INPUT)
	@LIBPQ_SGML="$(LIBPQ_SGML)" PG_VERSION="$(PG_DOC_VERSION)" \
	    $(DOCS_GEN) "$(CURDIR)/API.md.check" >/dev/null
	@if cmp -s API.md API.md.check; then \
	    rm -f API.md.check; echo "API.md is up to date"; \
	else \
	    diff -u API.md API.md.check | head -40; rm -f API.md.check; \
	    echo "API.md is stale: run 'make docs'" >&2; exit 1; \
	fi

# ---------------------------------------------------------------------------
# Line coverage of the wrappers, and the list of the ones no test entered.
# ---------------------------------------------------------------------------
coverage: clips
	mkdir -p "$(COVDIR)"
	cp userfunctions.c "$(COVDIR)/"
	$(COV_CC) -c -D$(CLIPS_OS) $(COV_CFLAGS) $(CFLAGS) -I"$(BUILD_DIR)" \
	    -o "$(COVDIR)/userfunctions.o" "$(COVDIR)/userfunctions.c"
	cp "$(BUILD_DIR)/libclips.a" "$(COVDIR)/libclips.a"
	ar d "$(COVDIR)/libclips.a" userfunctions.o
	ar r "$(COVDIR)/libclips.a" "$(COVDIR)/userfunctions.o"
	$(COV_CC) -o "$(COVDIR)/clips" "$(BUILD_DIR)/main.o" \
	    -L"$(COVDIR)" -lclips --coverage $(LDLIBS)
	rm -f "$(COVDIR)/userfunctions.gcda"
	: > "$(COVDIR)/never-entered.txt"
	PG_BINDIR="$(PG_BINDIR)" CLIPS="$(COVDIR)/clips" ./tests/run.sh || true
	cd "$(COVDIR)" && $(GCOV) -b -f userfunctions.c > by-function.txt
	@echo
	@sed -n "/^File .*userfunctions\.c/,/^Creating/p" "$(COVDIR)/by-function.txt" | grep -v '^Creating'
	@grep -v '^[[:space:]]*//' userfunctions.c | grep 'AddUDF(' \
	    | grep -oE '"Pq[A-Za-z0-9_]*Function"' | tr -d '"' | sort -u \
	    > "$(COVDIR)/registered-udfs.txt"
	@awk -v out="$(COVDIR)/never-entered.txt" \
	     'NR==FNR { udf[$$0]=1; next } \
	      /^Function / { fn=substr($$2,2,length($$2)-2); want=(fn in udf); next } \
	      /^Lines executed:/ && want { \
	        want=0; p=$$2; sub(/^executed:/,"",p); sub(/%$$/,"",p); \
	        n=$$4+0; fns++; tot+=n; cov+=p*n/100; \
	        if (p+0==0) { zero++; print fn > out } } \
	      END { if (tot) printf "\nUDF handlers only: %d registered, %d lines, %.1f%% executed (%d never entered)\n", fns, tot, 100*cov/tot, zero }' \
	    "$(COVDIR)/registered-udfs.txt" "$(COVDIR)/by-function.txt"
	@echo
	@echo "per-function detail: $(COVDIR)/by-function.txt"
	@echo "annotated source:    $(COVDIR)/userfunctions.c.gcov"
	@echo "never entered:       $(COVDIR)/never-entered.txt"

help:
	@printf 'CLIPSPostgreSQL targets:\n\n'
	@printf '  %-16s %s\n' \
	    all             'build the binary against one CLIPS (the default)' \
	    debug           'the same build with debugging symbols' \
	    libpq           'fetch, verify and build the pinned libpq only' \
	    clips-source    'fetch the selected CLIPS without building it' \
	    pg-server       'also build the PostgreSQL server, for the tests' \
	    test            'the whole suite and the examples: tests/run.sh' \
	    test-suite      'only the in-process suite, tests/test.bat' \
	    test-examples   'only the examples, checked against examples/*.expected' \
	    test-valgrind   'the in-process suite under valgrind' \
	    check-versions  'compile against every supported PostgreSQL' \
	    test-versions   'run the whole suite against every supported major' \
	    test-clips      'run the whole suite against all three CLIPS versions' \
	    coverage        'line coverage of userfunctions.c' \
	    docs            'regenerate API.md from the PostgreSQL documentation' \
	    docs-check      'fail if API.md is not what docs would write' \
	    install         'install the binary and its wrapper under PREFIX' \
	    uninstall       'remove what install put there' \
	    clean           'remove the build trees, coverage and test scratch' \
	    distclean       'also remove the fetched CLIPS and PostgreSQL sources'
	@printf '\nPostgreSQL is pinned, downloaded and checked against the SHA-256\n'
	@printf 'postgresql.org publishes for it. This build uses %s.\n' '$(PG_VERSION)'
	@printf '\nSupported: 14.24  15.19  16.15  17.11  18.6  19beta3\n'
	@printf 'The functions PostgreSQL 16, 17 and 18 added are compiled in only\n'
	@printf 'when the libpq being built against has them; API.md says which\n'
	@printf 'ones those are.\n'
	@printf '\n  PG_SYSTEM=1         link the libpq this machine has instead\n'
	@printf '  PG_CONFIG=<path>    which pg_config PG_SYSTEM=1 asks\n'
	@printf '  PG_INCDIR=, PG_LIBDIR=  point at a libpq directly\n'
	@printf '  PG_VERSION=         pin a different release (also set PG_SHA256)\n'
	@printf '  PG_CONFIGURE_OPTS=  configure options for the vendored build\n'
	@printf '\nCLIPS is built from one of three sources, selected with\n'
	@printf 'CLIPS_VERSION. This build uses %s: %s.\n' \
	    '$(CLIPS_VERSION)' '$(CLIPS_ORIGIN)'
	@printf '\n  CLIPS_VERSION=6.4.2   the release tarball from SourceForge\n'
	@printf '  CLIPS_VERSION=svn-6x  branches/64x, pinned at r%s\n' '$(CLIPS_SVN_6X_REV)'
	@printf '  CLIPS_VERSION=svn-7x  branches/70x, pinned at r%s\n' '$(CLIPS_SVN_7X_REV)'
	@printf '  CLIPS_SVN_REV=        build a branch at another revision,\n'
	@printf '                        or at HEAD (needs svn installed)\n'
	@printf '  CLIPS_SVN_URL=        take the branch from somewhere else\n'
	@printf '\nEach version is fetched and built under its own directory, and\n'
	@printf 'vendor/clips points at the one built last. "make print-clips"\n'
	@printf 'says which that is.\n'
	@printf '\ninstall goes to %s and needs no privileges.\n' '$(PREFIX)'
	@printf 'For a system-wide location, name it:\n'
	@printf '\n      sudo make install PREFIX=/usr/local\n'
	@printf '\nOther variables: PREFIX, VERSION, CLIPS (which binary the tests\n'
	@printf 'run), CLIPSPG_DSN (a server the tests should use instead of\n'
	@printf 'starting one), VALGRIND, COV_CC, GCOV.\n'

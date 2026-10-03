# CLIPSPostgreSQL

A PostgreSQL library for CLIPS.

```clips
(bind ?conn (pq-connectdb "dbname=widgets"))

(deftemplate widget (slot id) (slot name) (slot weight))

(bind ?res (pq-exec-params ?conn
             "SELECT id, name, weight FROM widgets WHERE weight > $1"
             (create$ 2.5)))

(pq-result-to-facts ?res widget)

(pq-clear ?res)
(pq-finish ?conn)
```

For details on how to use, see [API.md](API.md)
which is generated from the PostgreSQL documentation.

## Pre-requisites

`curl` or `wget`, `tar`, a C compiler, and -- for the vendored PostgreSQL
build -- `bison`, `flex` and `perl`:

```
sudo apt-get install bison flex perl      # Debian, Ubuntu
sudo dnf install bison flex perl          # Fedora, RHEL
brew install bison flex                   # macOS
```

`subversion` as well, but only to build against a CLIPS branch rather than
the 6.4.2 release -- see
[Other CLIPS versions](#other-clips-versions).

See
[Building against a system libpq](#building-against-a-system-libpq).
for building against `libpq` already installed on your system.

## Building

```
make
```

That downloads the pinned PostgreSQL source release, checks it against the
SHA-256 postgresql.org publishes for it, builds libpq from it into `vendor/`,
downloads CLIPS 6.4.2, and builds a binary with the `pq-*` functions in it.

Only libpq is built, not the server.

To fetch and build the dependency without building CLIPS:

```
make libpq
```

Other `make` variables:

| Variable | Default | Meaning |
| --- | --- | --- |
| `PG_VERSION` | `18.6` | PostgreSQL release to download and build |
| `PG_SHA256` | the digest of that release | Checked before anything is unpacked |
| `PG_CONFIGURE_OPTS` | `--without-readline --without-zlib --without-icu --without-lz4 --without-zstd` | Passed to PostgreSQL's `configure` |
| `PG_PREFIX` | `vendor/pgsql-$(PG_VERSION)` | Where the built libpq is installed |
| `CLIPS_VERSION` | `6.4.2` | Which CLIPS to build against: `6.4.2`, `svn-6x` or `svn-7x` |
| `CLIPS_SVN_REV` | the pinned revision | Build a branch at another revision, or at `HEAD` |
| `PREFIX` | `$(HOME)/.local` | Install root for `make install` |
| `VERSION` | `0.1.0` | Version of this library, used in the installed names |

`make help` lists the targets.

### Other CLIPS versions

The wrappers build against the CLIPS 6.4.2 release and against both of the
branches under development:

```
make                          # 6.4.2, the release tarball (the default)
make CLIPS_VERSION=svn-6x     # branches/64x, the 6.4 maintenance branch
make CLIPS_VERSION=svn-7x     # branches/70x, which adds deftable and goals
```

To build a branch at some other revision:

```
make CLIPS_VERSION=svn-7x CLIPS_SVN_REV=980
make CLIPS_VERSION=svn-7x CLIPS_SVN_REV=HEAD
```

The branches come from Subversion, so those need `svn` installed
(`sudo apt install subversion`, `brew install subversion`); the default
build does not.

Each version is fetched into `vendor/clips-source/<tag>` and built in
`vendor/clips-build/<tag>`, so switching between them -- or switching
PostgreSQL versions underneath one of them -- does not mean rebuilding the
one you left. `make clips-source` fetches the selected version without
building anything.

```
make test-clips          # the whole suite against all three, one after another
```

### Other PostgreSQL versions

```
make PG_VERSION=17.11
make PG_VERSION=19beta3
```

These are the versions the makefile pins a digest for, and the ones the
library is tested against:

| | | | | | |
| --- | --- | --- | --- | --- | --- |
| 14.24 | 15.19 | 16.15 | 17.11 | 18.6 | 19beta3 |

Building a version of PostgreSQL that is not in the table means
passing the digest postgresql.org publishes for it:

```
make PG_VERSION=17.10 PG_SHA256=<digest from postgresql.org>
```

CLIPSPostgreSQL lets you check the version of Postgres you it's built against:

```clips
(if (>= (pq-built-version) 170000)
 then (bind ?cancel (pq-cancel-create ?conn))
 else ...)
```

- `pq-built-version` is the libpq the wrappers were compiled against, which is
  what decides what exists.
- `pq-lib-version` is the library loaded right now which might be different.
  A binding compiled against 17 runs against an 18 library
  and still has only the 17 functions in it.

Two targets cover the range:

```
make check-versions      # compiles against every supported release
make test-versions       # runs the whole suite against every supported major
```

`check-versions` fetches two headers per version, compiles against each, and
reports what each binds -- seconds, and it links nothing. `test-versions`
builds each version's libpq and runs the suite and
the examples against it.

It ends with a summary:

```
14.24      built=140024   Tests run: 327  Failures: 0  PASSED
15.19      built=150019   Tests run: 328  Failures: 0  PASSED
16.15      built=160015   Tests run: 330  Failures: 0  PASSED
17.11      built=170011   Tests run: 375  Failures: 0  PASSED
18.6       built=180006   Tests run: 379  Failures: 0  PASSED
19beta3    built=190000   Tests run: 379  Failures: 0  PASSED
```

`make clean` removes the build trees but keeps the sources that were
downloaded; `make distclean` removes those too, including the libraries
downloaded for the full test suite run.

### Building against a system libpq

```
make PG_SYSTEM=1
```

This links whatever libpq the machine has, asking `pg_config` -- or
`pkg-config libpq` if there is no `pg_config` -- where its headers and library
are. It has to be a libpq from PostgreSQL 14 or later -- 14 is where pipeline mode
arrives, and the source says so at compile time rather than failing to link at
the end of the build.

If `pg_config` is not the one you want, or is not there at all:

```
make PG_SYSTEM=1 PG_LIBPQ_VERSION=16.15
make PG_SYSTEM=1 PG_CONFIG=/usr/lib/postgresql/18/bin/pg_config
make PG_SYSTEM=1 PG_INCDIR=/usr/include/postgresql PG_LIBDIR=/usr/lib/x86_64-linux-gnu
```

`API.md` is generated from the newest supported release's manual whatever you
build against, since it documents every version.

## Installing

```
make install
```

It does not need `sudo`: it installs into `~/.local`, and tells you if
`~/.local/bin` is not on your `PATH`. If you use `sudo make install`,
it will warn you to specify a `PREFIX` like so:

```
sudo make install PREFIX=/usr/local
```

What lands there:

| Path | |
| --- | --- |
| `$(PREFIX)/bin/CLIPSPostgreSQL` | a symlink to the versioned wrapper, which is what to run |
| `$(PREFIX)/bin/CLIPSPostgreSQL-$(VERSION)` | the wrapper: answers `--version`, points the loader at the libpq below, and execs the binary |
| `$(PREFIX)/libexec/CLIPSPostgreSQL-$(VERSION)/clips` | the binary itself, kept off `PATH` |
| `$(PREFIX)/lib/libpq.so*` | the libpq the binary was built against, for a vendored build only |

To remove the files created by `make install`;

```
make uninstall
# or
sudo make uninstall PREFIX=/usr/local
```

## Tests

```
make test
```

The suite needs a server, and `tests/run.sh` finds one:

1. `CLIPSPG_DSN=<conninfo>` names a server that is already running, which is
   used as it is and left alone. **Its database is written to** -- point it at
   a scratch database, not one that matters.
2. Otherwise a PostgreSQL installation is looked for: first where `make`
   points, then on the PATH, then in the usual packaged locations. A cluster
   is created under `tests/tmp`, started on a Unix socket of its own, and
   removed at the end.
3. With neither, the suites that need a server are skipped and the rest still
   run -- the argument guards, the connection-string parsing, and everything
   readable from a connection that could not be made.

The vendored PostgreSQL is a libpq, not a server, so a self-contained run
needs one built:

```
make pg-server        # minutes, once
make test
```

`make test` also runs every example in [examples/](examples/) against the same
server, and checks each one against the `.expected` file beside it -- the
lines it has to print, a clean exit, and nothing on `STDERR`. An example that
stops working fails the suite. `make test-examples` runs only those.

`make test-valgrind` runs the in-process suite under valgrind, where a wrapper
that frees the wrong thing or reads freed memory stops being a pass. `make
coverage` reports line coverage of `userfunctions.c` and names the wrappers no
test entered.

## Documentation

[API.md](API.md) is generated:

```
make docs
```

The prose for every function comes from `libpq.sgml`, the source of the libpq
chapter of the PostgreSQL manual, for the newest release the library supports
-- the one whose manual describes every function it can bind.

What the CLIPS side contributes rides along with the registration in
`userfunctions.c`: the group each function belongs to, its argument names, and
what it answers with. `docs/api-overrides.md` replaces the manual's wording
where the CLIPS calling convention differs from C, which is also where the
functions with no C counterpart are described.

```
make docs-check
```

fails if `API.md` is not what `make docs` would write, and the same check
refuses to generate a reference in which a registered function has no
documentation, or a documented libpq function is neither bound nor listed
under **Not exposed** with a reason.

## What it looks like

Handles -- connections, results, cancel connections -- are CLIPS external
addresses, and closing one empties it, so a second close is refused rather
than being a second free:

```clips
(pq-finish ?conn)
(pq-status ?conn)     ; FALSE, and a message on STDERR
```

To check why a call failed to the server:

```clips
(bind ?res (pq-exec ?conn "SELEC 1"))
(pq-result-status ?res)                          ; PGRES_FATAL_ERROR
(pq-result-error-field ?res PG_DIAG_SQLSTATE)    ; "42601"
(pq-clear ?res)
```

Every function accepts either the symbols representing constants (`CONNECTION_OK`,
`PGRES_TUPLES_OK`, `PQTRANS_INTRANS`, etc) or the integers they represent.

Values go out as parameters rather than as text in the command:

```clips
(pq-exec-params ?conn "INSERT INTO parts VALUES ($1, $2)" (create$ 7 nil))
```

CLIPS `nil` is SQL NULL, in a parameter and in a row read back.

A whole row can be turned into a multifield, fact, or instance with
`pq-row-to-multifield`, `pq-row-to-fact` and `pq-row-to-instance` respectively,
and a whole result with `pq-result-to-multifields`, `pq-result-to-facts` and
`pq-result-to-instances`. The `pq-exec-to-*` forms of the same three run the
query as well, and can infer the deftemplate or defclass from the table the
columns come from:

```clips
(deftemplate orders (slot id) (slot product) (slot amount))

(pq-exec-to-facts ?conn "SELECT id, product, amount FROM orders")
```

See [examples/](examples/).

## Licence

MIT. See [LICENSE](LICENSE).

CLIPS and PostgreSQL are downloaded by the build and are under their own
licences.

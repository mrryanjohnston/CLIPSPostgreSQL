#!/bin/sh
# Runs the whole test suite against every PostgreSQL major this library
# supports, one after another.
#
# What varies between versions is the client library: the wrappers are
# compiled against each libpq in turn, binding whatever that version has.
# What they talk to does not have to vary with them -- a libpq 14 client
# speaks to an 18 server perfectly well -- so one server is found once and
# every version is run against it. That keeps this minutes rather than an
# hour: each version is a libpq build, not a PostgreSQL build.
#
# The vendored libpq for a version is built if it is not there already, which
# needs bison, flex and perl (see "make help"). A version whose
# vendor/pgsql-<version> is already populated -- built earlier, or an
# installation copied into place -- is used as it stands.
#
# Usage:
#   scripts/test-versions.sh                     every supported major
#   scripts/test-versions.sh 17.11 18.6          only these
#   PG_BINDIR=/usr/lib/postgresql/16/bin scripts/test-versions.sh
set -u

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root" || exit 1

# One release per supported major: the same list the makefile pins digests
# for. Which functions a build binds is decided by the major, so one release
# of each is the whole matrix.
default_versions='14.24 15.19 16.15 17.11 18.6 19beta3'
versions=${*:-$default_versions}

default_version=$(make -s print-pg-version)

# Which CLIPS this is running against does not vary here -- what varies is
# libpq -- so the binary is at the same path for every leg.
clips_bin=$(make -s print-clips-target)

# ----------------------------------------------------------------------
# A server to run them all against
#
# Every version needs one, and a run that quietly finds none would skip the
# suites that matter and still say it passed.
# ----------------------------------------------------------------------
find_server() {
    [ -n "${PG_BINDIR:-}" ] && [ -x "${PG_BINDIR}/pg_ctl" ] && { echo "$PG_BINDIR"; return; }
    for d in "$root/vendor/pgsql-$default_version/bin" \
             $(command -v pg_ctl >/dev/null 2>&1 && dirname "$(command -v pg_ctl)") \
             /usr/lib/postgresql/*/bin /usr/pgsql-*/bin \
             /opt/homebrew/opt/postgresql*/bin /usr/local/pgsql/bin; do
        [ -x "$d/pg_ctl" ] && [ -x "$d/initdb" ] && { echo "$d"; return; }
    done
}

server_bin=$(find_server)
if [ -z "$server_bin" ]; then
    echo "test-versions: no PostgreSQL server found to run the suites against." >&2
    echo >&2
    echo "  Every version needs one, and it does not have to match: a client" >&2
    echo "  of any supported version talks to a server of any of them." >&2
    echo >&2
    echo "      make pg-server                       build the vendored one" >&2
    echo "      sudo apt-get install postgresql-16   or use a packaged one" >&2
    echo "      PG_BINDIR=/path/to/bin $0" >&2
    exit 1
fi

echo "server:  $server_bin"
echo "testing: $versions"
echo

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

failures=0
results=$tmp/results

outer_library_path=${LD_LIBRARY_PATH:-}

for version in $versions; do
    LD_LIBRARY_PATH=$outer_library_path
    export LD_LIBRARY_PATH
    printf '=== PostgreSQL %s ' "$version"
    printf '%.0s=' $(seq 1 $((60 - ${#version}))) 2>/dev/null
    echo

    if ! make PG_VERSION="$version" > "$tmp/build.log" 2>&1; then
        echo "  BUILD FAILED"
        tail -15 "$tmp/build.log" | sed 's/^/    /'
        printf '%-10s build failed\n' "$version" >> "$results"
        failures=$((failures + 1))
        continue
    fi

    # The binary finds its own libpq through the rpath the build gave it.
    # A library's own dependencies are not looked for there, though -- a
    # runpath is not inherited -- so a vendored prefix that came from an
    # installation, and brought that installation's dependencies with it,
    # needs this. It names the same directory the rpath does.
    LD_LIBRARY_PATH="$root/vendor/pgsql-$version/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export LD_LIBRARY_PATH

    # Through a batch file rather than a pipe: CLIPS reading its commands
    # from a pipe does not stop at the end of one.
    printf '(printout t (pq-built-version) crlf)\n(exit)\n' > "$tmp/version.bat"
    built=$("$clips_bin" -f2 "$tmp/version.bat" 2>/dev/null | tr -dc '0-9')

    if make PG_VERSION="$version" PG_BINDIR="$server_bin" test > "$tmp/test.log" 2>&1; then
        outcome=PASSED
    else
        outcome=FAILED
        failures=$((failures + 1))
    fi

    # A run that found no server skips most of itself and still exits zero,
    # which would make this whole script meaningless.
    if grep -q "^no server:" "$tmp/test.log"; then
        outcome="FAILED (no server)"
        failures=$((failures + 1))
    fi

    counts=$(grep -E "^Tests run:" "$tmp/test.log" | tail -1)
    examples=$(grep -c "^examples \.*$" "$tmp/test.log")

    echo "  built for: $built"
    echo "  $counts"
    [ "$outcome" = PASSED ] || sed -n '/FAILURE\|FAILED/,+4p' "$tmp/test.log" | head -20 | sed 's/^/    /'
    echo "  $outcome"
    echo

    printf '%-10s built=%-8s %-28s %s\n' \
        "$version" "$built" "$counts" "$outcome" >> "$results"
done

# Leave the tree the way it was found, built for the version a plain "make"
# builds, rather than for whichever came last here.
echo "restoring the default build ($default_version)"
make PG_VERSION="$default_version" >/dev/null 2>&1

echo
echo "================================================================"
cat "$results"
echo "================================================================"

if [ "$failures" -gt 0 ]; then
    echo "$failures version(s) failed"
    exit 1
fi

echo "every version passed"

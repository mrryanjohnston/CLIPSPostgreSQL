#!/bin/sh
# Runs the CLIPSPostgreSQL test suite.
#
#   tests/test.bat        one process, every suite batched into it, one
#                         assertion counter. This is the suite proper.
#
#   examples/*.bat        every example, run against the same server and
#                         checked against the .expected file beside it. The
#                         examples are documentation, and this is what keeps
#                         them from quietly becoming fiction.
#
# Most of what this library wraps needs a server to talk to, and this script
# is what finds one. In order of preference:
#
#   CLIPSPG_DSN=<conninfo>   a server that is already running, used as-is and
#                            left alone. Its database is written to.
#   a PostgreSQL installation, from PG_BINDIR (which the makefile points at
#                            the vendored build), from PATH, or from the
#                            usual packaged locations. A cluster is created
#                            under tests/tmp, started on a Unix socket of its
#                            own, and removed at the end.
#   neither                  the suites that need a server are skipped and
#                            the rest still run, so the argument guards and
#                            the parsing functions are still covered.
#
# Usage:
#   ./tests/run.sh                     the whole thing
#   ./tests/run.sh suite               only tests/test.bat
#   ./tests/run.sh examples            only the examples
#   CLIPS=/path/to/clips ./tests/run.sh
set -u

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root" || exit 1

CLIPS=${CLIPS:-./vendor/clips/clips}
what=${1:-all}

# CLIPS may carry a prefix, as it does for the valgrind target, so the
# program being run is the last word of it that looks like a path.
clips_bin=
for word in $CLIPS; do
    case "$word" in */*) clips_bin=$word ;; esac
done
: "${clips_bin:=$CLIPS}"

if [ ! -x "$clips_bin" ]; then
    echo "no CLIPSPostgreSQL binary at $clips_bin -- run 'make' first," >&2
    echo "or point at one with CLIPS=/path/to/clips" >&2
    exit 1
fi

tmp=$root/tests/tmp
data=$tmp/pgdata
sock=$tmp/sock
serverlog=$tmp/server.log

# Written by the suites and by this script; removed at both ends so a run that
# died half way cannot seed the next one.
rm -rf "$tmp"
mkdir -p "$tmp"

started_cluster=no

cleanup() {
    if [ "$started_cluster" = yes ]; then
        "$pg_ctl" -D "$data" -m immediate -w stop >/dev/null 2>&1
        started_cluster=no
    fi
    rm -rf "$tmp"
}
trap 'cleanup' EXIT INT TERM

# ----------------------------------------------------------------------
# finding a server
# ----------------------------------------------------------------------

# Everything a packaged PostgreSQL might be, in the order worth trying. The
# globs are left unquoted on purpose; an unmatched one is simply not a
# directory and is skipped.
pg_bin_candidates() {
    [ -n "${PG_BINDIR:-}" ] && echo "$PG_BINDIR"
    command -v pg_ctl >/dev/null 2>&1 && dirname "$(command -v pg_ctl)"
    for d in /usr/lib/postgresql/*/bin /usr/pgsql-*/bin \
             /opt/homebrew/opt/postgresql*/bin /usr/local/pgsql/bin; do
        [ -d "$d" ] && echo "$d"
    done
}

initdb=
pg_ctl=
for d in $(pg_bin_candidates); do
    if [ -x "$d/initdb" ] && [ -x "$d/pg_ctl" ]; then
        initdb=$d/initdb
        pg_ctl=$d/pg_ctl
        break
    fi
done

dsn=${CLIPSPG_DSN:-}

if [ -n "$dsn" ]; then
    echo "using the server at CLIPSPG_DSN"
elif [ -n "$initdb" ]; then
    echo "creating a cluster with $initdb"
    mkdir -p "$sock"
    # --auth=trust: the cluster lives for the length of this script, listens
    # on a socket inside tests/tmp and never on TCP.
    # -N: the cluster is deleted at the end of this script, so there is
    # nothing for a durable initdb to protect.
    if ! "$initdb" -D "$data" -U "$(id -un)" --auth=trust -N \
                   --encoding=UTF8 --locale=C >"$tmp/initdb.log" 2>&1; then
        echo "initdb failed:" >&2
        tail -20 "$tmp/initdb.log" >&2
        exit 1
    fi

    if ! "$pg_ctl" -D "$data" -l "$serverlog" -w \
                   -o "-k \"$sock\" -h '' -c fsync=off -c full_page_writes=off" \
                   start >"$tmp/pg_ctl.log" 2>&1; then
        echo "the server would not start:" >&2
        tail -20 "$serverlog" >&2
        exit 1
    fi
    started_cluster=yes
    dsn="host=$sock dbname=postgres user=$(id -un)"

    # The examples connect with an empty connection string, the way a
    # program run by hand does, so what they connect to is said here in the
    # variables libpq reads.
    PGHOST=$sock
    PGDATABASE=postgres
    PGUSER=$(id -un)
    export PGHOST PGDATABASE PGUSER
else
    echo "no PostgreSQL installation found: the suites that need a server"
    echo "will be skipped. 'make pg-server' builds one, or install one and"
    echo "put it on PATH, or point CLIPSPG_DSN at a server already running."
fi

# What the suite is told about the server it has, or has not, been given.
{
    echo "; Written by tests/run.sh. The suites read these two."
    if [ -n "$dsn" ]; then
        echo "(defglobal ?*have-server* = TRUE)"
        printf '(defglobal ?*dsn* = "%s")\n' "$dsn"
    else
        echo "(defglobal ?*have-server* = FALSE)"
        echo '(defglobal ?*dsn* = "")'
    fi
} > "$tmp/dsn.bat"

# ----------------------------------------------------------------------
# the examples
#
# Each one is run to completion and has to say what its .expected file says
# it says. A line there is matched as a substring of some line of the
# output, which keeps the checks to what the example is demonstrating and
# away from what changes between machines -- a socket path, a server
# version, the process id of a backend.
#
# Writing anything to stderr fails the example too: everything in this
# library reports a refused call there, so an example that starts doing that
# has stopped working whatever it printed on the way.
# ----------------------------------------------------------------------

failures=0

check_example() {
    example=$1
    expected=${example%.bat}.expected
    name=$(basename "$example")
    out=$tmp/${name%.bat}.out
    err=$tmp/${name%.bat}.err

    if [ ! -f "$expected" ]; then
        echo
        echo "FAILED: $example has no $expected beside it"
        failures=$((failures + 1))
        return
    fi

    $CLIPS -f2 "$example" >"$out" 2>"$err"
    status=$?

    if [ "$status" -ne 0 ]; then
        echo
        echo "FAILED: $example exited $status"
        sed -n '1,20p' "$err"
        failures=$((failures + 1))
        return
    fi

    if [ -s "$err" ]; then
        echo
        echo "FAILED: $example wrote to stderr"
        sed -n '1,20p' "$err"
        failures=$((failures + 1))
        return
    fi

    missing=0
    while IFS= read -r line; do
        case "$line" in ''|'#'*) continue ;; esac
        if ! grep -Fq "$line" "$out"; then
            if [ "$missing" -eq 0 ]; then
                echo
                echo "FAILED: $example did not say what $expected says it says"
            fi
            echo "  missing: $line"
            missing=$((missing + 1))
        fi
    done < "$expected"

    if [ "$missing" -gt 0 ]; then
        echo "  what it said:"
        sed 's/^/    /' "$out"
        failures=$((failures + 1))
        return
    fi

    printf '.'
}

if [ "$what" = all ] || [ "$what" = suite ]; then
    # stderr is kept as well as shown: the messages the wrappers write there
    # are most of what the suite is checking, and one of them means an
    # assertion never ran at all.
    $CLIPS -f2 tests/test.bat 2>"$tmp/suite.err"
    status=$?
    cat "$tmp/suite.err" >&2

    if [ "$status" -ne 0 ]; then
        failures=$((failures + 1))
        echo
        echo "FAILED: tests/test.bat (exit $status)"
    fi

    # An error raised while an (expect ...) is evaluating its arguments
    # aborts the expect: the assertion disappears from the count instead of
    # failing, and the suite reports a pass it never made. Every deliberate
    # refusal in the suites is bound on a line of its own for exactly this
    # reason, so this is always a bug in the suite.
    if grep -q "evaluating arguments for the deffunction 'expect'" "$tmp/suite.err"; then
        failures=$((failures + 1))
        echo
        echo "FAILED: an assertion was aborted by an evaluation error, so it"
        echo "        did not run. Bind the call on a line of its own and"
        echo "        assert on the binding. The error was:"
        grep -B3 "evaluating arguments for the deffunction 'expect'" "$tmp/suite.err" | sed 's/^/          /'
    fi
fi

if [ "$what" = all ] || [ "$what" = examples ]; then
    echo
    if [ -z "$dsn" ]; then
        echo "examples: skipped, there is no server to run them against"
    elif [ -z "${PGHOST:-}${PGDATABASE:-}" ]; then
        # CLIPSPG_DSN said where the server is, and the examples cannot be
        # told: they take an empty connection string on purpose, so that they
        # read like a program someone would write by hand.
        echo "examples: skipped, CLIPSPG_DSN names a server the examples"
        echo "          cannot be pointed at. Set PGHOST and PGDATABASE too"
        echo "          to run them."
    else
        printf 'examples '
        for example in examples/*.bat; do
            [ -f "$example" ] || continue
            check_example "$example"
        done
        echo
    fi
fi

cleanup

if [ "$failures" -gt 0 ]; then
    echo "FAILED"
    exit 1
fi

echo "PASSED"

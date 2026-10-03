# CLIPSPostgreSQL API Reference

Every user-defined function this library adds to the CLIPS environment,
grouped and ordered to match [the libpq chapter of the PostgreSQL
manual](@DOCS_BASE@/libpq.html). Each CLIPS function corresponds to the libpq
function of the same name, spelled the way CLIPS spells things: `PQexecParams`
is `pq-exec-params`, `PQgetCopyData` is `pq-get-copy-data`. Each entry's
description carries the wording of that function's documentation in the
manual, and where the CLIPS calling convention differs from C, the difference
is noted in the entry.

This reference was generated from the documentation for **PostgreSQL
@PG_VERSION@**, the newest version this library supports. It describes every
function the library can bind, whichever version you built against: @ALWAYS@
of them are there in every supported release, and the rest say which release
they need. What is deliberately left out is listed under
[Not exposed](#not-exposed).

Every entry gives the CLIPS call form, then the description, then the C
prototype it corresponds to, then its arguments in call order with the CLIPS
types each accepts, and under **Returns** the value produced on success.

## Versions

The library builds against **PostgreSQL 14 through @PG_VERSION@**, and binds
what the libpq it was built against actually has. A function PostgreSQL added
later than that libpq is not compiled in, and calling it is an ordinary
CLIPS "missing function" error rather than anything this library reports.

Only the major version matters here. libpq has not added or removed a
function in a minor release in any major from 9.6 onwards, so what follows is
as true of 17.0 as it is of 17.11.

| Needs | Functions |
| --- | --- |
| any supported version | @ALWAYS@ |
| PostgreSQL 16 or later | @SINCE16@ |
| PostgreSQL 17 or later | @SINCE17@ |
| PostgreSQL 18 or later | @SINCE18@ |

Each entry below says which it needs. CLIPS gives a program no way to ask
whether a function is defined, so `pq-built-version` answers the question the
other way round -- it is the version of the libpq the wrappers were compiled
against, in the same numbers PostgreSQL versions itself with:

```clips
(if (>= (pq-built-version) 170000)
 then (bind ?cancel (pq-cancel-create ?conn))
 else ...)
```

That is not the same question as `pq-lib-version`, which is the library
loaded now: a binding compiled against 17 runs perfectly well with an 18
library under it, and still has only the 17 functions in it.

## Conventions

**Handles.** Connections, results and cancel connections are CLIPS external
addresses. They are not interchangeable: passing a result where a connection
belongs is refused, but a handle of the right kind pointing at the wrong
object is as undefined here as it is in C.

**Closing a handle empties it.** `pq-finish`, `pq-clear` and `pq-cancel-finish`
set the CLIPS value they are given to a null pointer, so a second close, or
any other call on a closed handle, is refused rather than being a second free
of the same memory:

```clips
(bind ?conn (pq-connectdb "dbname=widgets"))
(pq-finish ?conn)
(pq-status ?conn)     ; FALSE, and a message on STDERR
```

**Failure is FALSE.** Any function that can fail returns the symbol `FALSE`
and writes a message describing the problem to `STDERR`. The message names
the function, and, where libpq had something to say, quotes it.

**A refusal and a rejection are different things.** A command the server
refused is not a failed call: it is a result whose status says what happened.
`pq-exec` answers with a result whether or not the server liked the command,
and `FALSE` is kept for the case where libpq produced no result at all --
the connection is gone, or there was no memory for one. That is also the case
where there is nothing to clear:

```clips
(bind ?res (pq-exec ?conn "SELEC 1"))
(pq-result-status ?res)                          ; PGRES_FATAL_ERROR
(pq-result-error-field ?res PG_DIAG_SQLSTATE)    ; "42601"
(pq-clear ?res)
```

**FALSE also means "nothing to report".** For the readers -- an error message
that is empty, a parameter the server never sent, a column that belongs to no
table -- `FALSE` is the answer, and no message is written. These are the
functions whose C counterparts return `NULL` or an empty string for the same
reason.

**`nil` is SQL NULL.** A NULL field read with `pq-getvalue` or mapped into a
fact is the symbol `nil`, not the empty string, and a parameter given as `nil`
is sent as SQL NULL. `pq-getisnull` is still there for a caller that would
rather ask than compare.

**Enumerations are symbols spelled exactly as in C.** Connection statuses,
result statuses, transaction statuses, polling statuses and pipeline statuses
come back as `CONNECTION_OK`, `PGRES_TUPLES_OK`, `PQTRANS_INTRANS`,
`PGRES_POLLING_READING`, `PQ_PIPELINE_ON`. Every function that takes one
accepts either the symbol or the integer behind it.

**Indices count from zero**, matching the C API, and are checked: a row or
column number outside the result is refused rather than answered with an
empty value.

**Parameters are a multifield.** Where a C function takes an array of values
and a count, the CLIPS function takes one multifield and counts it. Every
value is sent in text format and typed by the server, so no type OIDs are
needed:

```clips
(pq-exec-params ?conn "SELECT $1::int + 1" (create$ 41))
(pq-exec-params ?conn "INSERT INTO parts VALUES ($1, $2)" (create$ 7 nil))
```

**Binary data is a multifield of bytes.** A `bytea` crosses as integers from 0
to 255, so a zero byte in the middle of it is a field like any other rather
than the end of a string.

### Rows

Reading a result column by column is always available, and nine functions
with no C counterpart convert rows in one call instead, each column by its
type. Three take one row: `pq-row-to-multifield`, `pq-row-to-fact` and
`pq-row-to-instance`. Six take every row of a result and answer what they
made, in row order: `pq-result-to-multifields`, `pq-result-to-facts` and
`pq-result-to-instances`, and `pq-exec-to-multifields`, `pq-exec-to-facts`
and `pq-exec-to-instances`, which run the command as well.

```clips
(deftemplate widget (slot id) (slot name) (slot weight))

(pq-exec-to-facts ?conn "SELECT id, name, weight FROM widgets")
```

That call runs the query, asserts one `widget` fact per row, clears the
result, and answers a multifield of the fact addresses. The deftemplate can
be left out when the columns all come from one table, which is then its name;
a defclass is inferred the same way, in capitals.

The integers, the floating-point types and `boolean` become CLIPS integers,
floats and `TRUE`/`FALSE`; SQL NULL becomes `nil`; everything else keeps the
text PostgreSQL printed, which is the only conversion that loses nothing. The
one to know about is `numeric`, which becomes a float: a value too precise for
a double loses that precision, and `pq-getvalue` is how to keep it exact.

Column names are slot names. The one-row functions refuse a column with no
slot to go in; the whole-result functions pass it over, skip a row a slot
refuses, and report once on `STDERR` that they did.

## Database Connection Control Functions

<!-- functions -->

## Connection Status Functions

<!-- functions -->

## Command Execution Functions

<!-- functions -->

## Retrieving Query Result Information

<!-- functions -->

## Retrieving Other Result Information

<!-- functions -->

## Escaping Strings for Inclusion in SQL Commands

<!-- functions -->

## Rows as CLIPS Data

These nine have no counterpart in libpq. Everything else in this reference
is a function of the C API; these are the conversion the C API leaves to its
caller, done once here. The first three take one row and the other six take
every row of a result, or run the command and take every row of its result.

<!-- functions -->

## Asynchronous Command Processing

<!-- functions -->

## Pipeline Mode

<!-- functions -->

## Canceling Queries in Progress

<!-- functions -->

## Asynchronous Notification

<!-- functions -->

## Functions Associated with the COPY Command

<!-- functions -->

## Control Functions

<!-- functions -->

## Miscellaneous Functions

<!-- functions -->

## Not exposed

The rest of libpq is left out on purpose, and this is why. The list is
checked when this reference is generated: a function the manual documents
that is neither bound nor named here is an error, so nothing can be left out
by accident.

**Superseded by something that is bound.** PostgreSQL still ships these and
its own documentation points elsewhere, so this binding points elsewhere too.

- `PQsetdb` -- `pq-setdb-login` with two fewer parameters.
- `PQgetCancel`, `PQfreeCancel`, `PQcancel`, `PQrequestCancel` -- the cancel
  interface that came before `PQcancelCreate`. `pq-cancel-create` and the
  functions around it are the current one, and the only one that can cancel
  without blocking.
- `PQescapeString`, `PQescapeBytea` -- escaping without a connection, which
  cannot know the server's string syntax. `pq-escape-string-conn` and
  `pq-escape-bytea-conn` can.
- `PQencryptPassword` -- superseded by `pq-encrypt-password-conn`, which asks
  the server which algorithm it wants.
- `PQoidStatus` -- superseded by `pq-oid-value`, which does not use a static
  buffer.
- `PQgetline`, `PQgetlineAsync`, `PQputline`, `PQputnbytes`, `PQendcopy` --
  the COPY interface of PostgreSQL 7.3 and earlier. `pq-get-copy-data`,
  `pq-put-copy-data` and `pq-put-copy-end` are the current one.
- `PQtty` -- has done nothing since PostgreSQL 14.

**Memory this binding owns.** Every string libpq allocates is copied into a
CLIPS value and freed before the call returns, and every handle is freed by
the function that closes it, so there is nothing left for a caller to free.

- `PQfreemem`, `PQconninfoFree`, `PQresultAlloc`

**C function pointers.** These take a callback, and a CLIPS program has no
way to produce one.

- `PQsetNoticeProcessor`, `PQsetNoticeReceiver` -- notices are written to
  `STDERR` by libpq's own default processor, which is left in place.
- `PQsetAuthDataHook`, `PQgetAuthDataHook`
- `PQregisterEventProc`, `PQinstanceData`, `PQsetInstanceData`,
  `PQresultInstanceData`, `PQresultSetInstanceData`,
  `PQfireResultCreateEvents` -- the event system, which exists to let C code
  hang its own data off a connection.

**Building a result by hand.** `pq-make-empty-pgresult` is bound because a
program may want a result of its own to return; filling one in field by field
is a C idiom with no use here.

- `PQcopyResult`, `PQsetResultAttrs`, `PQsetvalue`

**Streams and file descriptors.** All of these take a `FILE *`.

- `PQprint`, `PQtrace`, `PQuntrace`, `PQsetTraceFlags`

**OpenSSL internals.** These hand back the SSL library's own structures for C
code to call the SSL library with. `pq-ssl-attribute` and
`pq-ssl-attribute-names` answer the questions that can be answered without
one.

- `PQgetssl`, `PQsslStruct`, `PQinitSSL`, `PQinitOpenSSL`,
  `PQsetSSLKeyPassHook_OpenSSL`, `PQgetSSLKeyPassHook_OpenSSL`

**The fast-path interface.** `PQfn` calls a function by OID over a protocol
message of its own. The manual describes it as an interface to be avoided in
new code, and SQL reaches everything it reaches.

- `PQfn`

**Declared but not documented.** libpq-fe.h also declares PQmblen,
PQmblenBounded, PQdsplen and PQenv2encoding, which the manual does not
describe. The first three measure a character in a buffer the caller owns,
and CLIPS strings are not that buffer; the fourth reads PGCLIENTENCODING from
the environment, which `(get-env "PGCLIENTENCODING")` already does.

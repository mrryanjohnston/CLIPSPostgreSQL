# CLIPSPostgreSQL API Reference

Every user-defined function this library adds to the CLIPS environment,
grouped and ordered to match [the libpq chapter of the PostgreSQL
manual](https://www.postgresql.org/docs/18/libpq.html). Each CLIPS function corresponds to the libpq
function of the same name, spelled the way CLIPS spells things: `PQexecParams`
is `pq-exec-params`, `PQgetCopyData` is `pq-get-copy-data`. Each entry's
description carries the wording of that function's documentation in the
manual, and where the CLIPS calling convention differs from C, the difference
is noted in the entry.

This reference was generated from the documentation for **PostgreSQL
18.6**, the newest version this library supports. It describes every
function the library can bind, whichever version you built against: 113
of them are there in every supported release, and the rest say which release
they need. What is deliberately left out is listed under
[Not exposed](#not-exposed).

Every entry gives the CLIPS call form, then the description, then the C
prototype it corresponds to, then its arguments in call order with the CLIPS
types each accepts, and under **Returns** the value produced on success.

## Versions

The library builds against **PostgreSQL 14 through 18.6**, and binds
what the libpq it was built against actually has. A function PostgreSQL added
later than that libpq is not compiled in, and calling it is an ordinary
CLIPS "missing function" error rather than anything this library reports.

Only the major version matters here. libpq has not added or removed a
function in a minor release in any major from 9.6 onwards, so what follows is
as true of 17.0 as it is of 17.11.

| Needs | Functions |
| --- | --- |
| any supported version | 113 |
| PostgreSQL 16 or later | 1 |
| PostgreSQL 17 or later | 18 |
| PostgreSQL 18 or later | 1 |

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

### `pq-connectdb`

```clips
(pq-connectdb [?conninfo])
```

Makes a new connection to the database server, using the parameters taken
from the connection string, and waits for it to be established.

A connection object comes back whether or not the attempt succeeded --
`pq-status` is what says which, and on a connection that failed
`pq-error-message` says why. Either way it is the caller's to close with
`pq-finish`.

The string may be empty, to use every default; it may be a list of
`keyword=value` settings separated by whitespace; or it may be a URI. See
[Connection Strings](@DOCS_BASE@/libpq-connect.html#LIBPQ-CONNSTRING).

In C:

```c
PGconn *PQconnectdb(const char *conninfo);
```

#### Arguments

- `STRING`/`SYMBOL` `conninfo` (optional): Optional. The connection string. Defaults to the empty string, which uses the defaults for every parameter.

#### Returns

- `EXTERNAL-ADDRESS`: The connection, connected or not. Close it with `pq-finish`.

### `pq-connectdb-params`

```clips
(pq-connectdb-params ?keywords ?values [?expand-dbname])
```

Makes a new connection to the database server, using parameters given as two
multifields, and waits for it to be established.

The keywords and the values are separate multifields of the same length, and
each keyword takes the value in the matching position; a value of `nil` leaves
that parameter at its default, as a null pointer does in C. Nothing has to be
quoted or escaped, which is the reason to prefer this over building a
connection string.

```clips
(pq-connectdb-params (create$ host dbname connect_timeout)
                     (create$ "/var/run/postgresql" widgets 5))
```

As with `pq-connectdb`, a connection object comes back whether or not the
attempt succeeded.

In C:

```c
PGconn *PQconnectdbParams(const char * const *keywords,
                          const char * const *values,
                          int expand_dbname);
```

#### Arguments

- `MULTIFIELD` `keywords`: The parameter names, as symbols or strings.

- `MULTIFIELD` `values`: The value for each keyword, in the same order. `nil` leaves a parameter at its default.

- `BOOLEAN` `expand-dbname` (optional): Optional, `TRUE` by default. When the `dbname` value contains an `=` sign or a URI prefix, it is taken as a connection string of its own and expanded.

#### Returns

- `EXTERNAL-ADDRESS`: The connection, connected or not. Close it with `pq-finish`.

### `pq-setdb-login`

```clips
(pq-setdb-login ?pghost ?pgport ?pgoptions ?pgtty ?dbname ?login ?pwd)
```

Makes a new connection to the database server with a fixed set of parameters.

This is the predecessor of `pq-connectdb`. It has the same effect except that
every parameter it does not take is left at its default; `nil` for one it does
take leaves that one at its default too.

`pgtty` has been ignored since PostgreSQL 14 and is still taken so that the
argument list matches the C function.

In C:

```c
PGconn *PQsetdbLogin(const char *pghost,
                     const char *pgport,
                     const char *pgoptions,
                     const char *pgtty,
                     const char *dbName,
                     const char *login,
                     const char *pwd);
```

#### Arguments

- `STRING`/`SYMBOL` `pghost`: The host to connect to, or `nil`.

- `STRING`/`SYMBOL` `pgport`: The port, or `nil`.

- `STRING`/`SYMBOL` `pgoptions`: Command-line options for the backend, or `nil`.

- `STRING`/`SYMBOL` `pgtty`: Ignored. Pass `nil`.

- `STRING`/`SYMBOL` `dbname`: The database name, or `nil`. A value containing `=` or a URI prefix is taken as a connection string.

- `STRING`/`SYMBOL` `login`: The user name, or `nil`.

- `STRING`/`SYMBOL` `pwd`: The password, or `nil`.

#### Returns

- `EXTERNAL-ADDRESS`: The connection, connected or not. Close it with `pq-finish`.

### `pq-connect-start`

```clips
(pq-connect-start [?conninfo])
```

Makes a new connection to the database server without waiting for it to be
established.

The connection is not usable until it has been polled through with
`pq-connect-poll`, which is the point of starting one this way: a CLIPS
program that has other work to do can do it between polls.

In C:

```c
PGconn *PQconnectStartParams(const char * const *keywords,
                             const char * const *values,
                             int expand_dbname);

PGconn *PQconnectStart(const char *conninfo);

PostgresPollingStatusType PQconnectPoll(PGconn *conn);
```

#### Arguments

- `STRING`/`SYMBOL` `conninfo` (optional): Optional. The connection string. Defaults to the empty string.

#### Returns

- `EXTERNAL-ADDRESS`: A connection whose status is `CONNECTION_STARTED`, or `FALSE` if libpq could not allocate one. Close it with `pq-finish` however the polling ends.

### `pq-connect-start-params`

```clips
(pq-connect-start-params ?keywords ?values [?expand-dbname])
```

Makes a new connection to the database server, from keywords and values,
without waiting for it to be established. `pq-connectdb-params` describes the
two multifields; `pq-connect-poll` carries it the rest of the way.

In C:

```c
PGconn *PQconnectStartParams(const char * const *keywords,
                             const char * const *values,
                             int expand_dbname);

PGconn *PQconnectStart(const char *conninfo);

PostgresPollingStatusType PQconnectPoll(PGconn *conn);
```

#### Arguments

- `MULTIFIELD` `keywords`: The parameter names, as symbols or strings.

- `MULTIFIELD` `values`: The value for each keyword, in the same order. `nil` leaves a parameter at its default.

- `BOOLEAN` `expand-dbname` (optional): Optional, `TRUE` by default.

#### Returns

- `EXTERNAL-ADDRESS`: A connection whose status is `CONNECTION_STARTED`, or `FALSE` if libpq could not allocate one.

### `pq-connect-poll`

```clips
(pq-connect-poll ?conn)
```

Carries a connection started with `pq-connect-start` one step further along.

Call it until it answers `PGRES_POLLING_OK`, which means the connection is
ready, or `PGRES_POLLING_FAILED`, which means it will not be. Between calls,
`PGRES_POLLING_READING` and `PGRES_POLLING_WRITING` say which way the socket
should be waited on, which `pq-socket` and `pq-socket-poll` can do.

In C:

```c
PGconn *PQconnectStartParams(const char * const *keywords,
                             const char * const *values,
                             int expand_dbname);

PGconn *PQconnectStart(const char *conninfo);

PostgresPollingStatusType PQconnectPoll(PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `SYMBOL`: `PGRES_POLLING_READING`, `PGRES_POLLING_WRITING`, `PGRES_POLLING_OK` or `PGRES_POLLING_FAILED`.

### `pq-finish`

```clips
(pq-finish ?conn)
```

Closes the connection to the server and frees everything held for it.

The handle is emptied, so any later call on it is refused rather than being a
second free of the same pointer. Results already taken from the connection
are not affected: they are copies, and stay readable until they are cleared.

In C:

```c
void PQfinish(PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `BOOLEAN`: `TRUE`. `FALSE` if the handle was not a connection, or had already been finished.

### `pq-reset`

```clips
(pq-reset ?conn)
```

Closes the connection to the server and reopens it with the same parameters,
waiting for the new connection to be established.

This is what to do with a connection that has broken: the backend it was
talking to is gone, and everything in flight with it, but the parameters are
still here.

In C:

```c
void PQreset(PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `BOOLEAN`: `TRUE` once the attempt has finished. Whether it succeeded is what `pq-status` says.

### `pq-reset-start`

```clips
(pq-reset-start ?conn)
```

Reset the communication channel to the server, in a nonblocking manner.

These functions will close the connection to the server and attempt to establish a new connection, using all the same parameters previously used. This can be useful for error recovery if a working connection is lost. They differ from `pq-reset` (above) in that they act in a nonblocking manner. These functions suffer from the same restrictions as `pq-connect-start-params`, `pq-connect-start` and `pq-connect-poll`.

To initiate a connection reset, call `pq-reset-start`. If it answers `FALSE`, the reset has failed. If it answers `TRUE`, poll the reset using `pq-reset-poll` in exactly the same way as you would create the connection using `pq-connect-poll`.

In C:

```c
int PQresetStart(PGconn *conn);

PostgresPollingStatusType PQresetPoll(PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `BOOLEAN`

### `pq-reset-poll`

```clips
(pq-reset-poll ?conn)
```

Carries a reset started with `pq-reset-start` one step further along, exactly
as `pq-connect-poll` does for a new connection.

In C:

```c
int PQresetStart(PGconn *conn);

PostgresPollingStatusType PQresetPoll(PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `SYMBOL`: `PGRES_POLLING_READING`, `PGRES_POLLING_WRITING`, `PGRES_POLLING_OK` or `PGRES_POLLING_FAILED`.

### `pq-ping`

```clips
(pq-ping [?conninfo])
```

`pq-ping` reports the status of the server. It accepts connection parameters identical to those of `pq-connectdb`, described above. It is not necessary to supply correct user name, password, or database name values to obtain the server status; however, if incorrect values are provided, the server will log a failed connection attempt.

The return values are the same as for `pq-ping-params`.

In C:

```c
PGPing PQping(const char *conninfo);
```

#### Arguments

- `STRING`/`SYMBOL` `conninfo` (optional): Optional. The connection string naming the server to ask about.

#### Returns

- `SYMBOL`: `PQPING_OK`, `PQPING_REJECT`, `PQPING_NO_RESPONSE` or `PQPING_NO_ATTEMPT`.

### `pq-ping-params`

```clips
(pq-ping-params ?keywords ?values [?expand-dbname])
```

Reports whether the server can be reached, from keywords and values rather
than a connection string. `pq-connectdb-params` describes the two multifields.

In C:

```c
PGPing PQpingParams(const char * const *keywords,
                    const char * const *values,
                    int expand_dbname);
```

#### Arguments

- `MULTIFIELD` `keywords`: The parameter names, as symbols or strings.

- `MULTIFIELD` `values`: The value for each keyword, in the same order.

- `BOOLEAN` `expand-dbname` (optional): Optional, `TRUE` by default.

#### Returns

- `SYMBOL`: `PQPING_OK`, `PQPING_REJECT`, `PQPING_NO_RESPONSE` or `PQPING_NO_ATTEMPT`.

### `pq-conndefaults`

```clips
(pq-conndefaults)
```

Returns the connection options this libpq understands, and the default value
of each.

The options come back flattened into one multifield: a keyword as a symbol,
then its value as a string, then the next keyword, and so on. A keyword whose
value is not set -- because no environment variable or service file gave it
one -- has the symbol `nil` in its place.

```clips
(bind ?options (pq-conndefaults))
(nth$ 1 ?options)      ; service
(nth$ 2 ?options)      ; nil
```

In C:

```c
PQconninfoOption *PQconndefaults(void);

typedef struct
{
    char   *keyword;   /* The keyword of the option */
    char   *envvar;    /* Fallback environment variable name */
    char   *compiled;  /* Fallback compiled in default value */
    char   *val;       /* Option's current value, or NULL */
    char   *label;     /* Label for field in connect dialog */
    char   *dispchar;  /* Indicates how to display this field
                          in a connect dialog. Values are:
                          ""        Display entered value as is
                          "*"       Password field - hide value
                          "D"       Debug option - don't show by default */
    int     dispsize;  /* Field size in characters for dialog */
} PQconninfoOption;
```

#### Returns

- `MULTIFIELD`: Keyword and value, alternating, for every option libpq has.

### `pq-conninfo`

```clips
(pq-conninfo ?conn)
```

Returns the connection options used by a live connection, in the same
flattened shape `pq-conndefaults` uses: keyword, value, keyword, value, with
`nil` for an option that is not set.

Passwords are not included, which is what makes this safe to print.

In C:

```c
PQconninfoOption *PQconninfo(PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`: The connection to describe.

#### Returns

- `MULTIFIELD`: Keyword and value, alternating, for every option of this connection.

### `pq-conninfo-parse`

```clips
(pq-conninfo-parse ?conninfo)
```

Parses a connection string and returns the options it sets, in the same
flattened shape `pq-conndefaults` uses.

Only the options the string names have values; the rest are `nil`. A string
libpq cannot parse -- an unknown keyword, a keyword with no value -- is a
failure, and libpq's explanation is written to `STDERR`.

In C:

```c
PQconninfoOption *PQconninfoParse(const char *conninfo, char **errmsg);
```

#### Arguments

- `STRING`/`SYMBOL` `conninfo`: The connection string to parse, in `keyword=value` or URI form.

#### Returns

- `MULTIFIELD`: Keyword and value, alternating.


## Connection Status Functions

### `pq-db`

```clips
(pq-db ?conn)
```

Returns the database name of the connection.

In C:

```c
char *PQdb(const PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `STRING`

### `pq-user`

```clips
(pq-user ?conn)
```

Returns the user name of the connection.

In C:

```c
char *PQuser(const PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `STRING`

### `pq-pass`

```clips
(pq-pass ?conn)
```

Returns the password of the connection.

`pq-pass` will return either the password specified in the connection parameters, or if there was none and the password was obtained from the [password file](https://www.postgresql.org/docs/18/libpq-pgpass.html), it will return that. In the latter case, if multiple hosts were specified in the connection parameters, it is not possible to rely on the result of `pq-pass` until the connection is established. The status of the connection can be checked using the function `pq-status`.

In C:

```c
char *PQpass(const PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `STRING`

### `pq-host`

```clips
(pq-host ?conn)
```

Returns the server host name of the active connection. This can be a host name, an IP address, or a directory path if the connection is via Unix socket. (The path case can be distinguished because it will always be an absolute path, beginning with `/`.)

If the connection parameters specified both `host` and `hostaddr`, then `pq-host` will return the `host` information. If only `hostaddr` was specified, then that is returned. If multiple hosts were specified in the connection parameters, `pq-host` returns the host actually connected to.

`pq-host` returns `NULL` if the

argument is `NULL`. Otherwise, if there is an error producing the host information (perhaps if the connection has not been fully established or there was an error), it returns an empty string.

If multiple hosts were specified in the connection parameters, it is not possible to rely on the result of `pq-host` until the connection is established. The status of the connection can be checked using the function `pq-status`.

In C:

```c
char *PQhost(const PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `STRING`

### `pq-hostaddr`

```clips
(pq-hostaddr ?conn)
```

Returns the server IP address of the active connection. This can be the address that a host name resolved to, or an IP address provided through the `hostaddr` parameter.

`pq-hostaddr` returns `NULL` if the

argument is `NULL`. Otherwise, if there is an error producing the host information (perhaps if the connection has not been fully established or there was an error), it returns an empty string.

In C:

```c
char *PQhostaddr(const PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `STRING`

### `pq-port`

```clips
(pq-port ?conn)
```

Returns the port of the active connection.

If multiple ports were specified in the connection parameters, `pq-port` returns the port actually connected to.

`pq-port` returns `NULL` if the

argument is `NULL`. Otherwise, if there is an error producing the port information (perhaps if the connection has not been fully established or there was an error), it returns an empty string.

If multiple ports were specified in the connection parameters, it is not possible to rely on the result of `pq-port` until the connection is established. The status of the connection can be checked using the function `pq-status`.

In C:

```c
char *PQport(const PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `STRING`

### `pq-options`

```clips
(pq-options ?conn)
```

Returns the command-line options passed in the connection request.

In C:

```c
char *PQoptions(const PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `STRING`

### `pq-status`

```clips
(pq-status ?conn)
```

Returns the status of the connection.

The status can be one of a number of values. However, only two of these are seen outside of an asynchronous connection procedure: `CONNECTION_OK` and `CONNECTION_BAD`. A good connection to the database has the status `CONNECTION_OK`. A failed connection attempt is signaled by status `CONNECTION_BAD`. Ordinarily, an OK status will remain so until `pq-finish`, but a communications failure might result in the status changing to `CONNECTION_BAD` prematurely. In that case the application could try to recover by calling `pq-reset`.

See the entry for `pq-connect-start-params`, `pq-connect-start` and `pq-connect-poll` with regards to other status codes that might be returned.

In C:

```c
ConnStatusType PQstatus(const PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `SYMBOL`: `CONNECTION_OK`, `CONNECTION_BAD`, or one of the states a connection being established passes through.

### `pq-transaction-status`

```clips
(pq-transaction-status ?conn)
```

Returns the current in-transaction status of the server. The status can be `PQTRANS_IDLE` (currently idle), `PQTRANS_ACTIVE` (a command is in progress), `PQTRANS_INTRANS` (idle, in a valid transaction block), or `PQTRANS_INERROR` (idle, in a failed transaction block). `PQTRANS_UNKNOWN` is reported if the connection is bad. `PQTRANS_ACTIVE` is reported only when a query has been sent to the server and not yet completed.

In C:

```c
PGTransactionStatusType PQtransactionStatus(const PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `SYMBOL`: `PQTRANS_IDLE` (connected and idle), `PQTRANS_ACTIVE` (a command is in progress), `PQTRANS_INTRANS` (idle, in a transaction block), `PQTRANS_INERROR` (idle, in a failed transaction block) or `PQTRANS_UNKNOWN` (the connection is bad).

### `pq-parameter-status`

```clips
(pq-parameter-status ?conn ?param-name)
```

Returns the server's current setting of a parameter it reports to the client,
such as `server_version`, `client_encoding` or `TimeZone`.

In C:

```c
const char *PQparameterStatus(const PGconn *conn, const char *paramName);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `STRING`/`SYMBOL` `param-name`: The parameter to ask about.

#### Returns

- `STRING`: The value, or `FALSE` for a parameter this server does not report.

### `pq-protocol-version`

```clips
(pq-protocol-version ?conn)
```

Interrogates the frontend/backend protocol major version. Unlike `pq-full-protocol-version`, this returns only the major protocol version in use, but it is supported by a wider range of libpq releases back to version 7.4. Currently, the possible values are 3 (3.0 protocol), or zero (connection bad). Prior to release version 14.0, libpq could additionally return 2 (2.0 protocol).

In C:

```c
int PQprotocolVersion(const PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `INTEGER`

### `pq-full-protocol-version`

```clips
(pq-full-protocol-version ?conn)
```

Interrogates the frontend/backend protocol being used. Applications might wish to use this function to determine whether certain features are supported. The result is formed by multiplying the server's major version number by 10000 and adding the minor version number. For example, version 3.2 would be returned as 30002, and version 4.0 would be returned as 40000. Zero is returned if the connection is bad. The 3.0 protocol is supported by PostgreSQL server versions 7.4 and above.

The protocol version will not change after connection startup is complete, but it could theoretically change during a connection reset.

**Requires PostgreSQL 18 or later.** Built against an older libpq, this function is not defined at all; `pq-built-version` is how a program asks.

In C:

```c
int PQfullProtocolVersion(const PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `INTEGER`

### `pq-server-version`

```clips
(pq-server-version ?conn)
```

Returns an integer representing the server version.

Applications might use this function to determine the version of the database server they are connected to. The result is formed by multiplying the server's major version number by 10000 and adding the minor version number. For example, version 10.1 will be returned as 100001, and version 11.0 will be returned as 110000. Zero is returned if the connection is bad.

Prior to major version 10, PostgreSQL used three-part version numbers in which the first two parts together represented the major version. For those versions, `pq-server-version` uses two digits for each part; for example version 9.1.5 will be returned as 90105, and version 9.2.0 will be returned as 90200.

Therefore, for purposes of determining feature compatibility, applications should divide the result of `pq-server-version` by 100 not 10000 to determine a logical major version number. In all release series, only the last two digits differ between minor releases (bug-fix releases).

In C:

```c
int PQserverVersion(const PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `INTEGER`

### `pq-error-message`

```clips
(pq-error-message ?conn)
```

Returns the message describing the most recent operation on the connection
that failed.

Nearly every libpq call sets this when it fails, so it is read straight after
the call that failed rather than kept: the next failure replaces it. The
message ends in a newline, as libpq writes it.

In C:

```c
char *PQerrorMessage(const PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `STRING`: The message, or `FALSE` when there is nothing to report.

### `pq-socket`

```clips
(pq-socket ?conn)
```

Returns the file descriptor of the connection's socket to the server, for a
program that wants to wait on it rather than block inside libpq.

In C:

```c
int PQsocket(const PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `INTEGER`: The descriptor, or `FALSE` when the connection has no open socket.

### `pq-backend-pid`

```clips
(pq-backend-pid ?conn)
```

`pq-backend-pid` of the backend process handling this connection.

The backend PID is useful for debugging purposes and for comparison to `NOTIFY` messages (which include the PID of the notifying backend process). Note that the PID belongs to a process executing on the database server host, not the local host!

In C:

```c
int PQbackendPID(const PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `INTEGER`

### `pq-connection-needs-password`

```clips
(pq-connection-needs-password ?conn)
```

Returns true (1) if the connection authentication method required a password, but none was available. Returns false (0) if not.

This function can be applied after a failed connection attempt to decide whether to prompt the user for a password.

In C:

```c
int PQconnectionNeedsPassword(const PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `BOOLEAN`

### `pq-connection-used-password`

```clips
(pq-connection-used-password ?conn)
```

Returns true (1) if the connection authentication method used a password. Returns false (0) if not.

This function can be applied after either a failed or successful connection attempt to detect whether the server demanded a password.

In C:

```c
int PQconnectionUsedPassword(const PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `BOOLEAN`

### `pq-connection-used-gssapi`

```clips
(pq-connection-used-gssapi ?conn)
```

Returns true (1) if the connection authentication method used GSSAPI. Returns false (0) if not.

This function can be applied to detect whether the connection was authenticated with GSSAPI.

**Requires PostgreSQL 16 or later.** Built against an older libpq, this function is not defined at all; `pq-built-version` is how a program asks.

In C:

```c
int PQconnectionUsedGSSAPI(const PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `BOOLEAN`

### `pq-ssl-in-use`

```clips
(pq-ssl-in-use ?conn)
```

Returns true (1) if the connection uses SSL, false (0) if not.

In C:

```c
int PQsslInUse(const PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `BOOLEAN`

### `pq-gss-enc-in-use`

```clips
(pq-gss-enc-in-use ?conn)
```

Returns whether the connection is encrypted with GSSAPI.

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `BOOLEAN`: `TRUE` if GSSAPI encryption is in use.

### `pq-ssl-attribute`

```clips
(pq-ssl-attribute ?conn ?attribute-name)
```

Returns one piece of information about the SSL in use on the connection --
`library`, `protocol`, `key_bits`, `cipher`, `compression`,
`alpn`. `pq-ssl-attribute-names` lists the ones this connection can answer.

In C:

```c
const char *PQsslAttribute(const PGconn *conn, const char *attribute_name);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `STRING`/`SYMBOL` `attribute-name`: The attribute to read.

#### Returns

- `STRING`: The value, or `FALSE` when the attribute has none, which is the answer for every attribute of a connection not using SSL.

### `pq-ssl-attribute-names`

```clips
(pq-ssl-attribute-names ?conn)
```

Returns the names of the SSL attributes this connection can be asked about
with `pq-ssl-attribute`.

In C:

```c
const char * const * PQsslAttributeNames(const PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `MULTIFIELD`: The attribute names, one symbol each. Empty when the connection is not using SSL.

### `pq-client-encoding`

```clips
(pq-client-encoding ?conn)
```

Returns the client encoding of the connection, as the integer id libpq
numbers encodings with.

The name is what most programs want, and
`(pq-parameter-status ?conn "client_encoding")` is where it is.

In C:

```c
int PQclientEncoding(const PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `INTEGER`: The encoding id.


## Command Execution Functions

### `pq-exec`

```clips
(pq-exec ?conn ?command)
```

Submits a command to the server and waits for the result.

A command the server refused is a result like any other: its status is
`PGRES_FATAL_ERROR` and `pq-result-error-message` says what was wrong with it.
`FALSE` is only for the case where there is no result at all, which means the
connection is broken or out of memory.

The command string may contain several statements separated by semicolons,
in which case the whole lot runs in one transaction unless it contains its
own transaction commands, and the result is the last statement's.

Every result must be cleared with `pq-clear`.

In C:

```c
PGresult *PQexec(PGconn *conn, const char *command);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `STRING`/`SYMBOL` `command`: The SQL to run.

#### Returns

- `EXTERNAL-ADDRESS`: The result. Clear it with `pq-clear`.

### `pq-exec-params`

```clips
(pq-exec-params ?conn ?command [?params])
```

Submits a command with parameters and waits for the result.

The parameters are one multifield, and `$1` in the command is its first
field. Every value is sent separately from the command text, which is what
makes this the safe way to put a value into a query: a parameter can never be
read as SQL, whatever it contains.

Values are sent in text format and typed by the server from the context they
appear in. A field of `nil` is sent as SQL NULL. Where the server cannot infer
a type, the usual cast in the command -- `$1::int` -- tells it.

```clips
(pq-exec-params ?conn "SELECT name FROM widgets WHERE weight > $1" (create$ 2.5))
```

In C:

```c
PGresult *PQexecParams(PGconn *conn,
                       const char *command,
                       int nParams,
                       const Oid *paramTypes,
                       const char * const *paramValues,
                       const int *paramLengths,
                       const int *paramFormats,
                       int resultFormat);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `STRING`/`SYMBOL` `command`: The SQL to run, with `$1`, `$2` and so on where the parameters go.

- `MULTIFIELD` `params` (optional): Optional. The parameter values, in order. `nil` is SQL NULL.

#### Returns

- `EXTERNAL-ADDRESS`: The result. Clear it with `pq-clear`.

### `pq-prepare`

```clips
(pq-prepare ?conn ?statement-name ?query)
```

Prepares a statement on the server under a name, for `pq-exec-prepared` to
run more than once.

The parameter types are left to the server to infer from the statement.

In C:

```c
PGresult *PQprepare(PGconn *conn,
                    const char *stmtName,
                    const char *query,
                    int nParams,
                    const Oid *paramTypes);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `STRING`/`SYMBOL` `statement-name`: The name to prepare it under. The empty string names the unnamed statement, which the next prepare replaces.

- `STRING`/`SYMBOL` `query`: The SQL, with `$1`, `$2` and so on where the parameters go.

#### Returns

- `EXTERNAL-ADDRESS`: A result whose status says whether the statement was prepared. Clear it with `pq-clear`.

### `pq-exec-prepared`

```clips
(pq-exec-prepared ?conn ?statement-name [?params])
```

Runs a statement prepared with `pq-prepare` and waits for the result. The
parameters are a multifield, exactly as in `pq-exec-params`.

In C:

```c
PGresult *PQexecPrepared(PGconn *conn,
                         const char *stmtName,
                         int nParams,
                         const char * const *paramValues,
                         const int *paramLengths,
                         const int *paramFormats,
                         int resultFormat);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `STRING`/`SYMBOL` `statement-name`: The name the statement was prepared under.

- `MULTIFIELD` `params` (optional): Optional. The parameter values, in order. `nil` is SQL NULL.

#### Returns

- `EXTERNAL-ADDRESS`: The result. Clear it with `pq-clear`.

### `pq-describe-prepared`

```clips
(pq-describe-prepared ?conn ?statement-name)
```

Asks the server about a prepared statement: the number of its parameters and
their types, from `pq-nparams` and `pq-paramtype`, and the columns it will
return, from the column functions.

In C:

```c
PGresult *PQdescribePrepared(PGconn *conn, const char *stmtName);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `STRING`/`SYMBOL` `statement-name`: The name the statement was prepared under, or the empty string for the unnamed statement.

#### Returns

- `EXTERNAL-ADDRESS`: A result carrying the description. Clear it with `pq-clear`.

### `pq-describe-portal`

```clips
(pq-describe-portal ?conn ?portal-name)
```

Asks the server about a portal -- what a cursor is on the wire -- returning a
result that describes the columns it will produce.

In C:

```c
PGresult *PQdescribePortal(PGconn *conn, const char *portalName);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `STRING`/`SYMBOL` `portal-name`: The portal to describe, or the empty string for the unnamed portal.

#### Returns

- `EXTERNAL-ADDRESS`: A result carrying the description. Clear it with `pq-clear`.

### `pq-close-prepared`

```clips
(pq-close-prepared ?conn ?statement-name)
```

Closes a prepared statement, freeing what the server was holding for it.
Closing a name that was never prepared is not an error: the point of the call
is that the name is free afterwards.

**Requires PostgreSQL 17 or later.** Built against an older libpq, this function is not defined at all; `pq-built-version` is how a program asks.

In C:

```c
PGresult *PQclosePrepared(PGconn *conn, const char *stmtName);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `STRING`/`SYMBOL` `statement-name`: The statement to close.

#### Returns

- `EXTERNAL-ADDRESS`: A result whose status says what happened. Clear it with `pq-clear`.

### `pq-close-portal`

```clips
(pq-close-portal ?conn ?portal-name)
```

Closes a portal, freeing what the server was holding for it. As with
`pq-close-prepared`, closing one that is not there is not an error.

**Requires PostgreSQL 17 or later.** Built against an older libpq, this function is not defined at all; `pq-built-version` is how a program asks.

In C:

```c
PGresult *PQclosePortal(PGconn *conn, const char *portalName);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `STRING`/`SYMBOL` `portal-name`: The portal to close.

#### Returns

- `EXTERNAL-ADDRESS`: A result whose status says what happened. Clear it with `pq-clear`.

### `pq-make-empty-pgresult`

```clips
(pq-make-empty-pgresult ?conn ?status)
```

Builds a result object with a status of the caller's choosing and nothing in
it, for a program that wants to hand back a result of its own.

In C:

```c
PGresult *PQmakeEmptyPGresult(PGconn *conn, ExecStatusType status);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`: The connection to take the error settings from.

- `INTEGER`/`STRING`/`SYMBOL` `status`: The status the result should have, as the symbol or the integer.

#### Returns

- `EXTERNAL-ADDRESS`: The result. Clear it with `pq-clear`, like any other.

### `pq-clear`

```clips
(pq-clear ?res)
```

Frees the storage of a result.

Every result has to be cleared when it is finished with, or the memory it
holds is leaked for as long as the process runs. As with `pq-finish`, the
handle is emptied, so a second clear is refused rather than freeing the same
memory twice.

In C:

```c
void PQclear(PGresult *res);
```

#### Arguments

- `EXTERNAL-ADDRESS` `res`

#### Returns

- `BOOLEAN`: `TRUE`. `FALSE` if the handle was not a result, or had already been cleared.


## Retrieving Query Result Information

### `pq-result-status`

```clips
(pq-result-status ?res)
```

Returns the result status of the command.

`pq-result-status` can return one of the following values:

- **`PGRES_EMPTY_QUERY`**: The string sent to the server was empty.

- **`PGRES_COMMAND_OK`**: Successful completion of a command returning no data.

- **`PGRES_TUPLES_OK`**: Successful completion of a command returning data (such as a `SELECT` or `SHOW`).

- **`PGRES_COPY_OUT`**: Copy Out (from server) data transfer started.

- **`PGRES_COPY_IN`**: Copy In (to server) data transfer started.

- **`PGRES_BAD_RESPONSE`**: The server's response was not understood.

- **`PGRES_NONFATAL_ERROR`**: A nonfatal error (a notice or warning) occurred.

- **`PGRES_FATAL_ERROR`**: A fatal error occurred.

- **`PGRES_COPY_BOTH`**: Copy In/Out (to and from server) data transfer started. This feature is currently used only for streaming replication, so this status should not occur in ordinary applications.

- **`PGRES_SINGLE_TUPLE`**: The `PGresult` contains a single result tuple from the current command. This status occurs only when single-row mode has been selected for the query (see [Retrieving Query Results in Chunks](https://www.postgresql.org/docs/18/libpq-single-row-mode.html)).

- **`PGRES_TUPLES_CHUNK`**: The `PGresult` contains several result tuples from the current command. This status occurs only when chunked mode has been selected for the query (see [Retrieving Query Results in Chunks](https://www.postgresql.org/docs/18/libpq-single-row-mode.html)). The number of tuples will not exceed the limit passed to `pq-set-chunked-rows-mode`.

- **`PGRES_PIPELINE_SYNC`**: The `PGresult` represents a synchronization point in pipeline mode, requested by either `pq-pipeline-sync` or `pq-send-pipeline-sync`. This status occurs only when pipeline mode has been selected.

- **`PGRES_PIPELINE_ABORTED`**: The `PGresult` represents a pipeline that has received an error from the server. `pq-get-result` must be called repeatedly, and each time it will return this status code until the end of the current pipeline, at which point it will return `PGRES_PIPELINE_SYNC` and normal processing can resume.

If the result status is `PGRES_TUPLES_OK`, `PGRES_SINGLE_TUPLE`, or `PGRES_TUPLES_CHUNK`, then the functions described below can be used to retrieve the rows returned by the query. Note that a `SELECT` command that happens to retrieve zero rows still shows `PGRES_TUPLES_OK`. `PGRES_COMMAND_OK` is for commands that can never return rows (`INSERT` or `UPDATE` without a `RETURNING` clause, etc.). A response of `PGRES_EMPTY_QUERY` might indicate a bug in the client software.

A result of status `PGRES_NONFATAL_ERROR` will never be returned directly by `pq-exec` or other query execution functions; results of this kind are instead passed to the notice processor (see [Notice Processing](https://www.postgresql.org/docs/18/libpq-notice-processing.html)).

In C:

```c
ExecStatusType PQresultStatus(const PGresult *res);
```

#### Arguments

- `EXTERNAL-ADDRESS` `res`

#### Returns

- `SYMBOL`: One of `PGRES_EMPTY_QUERY`, `PGRES_COMMAND_OK`, `PGRES_TUPLES_OK`, `PGRES_COPY_OUT`, `PGRES_COPY_IN`, `PGRES_COPY_BOTH`, `PGRES_BAD_RESPONSE`, `PGRES_NONFATAL_ERROR`, `PGRES_FATAL_ERROR`, `PGRES_SINGLE_TUPLE`, `PGRES_TUPLES_CHUNK`, `PGRES_PIPELINE_SYNC` or `PGRES_PIPELINE_ABORTED`.

### `pq-res-status`

```clips
(pq-res-status ?status)
```

Returns the name of a result status, for a message that has to name one. It
takes the status rather than the result, so it can be asked about a status
that no result has.

In C:

```c
char *PQresStatus(ExecStatusType status);
```

#### Arguments

- `INTEGER`/`STRING`/`SYMBOL` `status`: A result status, as the symbol or the integer behind it.

#### Returns

- `STRING`: The name of the status, as C spells it.

### `pq-result-error-message`

```clips
(pq-result-error-message ?res)
```

Returns the error message associated with a result, or `FALSE` for a result
that carries none -- which is every result of a command that succeeded.

Unlike `pq-error-message`, this belongs to the result and does not change, so
it can be read at any time while the result is alive.

In C:

```c
char *PQresultErrorMessage(const PGresult *res);
```

#### Arguments

- `EXTERNAL-ADDRESS` `res`

#### Returns

- `STRING`: The message, ending in a newline, or `FALSE` if there is none.

### `pq-result-verbose-error-message`

```clips
(pq-result-verbose-error-message ?res ?verbosity ?show-context)
```

Returns the error message of a result at a chosen verbosity, whatever
verbosity the connection had when the result was produced.

In C:

```c
char *PQresultVerboseErrorMessage(const PGresult *res,
                                  PGVerbosity verbosity,
                                  PGContextVisibility show_context);
```

#### Arguments

- `EXTERNAL-ADDRESS` `res`

- `INTEGER`/`STRING`/`SYMBOL` `verbosity`: `PQERRORS_TERSE`, `PQERRORS_DEFAULT`, `PQERRORS_VERBOSE` or `PQERRORS_SQLSTATE`.

- `INTEGER`/`STRING`/`SYMBOL` `show-context`: `PQSHOW_CONTEXT_NEVER`, `PQSHOW_CONTEXT_ERRORS` or `PQSHOW_CONTEXT_ALWAYS`.

#### Returns

- `STRING`: The message.

### `pq-result-error-field`

```clips
(pq-result-error-field ?res ?fieldcode)
```

The SQLSTATE code for the error. The SQLSTATE code identifies the type of error that has occurred; it can be used by front-end applications to perform specific operations (such as error handling) in response to a particular database error. For a list of the possible SQLSTATE codes, see [errcodes appendix](https://www.postgresql.org/docs/18/errcodes-appendix.html). This field is not localizable, and is always present.

The primary human-readable error message (typically one line). Always present.

Detail: an optional secondary error message carrying more detail about the problem. Might run to multiple lines.

Hint: an optional suggestion what to do about the problem. This is intended to differ from detail in that it offers advice (potentially inappropriate) rather than hard facts. Might run to multiple lines.

A string containing a decimal integer indicating an error cursor position as an index into the original statement string. The first character has index 1, and positions are measured in characters not bytes.

This is defined the same as the `PG_DIAG_STATEMENT_POSITION` field, but it is used when the cursor position refers to an internally generated command rather than the one submitted by the client. The `PG_DIAG_INTERNAL_QUERY` field will always appear when this field appears.

The text of a failed internally-generated command. This could be, for example, an SQL query issued by a PL/pgSQL function.

An indication of the context in which the error occurred. Presently this includes a call stack traceback of active procedural language functions and internally-generated queries. The trace is one entry per line, most recent first.

If the error was associated with a specific database object, the name of the schema containing that object, if any.

If the error was associated with a specific table, the name of the table. (Refer to the schema name field for the name of the table's schema.)

If the error was associated with a specific table column, the name of the column. (Refer to the schema and table name fields to identify the table.)

If the error was associated with a specific data type, the name of the data type. (Refer to the schema name field for the name of the data type's schema.)

If the error was associated with a specific constraint, the name of the constraint. Refer to fields listed above for the associated table or domain. (For this purpose, indexes are treated as constraints, even if they weren't created with constraint syntax.)

The file name of the source-code location where the error was reported.

The line number of the source-code location where the error was reported.

The name of the source-code function reporting the error.

> **Note**
>
> The fields for schema name, table name, column name, data type name, and constraint name are supplied only for a limited number of error types; see [errcodes appendix](https://www.postgresql.org/docs/18/errcodes-appendix.html). Do not assume that the presence of any of these fields guarantees the presence of another field. Core error sources observe the interrelationships noted above, but user-defined functions may use these fields in other ways. In the same vein, do not assume that these fields denote contemporary objects in the current database.

The client is responsible for formatting displayed information to meet its needs; in particular it should break long lines as needed. Newline characters appearing in the error message fields should be treated as paragraph breaks, not line breaks.

Errors generated internally by libpq will have severity and primary message, but typically no other fields.

Note that error fields are only available from `PGresult` objects, not `PGconn` objects; there is no `PQerrorField` function.

In C:

```c
char *PQresultErrorField(const PGresult *res, int fieldcode);
```

#### Arguments

- `EXTERNAL-ADDRESS` `res`

- `INTEGER`/`STRING`/`SYMBOL` `fieldcode`: The field to read, as one of the `PG_DIAG_*` symbols or the character code behind it.

#### Returns

- `STRING`: The field, or `FALSE` when the report does not include it. Not every field is present in every report.

### `pq-ntuples`

```clips
(pq-ntuples ?res)
```

Returns the number of rows (tuples) in the query result. (Note that `PGresult` objects are limited to no more than `INT_MAX` rows, so an `int` result is sufficient.)

In C:

```c
int PQntuples(const PGresult *res);
```

#### Arguments

- `EXTERNAL-ADDRESS` `res`

#### Returns

- `INTEGER`

### `pq-nfields`

```clips
(pq-nfields ?res)
```

Returns the number of columns (fields) in each row of the query result.

In C:

```c
int PQnfields(const PGresult *res);
```

#### Arguments

- `EXTERNAL-ADDRESS` `res`

#### Returns

- `INTEGER`

### `pq-fname`

```clips
(pq-fname ?res ?column-number)
```

Returns the column name associated with the given column number. Column numbers start at 0. The caller should not free the result directly. It will be freed when the associated `PGresult` handle is passed to `pq-clear`.

`NULL` is returned if the column number is out of range.

In C:

```c
char *PQfname(const PGresult *res,
              int column_number);
```

#### Arguments

- `EXTERNAL-ADDRESS` `res`

- `INTEGER` `column-number`

#### Returns

- `STRING`

### `pq-fnumber`

```clips
(pq-fnumber ?res ?column-name)
```

Returns the number of the column with a given name.

The name is matched the way SQL matches an identifier: an unquoted name is
folded to lower case, and a name in double quotes is matched exactly.

In C:

```c
int PQfnumber(const PGresult *res,
              const char *column_name);
```

#### Arguments

- `EXTERNAL-ADDRESS` `res`

- `STRING`/`SYMBOL` `column-name`: The name to look for.

#### Returns

- `INTEGER`: The column number, counting from zero, or `-1` when the result has no such column.

### `pq-ftable`

```clips
(pq-ftable ?res ?column-number)
```

Returns the OID of the table a column was selected from.

In C:

```c
Oid PQftable(const PGresult *res,
             int column_number);
```

#### Arguments

- `EXTERNAL-ADDRESS` `res`

- `INTEGER` `column-number`

#### Returns

- `INTEGER`: The table's OID, or `FALSE` when the column is not a simple reference to a table column, which is the case for anything computed.

### `pq-ftablecol`

```clips
(pq-ftablecol ?res ?column-number)
```

Returns the number of a column within the table it was selected from,
counting from one, as PostgreSQL numbers table columns.

In C:

```c
int PQftablecol(const PGresult *res,
                int column_number);
```

#### Arguments

- `EXTERNAL-ADDRESS` `res`

- `INTEGER` `column-number`

#### Returns

- `INTEGER`: The column's number in its table, or `FALSE` when the column is not a simple reference to a table column.

### `pq-fformat`

```clips
(pq-fformat ?res ?column-number)
```

Returns the format code indicating the format of the given column. Column numbers start at 0.

Format code zero indicates textual data representation, while format code one indicates binary representation. (Other codes are reserved for future definition.)

In C:

```c
int PQfformat(const PGresult *res,
              int column_number);
```

#### Arguments

- `EXTERNAL-ADDRESS` `res`

- `INTEGER` `column-number`

#### Returns

- `INTEGER`

### `pq-ftype`

```clips
(pq-ftype ?res ?column-number)
```

Returns the data type associated with the given column number. The integer returned is the internal OID number of the type. Column numbers start at 0.

You can query the system table `pg_type` to obtain the names and properties of the various data types. The OIDs of the built-in data types are defined in the file `catalog/pg_type_d.h` in the PostgreSQL installation's `include` directory.

In C:

```c
Oid PQftype(const PGresult *res,
            int column_number);
```

#### Arguments

- `EXTERNAL-ADDRESS` `res`

- `INTEGER` `column-number`

#### Returns

- `INTEGER`

### `pq-fmod`

```clips
(pq-fmod ?res ?column-number)
```

Returns the type modifier of the column associated with the given column number. Column numbers start at 0.

The interpretation of modifier values is type-specific; they typically indicate precision or size limits. The value -1 is used to indicate "no information available". Most data types do not use modifiers, in which case the value is always -1.

In C:

```c
int PQfmod(const PGresult *res,
           int column_number);
```

#### Arguments

- `EXTERNAL-ADDRESS` `res`

- `INTEGER` `column-number`

#### Returns

- `INTEGER`

### `pq-fsize`

```clips
(pq-fsize ?res ?column-number)
```

Returns the size in bytes of the column associated with the given column number. Column numbers start at 0.

`pq-fsize` returns the space allocated for this column in a database row, in other words the size of the server's internal representation of the data type. (Accordingly, it is not really very useful to clients.) A negative value indicates the data type is variable-length.

In C:

```c
int PQfsize(const PGresult *res,
            int column_number);
```

#### Arguments

- `EXTERNAL-ADDRESS` `res`

- `INTEGER` `column-number`

#### Returns

- `INTEGER`

### `pq-binary-tuples`

```clips
(pq-binary-tuples ?res)
```

Answers `TRUE` if the `PGresult` contains binary data and 0 if it contains text data.

This function is deprecated (except for its use in connection with `COPY`), because it is possible for a single `PGresult` to contain text data in some columns and binary data in others. `pq-fformat` is preferred. `pq-binary-tuples` answers `TRUE` only if all columns of the result are binary (format 1).

In C:

```c
int PQbinaryTuples(const PGresult *res);
```

#### Arguments

- `EXTERNAL-ADDRESS` `res`

#### Returns

- `BOOLEAN`

### `pq-getvalue`

```clips
(pq-getvalue ?res ?row-number ?column-number)
```

Returns one field of one row of a result.

A field that is SQL NULL comes back as the symbol `nil` rather than as the
empty string, so that a NULL and an empty value can be told apart without a
second call; `pq-getisnull` is still there for a caller that would rather ask.

Values arrive as the text PostgreSQL printed. The row mappers --
`pq-row-to-multifield` and the two beside it -- are what convert a whole row
to CLIPS types in one call.

In C:

```c
char *PQgetvalue(const PGresult *res,
                 int row_number,
                 int column_number);
```

#### Arguments

- `EXTERNAL-ADDRESS` `res`

- `INTEGER` `row-number`: The row, counting from zero.

- `INTEGER` `column-number`: The column, counting from zero.

#### Returns

- `STRING`: The field's text, or the symbol `nil` if it is SQL NULL.

### `pq-getisnull`

```clips
(pq-getisnull ?res ?row-number ?column-number)
```

Returns whether one field of one row is SQL NULL.

In C:

```c
int PQgetisnull(const PGresult *res,
                int row_number,
                int column_number);
```

#### Arguments

- `EXTERNAL-ADDRESS` `res`

- `INTEGER` `row-number`: The row, counting from zero.

- `INTEGER` `column-number`: The column, counting from zero.

#### Returns

- `BOOLEAN`: `TRUE` if the field is NULL.

### `pq-getlength`

```clips
(pq-getlength ?res ?row-number ?column-number)
```

Returns the length in bytes of one field of one row, which for a text value
is the length of the string and for a binary one the size of the datum.

In C:

```c
int PQgetlength(const PGresult *res,
                int row_number,
                int column_number);
```

#### Arguments

- `EXTERNAL-ADDRESS` `res`

- `INTEGER` `row-number`: The row, counting from zero.

- `INTEGER` `column-number`: The column, counting from zero.

#### Returns

- `INTEGER`: The length in bytes. Zero for a NULL field.

### `pq-nparams`

```clips
(pq-nparams ?res)
```

Returns the number of parameters of a prepared statement.

This function is only useful when inspecting the result of `pq-describe-prepared`. For other types of results it will return zero.

In C:

```c
int PQnparams(const PGresult *res);
```

#### Arguments

- `EXTERNAL-ADDRESS` `res`

#### Returns

- `INTEGER`

### `pq-paramtype`

```clips
(pq-paramtype ?res ?param-number)
```

Returns the data type of the indicated statement parameter. Parameter numbers start at 0.

This function is only useful when inspecting the result of `pq-describe-prepared`. For other types of results it will return zero.

In C:

```c
Oid PQparamtype(const PGresult *res, int param_number);
```

#### Arguments

- `EXTERNAL-ADDRESS` `res`

- `INTEGER` `param-number`

#### Returns

- `INTEGER`


## Retrieving Other Result Information

### `pq-cmd-status`

```clips
(pq-cmd-status ?res)
```

Returns the command status tag from the SQL command that generated the `PGresult`.

Commonly this is just the name of the command, but it might include additional data such as the number of rows processed. The caller should not free the result directly. It will be freed when the associated `PGresult` handle is passed to `pq-clear`.

In C:

```c
char *PQcmdStatus(PGresult *res);
```

#### Arguments

- `EXTERNAL-ADDRESS` `res`

#### Returns

- `STRING`

### `pq-cmd-tuples`

```clips
(pq-cmd-tuples ?res)
```

Returns the number of rows the command affected.

libpq reports this as a string, and it is an integer here: `INSERT`, `UPDATE`,
`DELETE`, `MERGE`, `MOVE`, `FETCH` and `COPY` all count rows, and `SELECT`
reports the number it returned.

In C:

```c
char *PQcmdTuples(PGresult *res);
```

#### Arguments

- `EXTERNAL-ADDRESS` `res`

#### Returns

- `INTEGER`: The number of rows, or `FALSE` for a command that counts none.

### `pq-oid-value`

```clips
(pq-oid-value ?res)
```

Returns the OID of the row an `INSERT` inserted.

Tables have not had OIDs since PostgreSQL 12, so this is `FALSE` for every
ordinary insert. A statement that needs the identifier of what it inserted
should use `INSERT ... RETURNING` instead.

In C:

```c
Oid PQoidValue(const PGresult *res);
```

#### Arguments

- `EXTERNAL-ADDRESS` `res`

#### Returns

- `INTEGER`: The OID, or `FALSE` when the statement inserted no row into a table with OIDs.

### `pq-result-memory-size`

```clips
(pq-result-memory-size ?res)
```

Retrieves the number of bytes allocated for a `PGresult` object.

This value is the sum of all `malloc` requests associated with the `PGresult` object, that is, all the memory that will be freed by `pq-clear`. This information can be useful for managing memory consumption.

In C:

```c
size_t PQresultMemorySize(const PGresult *res);
```

#### Arguments

- `EXTERNAL-ADDRESS` `res`

#### Returns

- `INTEGER`


## Escaping Strings for Inclusion in SQL Commands

### `pq-escape-literal`

```clips
(pq-escape-literal ?conn ?str)
```

Escapes a string for use as a literal inside an SQL command, and puts the
quotes on it.

The result is ready to be concatenated into a command as it stands -- adding
quotes around it would be wrong. A parameter is still the better way to get a
value into a query; this is for the cases where a parameter cannot go, and
for building an identifier's default.

```clips
(str-cat "SELECT * FROM widgets WHERE name = " (pq-escape-literal ?conn ?name))
```

In C:

```c
char *PQescapeLiteral(PGconn *conn, const char *str, size_t length);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `STRING`/`SYMBOL` `str`: The text to escape.

#### Returns

- `STRING`: The escaped and quoted literal.

### `pq-escape-identifier`

```clips
(pq-escape-identifier ?conn ?str)
```

Escapes a string for use as an SQL identifier -- a table or column name --
and puts the double quotes on it.

In C:

```c
char *PQescapeIdentifier(PGconn *conn, const char *str, size_t length);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `STRING`/`SYMBOL` `str`: The identifier to escape.

#### Returns

- `STRING`: The escaped and quoted identifier.

### `pq-escape-string-conn`

```clips
(pq-escape-string-conn ?conn ?from)
```

Escapes a string for use inside an SQL literal, without adding the quotes.
`pq-escape-literal` is the one to use for new code; this is here because so
much existing SQL is built around it.

In C:

```c
size_t PQescapeStringConn(PGconn *conn,
                          char *to, const char *from, size_t length,
                          int *error);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `STRING`/`SYMBOL` `from`: The text to escape.

#### Returns

- `STRING`: The escaped text, with no quotes around it.

### `pq-escape-bytea-conn`

```clips
(pq-escape-bytea-conn ?conn ?from)
```

Escapes binary data for use inside a `bytea` literal, in the format the
server's `standard_conforming_strings` setting calls for.

The data may be a multifield of byte values from 0 to 255, which is how a
`bytea` crosses in the other direction, or a string, for the common case of
text going into a `bytea` column.

In C:

```c
unsigned char *PQescapeByteaConn(PGconn *conn,
                                 const unsigned char *from,
                                 size_t from_length,
                                 size_t *to_length);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `STRING`/`MULTIFIELD`/`SYMBOL` `from`: The bytes, as a multifield of integers from 0 to 255, or a string.

#### Returns

- `STRING`: The escaped text, ready to be concatenated into a command.

### `pq-unescape-bytea`

```clips
(pq-unescape-bytea ?from)
```

Converts the text form of a `bytea` -- what the server prints for one, and
what `pq-escape-bytea-conn` produces -- back into the bytes it stands for.

The bytes come back as a multifield of integers so that a zero byte in the
middle of the data is a field like any other rather than the end of a string.

In C:

```c
unsigned char *PQunescapeBytea(const unsigned char *from, size_t *to_length);
```

#### Arguments

- `STRING`/`SYMBOL` `from`: The escaped text.

#### Returns

- `MULTIFIELD`: The bytes, one integer from 0 to 255 each.


## Rows as CLIPS Data

These nine have no counterpart in libpq. Everything else in this reference
is a function of the C API; these are the conversion the C API leaves to its
caller, done once here. The first three take one row and the other six take
every row of a result, or run the command and take every row of its result.

### `pq-row-to-multifield`

```clips
(pq-row-to-multifield ?res ?row-number)
```

Returns one row of a result as a multifield, one field per column, each
converted to the CLIPS type its PostgreSQL type calls for.

The integers become integers, `real`, `double precision` and `numeric` become
floats, `boolean` becomes `TRUE` or `FALSE`, SQL NULL becomes the symbol
`nil`, and everything else keeps the text PostgreSQL printed. `numeric` is the
conversion to watch: a value too precise for a double loses that precision,
and `pq-getvalue` is how to keep it exact.

```clips
(pq-row-to-multifield ?res 0)     ; (1 2.5 "bolt" nil TRUE)
```

#### Arguments

- `EXTERNAL-ADDRESS` `res`: The result to read from.

- `INTEGER` `row-number`: The row, counting from zero.

#### Returns

- `MULTIFIELD`: The row's values in column order.

### `pq-row-to-fact`

```clips
(pq-row-to-fact ?res ?row-number ?deftemplate)
```

Asserts one row of a result as a fact of a deftemplate, taking the column
names as slot names and converting each value as `pq-row-to-multifield` does.

The deftemplate must have a slot for every column of the row: a column with
nowhere to go is a refusal, not a value quietly dropped. The template is
usually written next to the query it is filled from, since the two have to
agree about the column names.

```clips
(deftemplate widget (slot id) (slot name) (slot weight))

(bind ?res (pq-exec ?conn "SELECT id, name, weight FROM widgets"))
(bind ?end (- (pq-ntuples ?res) 1))
(loop-for-count (?row 0 ?end)
  (pq-row-to-fact ?res ?row widget))
(pq-clear ?res)
```

#### Arguments

- `EXTERNAL-ADDRESS` `res`: The result to read from.

- `INTEGER` `row-number`: The row, counting from zero.

- `SYMBOL` `deftemplate`: The name of the deftemplate to assert.

#### Returns

- `FACT-ADDRESS`: The asserted fact.

### `pq-row-to-instance`

```clips
(pq-row-to-instance ?res ?row-number ?defclass [?instance-name] [?name-slot])
```

Makes an instance of a defclass from one row of a result, taking the column
names as slot names and converting each value as `pq-row-to-multifield` does.

As with `pq-row-to-fact`, the class must have a slot for every column of the
row. An instance's name is not a slot, so a column called `name` has nowhere
to go: it is written to the slot `_name`, or to whichever slot the fifth
argument names.

#### Arguments

- `EXTERNAL-ADDRESS` `res`: The result to read from.

- `INTEGER` `row-number`: The row, counting from zero.

- `SYMBOL` `defclass`: The name of the defclass to make an instance of.

- `SYMBOL` `instance-name` (optional): Optional. The name for the instance; `nil` leaves CLIPS to make one up, which is what a loop over rows wants.

- `SYMBOL` `name-slot` (optional): Optional. The slot a column called `name` is written to. Defaults to `_name`.

#### Returns

- `INSTANCE-ADDRESS`: The new instance.

### `pq-result-to-multifields`

```clips
(pq-result-to-multifields ?res [?headers])
```

Answers every row of a result as one flat multifield: the values row by
row, each converted as `pq-row-to-multifield` converts them. Pass `TRUE` for
`headers` to put the column names, as strings, in front of them.

```clips
(pq-result-to-multifields ?res)         ; (1 "widget" 2 "gadget")
(pq-result-to-multifields ?res TRUE)    ; ("id" "product" 1 "widget" 2 "gadget")
```

Every row contributes one field per column, so the stride is the column
count. A result with no rows answers an empty multifield, or its header alone
when one was asked for.

The result is read in place and is still there afterwards: it is the caller's
to clear.

#### Arguments

- `EXTERNAL-ADDRESS` `res`: The result to read.

- `BOOLEAN` `headers` (optional): Optional. `TRUE` to put the column names in front of the values. Defaults to `FALSE`; anything that is neither is refused.

#### Returns

- `MULTIFIELD`: The values row by row, preceded by the column names when `headers` is `TRUE`.

### `pq-result-to-facts`

```clips
(pq-result-to-facts ?res ?deftemplate)
```

Asserts one fact per row of a result and answers their fact addresses in row
order. Each column name is a slot name on the deftemplate, and each value is
converted as `pq-row-to-multifield` converts it.

Unlike `pq-row-to-fact`, a column with no slot to go in is passed over rather
than refused: the query decides what it selects and the deftemplate decides
what it holds, and neither has to be a subset of the other. Which columns
land is decided once, before the first row is read. When *no* column matches,
every row builds the same empty fact and CLIPS collapses the duplicates into
one.

A row a slot refuses -- a value outside the slot's type, range or allowed
values -- is skipped, reported once on `STDERR`, and the rows around it still
land. A row that is already in working memory answers the fact that already
holds it, so a result converted twice answers the same addresses twice while
working memory does not grow.

```clips
(deftemplate widget (slot id) (slot name) (slot weight))

(bind ?res (pq-exec ?conn "SELECT id, name, weight FROM widgets"))
(bind ?facts (pq-result-to-facts ?res widget))
(pq-clear ?res)
```

The result is read in place and is still there afterwards: it is the caller's
to clear. `pq-exec-to-facts` runs the query and does all of that in one call.

#### Arguments

- `EXTERNAL-ADDRESS` `res`: The result whose rows become facts.

- `STRING`/`SYMBOL` `deftemplate`: The name of the deftemplate to assert. Columns naming one of its slots fill that slot; the rest are passed over.

#### Returns

- `MULTIFIELD`: One fact address per row that was made, in row order.

### `pq-result-to-instances`

```clips
(pq-result-to-instances ?res ?defclass [?instance-names])
```

Makes one instance per row of a result and answers their instance addresses
in row order. Each column name is a slot name on the defclass, inherited
slots included, and each value is converted as `pq-row-to-multifield`
converts it.

Columns with no slot are passed over and rows a slot refuses are skipped,
exactly as for `pq-result-to-facts`. An instance's name is not a slot, so a
column called `name` goes to the slot `_name`, as it does for
`pq-row-to-instance`. Unlike facts, instances are not deduplicated: a result
converted twice makes two sets.

The instances are named by CLIPS unless `instance-names` says otherwise. That
argument is positional -- the nth name goes to the nth row -- and a row past
the end of the list is named by CLIPS, which is what every row gets when the
argument is left out. A single symbol, string or instance name names the
first row and nothing else.

```clips
(pq-result-to-instances ?res WIDGET (create$ first second third))
;; ([first] [second] [third])
```

Reusing a name is CLIPS's own rule: an instance of the same class that
already holds the name is replaced, and a name held by an instance of another
class loses that row, which is skipped and reported like any other.

#### Arguments

- `EXTERNAL-ADDRESS` `res`: The result whose rows become instances.

- `STRING`/`SYMBOL` `defclass`: The name of the defclass to instantiate. Columns naming one of its slots fill that slot; the rest are passed over.

- `MULTIFIELD`/`INSTANCE-NAME`/`STRING`/`SYMBOL` `instance-names` (optional): Optional. What to call the instances, in row order: a multifield of names, or one name for the first row. Rows the list does not reach are named by CLIPS.

#### Returns

- `MULTIFIELD`: One instance address per row that was made, in row order.

### `pq-exec-to-multifields`

```clips
(pq-exec-to-multifields ?conn ?command [?headers])
```

Runs a command and answers its rows as one flat multifield, as
`pq-result-to-multifields` would, clearing the result before it returns.

```clips
(pq-exec-to-multifields ?conn "SELECT id, product FROM orders")
;; (1 "widget" 2 "gadget")

(pq-exec-to-multifields ?conn "SELECT id, product FROM orders" TRUE)
;; ("id" "product" 1 "widget" 2 "gadget")
```

A command the server refuses answers `FALSE` with the server's message,
where `pq-exec` would answer a result whose status says so. A command that
produces no rows at all answers an empty multifield.

#### Arguments

- `EXTERNAL-ADDRESS` `conn`: The connection to run the command on.

- `STRING`/`SYMBOL` `command`: The SQL to run.

- `BOOLEAN` `headers` (optional): Optional. `TRUE` to put the column names in front of the values. Defaults to `FALSE`.

#### Returns

- `MULTIFIELD`: The values row by row, preceded by the column names when `headers` is `TRUE`.

### `pq-exec-to-facts`

```clips
(pq-exec-to-facts ?conn ?command [?deftemplate])
```

Runs a command, asserts one fact per row, and answers the fact addresses in
row order, clearing the result before it returns. The facts are in working
memory when the call comes back.

```clips
(deftemplate orders (slot id) (slot product) (slot amount))

(pq-exec-to-facts ?conn "SELECT id, product, amount FROM orders")
```

The deftemplate is optional. Left out, it is the name of the one table the
result's columns come from, which the server reports for every column that
is a plain reference to a table column; a computed column says nothing and is
not counted, so an aggregate over one table still infers that table. A result
whose columns come from no table, or from more than one, has no single name to
infer and is refused: name the deftemplate for those.

Column names are slot names, so a SQL alias is how a column and a slot are
made to agree:

```clips
(pq-exec-to-facts ?conn "SELECT customer AS id, count(*) AS orders
                         FROM sales GROUP BY customer" customer)
```

A command the server refuses answers `FALSE` with the server's message. In
every other respect as `pq-result-to-facts`, which this is a wrapper over.

#### Arguments

- `EXTERNAL-ADDRESS` `conn`: The connection to run the command on.

- `STRING`/`SYMBOL` `command`: The SQL to run.

- `STRING`/`SYMBOL` `deftemplate` (optional): Optional. The name of the deftemplate to assert. Defaults to the one table the result's columns come from.

#### Returns

- `MULTIFIELD`: One fact address per row that was made, in row order.

### `pq-exec-to-instances`

```clips
(pq-exec-to-instances ?conn ?command [?defclass] [?instance-names])
```

Runs a command, makes one instance per row, and answers the instance
addresses in row order, clearing the result before it returns.

The defclass is optional and inferred the way `pq-exec-to-facts` infers a
deftemplate, except that the table name is put in capitals: a query over
`orders` looks for `ORDERS`.

`instance-names` names the rows exactly as it does for
`pq-result-to-instances`. Because the defclass in front of it is itself
optional, a multifield in the third position is read as the names rather
than the class, and the class is inferred:

```clips
(pq-exec-to-instances ?conn "SELECT id, product FROM orders" (create$ newest))
;; ([newest] [gen1] [gen2])  -- class inferred as ORDERS
```

A bare symbol or string in that position is always a defclass name.

A command the server refuses answers `FALSE` with the server's message. In
every other respect as `pq-result-to-instances`.

#### Arguments

- `EXTERNAL-ADDRESS` `conn`: The connection to run the command on.

- `STRING`/`SYMBOL` `command`: The SQL to run.

- `MULTIFIELD`/`INSTANCE-NAME`/`STRING`/`SYMBOL` `defclass` (optional): Optional. The name of the defclass to instantiate. Defaults to the one table the result's columns come from, in capitals. A multifield here is the `instance-names` instead.

- `MULTIFIELD`/`INSTANCE-NAME`/`STRING`/`SYMBOL` `instance-names` (optional): Optional. What to call the instances, in row order: a multifield of names, or one name for the first row. Rows the list does not reach are named by CLIPS.

#### Returns

- `MULTIFIELD`: One instance address per row that was made, in row order.


## Asynchronous Command Processing

### `pq-send-query`

```clips
(pq-send-query ?conn ?command)
```

Submits a command without waiting for the result, which is then collected
with `pq-get-result`.

The connection will not take another command until every result of this one
has been read.

In C:

```c
int PQsendQuery(PGconn *conn, const char *command);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `STRING`/`SYMBOL` `command`: The SQL to run.

#### Returns

- `BOOLEAN`: `TRUE` if the command was sent. `FALSE` if it could not be, with libpq's reason on `STDERR`.

### `pq-send-query-params`

```clips
(pq-send-query-params ?conn ?command [?params])
```

Submits a command with parameters without waiting for the result. The
parameters are a multifield, exactly as in `pq-exec-params`.

In C:

```c
int PQsendQueryParams(PGconn *conn,
                      const char *command,
                      int nParams,
                      const Oid *paramTypes,
                      const char * const *paramValues,
                      const int *paramLengths,
                      const int *paramFormats,
                      int resultFormat);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `STRING`/`SYMBOL` `command`: The SQL to run, with `$1`, `$2` and so on where the parameters go.

- `MULTIFIELD` `params` (optional): Optional. The parameter values, in order. `nil` is SQL NULL.

#### Returns

- `BOOLEAN`: `TRUE` if the command was sent.

### `pq-send-prepare`

```clips
(pq-send-prepare ?conn ?statement-name ?query)
```

Prepares a statement without waiting for the result.

In C:

```c
int PQsendPrepare(PGconn *conn,
                  const char *stmtName,
                  const char *query,
                  int nParams,
                  const Oid *paramTypes);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `STRING`/`SYMBOL` `statement-name`: The name to prepare it under.

- `STRING`/`SYMBOL` `query`: The SQL, with `$1`, `$2` and so on where the parameters go.

#### Returns

- `BOOLEAN`: `TRUE` if the request was sent.

### `pq-send-query-prepared`

```clips
(pq-send-query-prepared ?conn ?statement-name [?params])
```

Runs a prepared statement without waiting for the result. The parameters are
a multifield, exactly as in `pq-exec-params`.

In C:

```c
int PQsendQueryPrepared(PGconn *conn,
                        const char *stmtName,
                        int nParams,
                        const char * const *paramValues,
                        const int *paramLengths,
                        const int *paramFormats,
                        int resultFormat);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `STRING`/`SYMBOL` `statement-name`: The name the statement was prepared under.

- `MULTIFIELD` `params` (optional): Optional. The parameter values, in order. `nil` is SQL NULL.

#### Returns

- `BOOLEAN`: `TRUE` if the command was sent.

### `pq-send-describe-prepared`

```clips
(pq-send-describe-prepared ?conn ?statement-name)
```

Submits a request to obtain information about the specified prepared statement, without waiting for completion. This is an asynchronous version of `pq-describe-prepared`: it answers `TRUE` if it was able to dispatch the request, and 0 if not. After a successful call, call `pq-get-result` to obtain the results. The function's parameters are handled identically to `pq-describe-prepared`.

In C:

```c
int PQsendDescribePrepared(PGconn *conn, const char *stmtName);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `STRING`/`SYMBOL` `statement-name`

#### Returns

- `BOOLEAN`

### `pq-send-describe-portal`

```clips
(pq-send-describe-portal ?conn ?portal-name)
```

Submits a request to obtain information about the specified portal, without waiting for completion. This is an asynchronous version of `pq-describe-portal`: it answers `TRUE` if it was able to dispatch the request, and 0 if not. After a successful call, call `pq-get-result` to obtain the results. The function's parameters are handled identically to `pq-describe-portal`.

In C:

```c
int PQsendDescribePortal(PGconn *conn, const char *portalName);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `STRING`/`SYMBOL` `portal-name`

#### Returns

- `BOOLEAN`

### `pq-send-close-prepared`

```clips
(pq-send-close-prepared ?conn ?statement-name)
```

Submits a request to close the specified prepared statement, without waiting for completion. This is an asynchronous version of `pq-close-prepared`: it answers `TRUE` if it was able to dispatch the request, and 0 if not. After a successful call, call `pq-get-result` to obtain the results. The function's parameters are handled identically to `pq-close-prepared`.

**Requires PostgreSQL 17 or later.** Built against an older libpq, this function is not defined at all; `pq-built-version` is how a program asks.

In C:

```c
int PQsendClosePrepared(PGconn *conn, const char *stmtName);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `STRING`/`SYMBOL` `statement-name`

#### Returns

- `BOOLEAN`

### `pq-send-close-portal`

```clips
(pq-send-close-portal ?conn ?portal-name)
```

Submits a request to close specified portal, without waiting for completion. This is an asynchronous version of `pq-close-portal`: it answers `TRUE` if it was able to dispatch the request, and 0 if not. After a successful call, call `pq-get-result` to obtain the results. The function's parameters are handled identically to `pq-close-portal`.

**Requires PostgreSQL 17 or later.** Built against an older libpq, this function is not defined at all; `pq-built-version` is how a program asks.

In C:

```c
int PQsendClosePortal(PGconn *conn, const char *portalName);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `STRING`/`SYMBOL` `portal-name`

#### Returns

- `BOOLEAN`

### `pq-get-result`

```clips
(pq-get-result ?conn)
```

Returns the next result of a command sent with one of the `pq-send-*`
functions, waiting for it if it has not arrived.

`FALSE` is how a command says it has no more results, which is the end of the
loop rather than a failure, and nothing is written to `STDERR` for it. A
command must be read to that point before the connection will take another.

```clips
(bind ?res (pq-get-result ?conn))
(while ?res
  ; ... use the result ...
  (pq-clear ?res)
  (bind ?res (pq-get-result ?conn)))
```

In C:

```c
PGresult *PQgetResult(PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `EXTERNAL-ADDRESS`: The next result, to be cleared with `pq-clear`, or `FALSE` when the command has no more.

### `pq-consume-input`

```clips
(pq-consume-input ?conn)
```

If input is available from the server, consume it.

`pq-consume-input` normally answers `TRUE` indicating "no error", but answers `FALSE` if there was some kind of trouble (in which case `pq-error-message` can be consulted). Note that the result does not say whether any input data was actually collected. After calling `pq-consume-input`, the application can check `pq-is-busy` and/or `pq-notifies` to see if their state has changed.

`pq-consume-input` can be called even if the application is not prepared to deal with a result or notification just yet. The function will read available data and save it in a buffer, thereby causing a `select()` read-ready indication to go away. The application can thus use `pq-consume-input` to clear the `select()` condition immediately, and then examine the results at leisure.

In C:

```c
int PQconsumeInput(PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `BOOLEAN`

### `pq-is-busy`

```clips
(pq-is-busy ?conn)
```

Returns whether a command is still in flight, which is to say whether
`pq-get-result` would block. Ask `pq-consume-input` for what has arrived
first, or this will keep saying the same thing.

In C:

```c
int PQisBusy(PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `BOOLEAN`: `TRUE` while the command is still busy.

### `pq-setnonblocking`

```clips
(pq-setnonblocking ?conn ?arg)
```

Sets the blocking state of the connection: in non-blocking mode a send that
would block queues the data and answers instead of waiting.

In C:

```c
int PQsetnonblocking(PGconn *conn, int arg);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `BOOLEAN` `arg`: `TRUE` for non-blocking, `FALSE` for blocking.

#### Returns

- `BOOLEAN`: `TRUE` if the state was changed.

### `pq-isnonblocking`

```clips
(pq-isnonblocking ?conn)
```

Returns the blocking status of the database connection.

Answers `TRUE` if the connection is set to nonblocking mode and 0 if blocking.

In C:

```c
int PQisnonblocking(const PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `BOOLEAN`

### `pq-flush`

```clips
(pq-flush ?conn)
```

Sends whatever is still queued on the connection.

On a blocking connection this either finishes or fails. On a non-blocking one
it may do neither: the socket would have blocked and some of the data is
still queued, which is the symbol `busy` and is not a failure.

In C:

```c
int PQflush(PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `SYMBOL`: `TRUE` when everything has been sent, the symbol `busy` when some of it is still queued, or `FALSE` on failure.

### `pq-set-single-row-mode`

```clips
(pq-set-single-row-mode ?conn)
```

Select single-row mode for the currently-executing query.

This function can only be called immediately after `pq-send-query` or one of its sibling functions, before any other operation on the connection such as `pq-consume-input` or `pq-get-result`. If called at the correct time, the function activates single-row mode for the current query and answers `TRUE`. Otherwise the mode stays unchanged and the function answers `FALSE`. In any case, the mode reverts to normal after completion of the current query.

In C:

```c
int PQsetSingleRowMode(PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `BOOLEAN`

### `pq-set-chunked-rows-mode`

```clips
(pq-set-chunked-rows-mode ?conn ?chunk-size)
```

Puts the connection into chunked-rows mode for the command just sent, so that
its rows arrive as a series of results of the given size rather than one
result holding all of them.

Each chunk comes back with the status `PGRES_TUPLES_CHUNK`, and the last one
is followed by a `PGRES_TUPLES_OK` result with no rows in it.

**Requires PostgreSQL 17 or later.** Built against an older libpq, this function is not defined at all; `pq-built-version` is how a program asks.

In C:

```c
int PQsetChunkedRowsMode(PGconn *conn, int chunkSize);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `INTEGER` `chunk-size`: How many rows each result should hold. Must be greater than zero.

#### Returns

- `BOOLEAN`: `TRUE` if the mode was set. `FALSE` if the connection was not in a state where it could be.

### `pq-socket-poll`

```clips
(pq-socket-poll ?sock ?for-read ?for-write ?end-time)
```

Waits until a socket is ready to be read from or written to, or until a
deadline passes. This is what a program that has nothing else to do between
polls uses in place of its own event loop.

The deadline is an absolute time in microseconds, which is what
`pq-get-current-time-usec` answers with; `-1` waits forever and `0` does not
wait at all.

```clips
(pq-socket-poll (pq-socket ?conn) TRUE FALSE
                (+ (pq-get-current-time-usec) 5000000))
```

**Requires PostgreSQL 17 or later.** Built against an older libpq, this function is not defined at all; `pq-built-version` is how a program asks.

In C:

```c
typedef int64_t pg_usec_time_t;

int PQsocketPoll(int sock, int forRead, int forWrite,
                 pg_usec_time_t end_time);
```

#### Arguments

- `INTEGER` `sock`: The file descriptor, from `pq-socket` or `pq-cancel-socket`.

- `BOOLEAN` `for-read`: `TRUE` to wait until it can be read from.

- `BOOLEAN` `for-write`: `TRUE` to wait until it can be written to.

- `INTEGER` `end-time`: The deadline, in microseconds since the epoch. `-1` to wait forever, `0` to return at once.

#### Returns

- `INTEGER`: Greater than zero when the socket is ready, zero when the deadline passed first, `FALSE` if the socket could not be polled.

### `pq-get-current-time-usec`

```clips
(pq-get-current-time-usec)
```

Returns the current time in microseconds since the epoch, in the form
`pq-socket-poll` takes as a deadline.

**Requires PostgreSQL 17 or later.** Built against an older libpq, this function is not defined at all; `pq-built-version` is how a program asks.

In C:

```c
pg_usec_time_t PQgetCurrentTimeUSec(void);
```

#### Returns

- `INTEGER`: The current time in microseconds.


## Pipeline Mode

### `pq-pipeline-status`

```clips
(pq-pipeline-status ?conn)
```

Returns whether the connection is in pipeline mode, and whether the current
pipeline has been aborted by a command that failed.

In C:

```c
PGpipelineStatus PQpipelineStatus(const PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `SYMBOL`: `PQ_PIPELINE_ON`, `PQ_PIPELINE_OFF` or `PQ_PIPELINE_ABORTED`.

### `pq-enter-pipeline-mode`

```clips
(pq-enter-pipeline-mode ?conn)
```

Causes a connection to enter pipeline mode if it is currently idle or already in pipeline mode.

Answers `TRUE` for success. Answers `FALSE` and has no effect if the connection is not currently idle, i.e., it has a result ready, or it is waiting for more input from the server, etc. This function does not actually send anything to the server, it just changes the libpq connection state.

In C:

```c
int PQenterPipelineMode(PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `BOOLEAN`

### `pq-exit-pipeline-mode`

```clips
(pq-exit-pipeline-mode ?conn)
```

Causes a connection to exit pipeline mode if it is currently in pipeline mode with an empty queue and no pending results.

Answers `TRUE` for success. Answers `TRUE` and takes no action if not in pipeline mode. If the current statement isn't finished processing, or `pq-get-result` has not been called to collect results from all previously sent query, answers `FALSE` (in which case, use `pq-error-message` to get more information about the failure).

In C:

```c
int PQexitPipelineMode(PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `BOOLEAN`

### `pq-pipeline-sync`

```clips
(pq-pipeline-sync ?conn)
```

Marks a synchronization point in a pipeline by sending a [sync message](https://www.postgresql.org/docs/18/protocol-flow.html#PROTOCOL-FLOW-EXT-QUERY) and flushing the send buffer. This serves as the delimiter of an implicit transaction and an error recovery point; see [Error Handling](https://www.postgresql.org/docs/18/libpq-pipeline-mode.html#LIBPQ-PIPELINE-ERRORS).

Answers `TRUE` for success. Answers `FALSE` if the connection is not in pipeline mode or sending a [sync message](https://www.postgresql.org/docs/18/protocol-flow.html#PROTOCOL-FLOW-EXT-QUERY) failed.

In C:

```c
int PQpipelineSync(PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `BOOLEAN`

### `pq-send-pipeline-sync`

```clips
(pq-send-pipeline-sync ?conn)
```

Marks a synchronization point in a pipeline by sending a [sync message](https://www.postgresql.org/docs/18/protocol-flow.html#PROTOCOL-FLOW-EXT-QUERY) without flushing the send buffer. This serves as the delimiter of an implicit transaction and an error recovery point; see [Error Handling](https://www.postgresql.org/docs/18/libpq-pipeline-mode.html#LIBPQ-PIPELINE-ERRORS).

Answers `TRUE` for success. Answers `FALSE` if the connection is not in pipeline mode or sending a [sync message](https://www.postgresql.org/docs/18/protocol-flow.html#PROTOCOL-FLOW-EXT-QUERY) failed. Note that the message is not itself flushed to the server automatically; use `pq-flush` if necessary.

**Requires PostgreSQL 17 or later.** Built against an older libpq, this function is not defined at all; `pq-built-version` is how a program asks.

In C:

```c
int PQsendPipelineSync(PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `BOOLEAN`

### `pq-send-flush-request`

```clips
(pq-send-flush-request ?conn)
```

Sends a request for the server to flush its output buffer.

Answers `TRUE` for success. Answers `FALSE` on any failure.

The server flushes its output buffer automatically as a result of `pq-pipeline-sync` being called, or on any request when not in pipeline mode; this function is useful to cause the server to flush its output buffer in pipeline mode without establishing a synchronization point. Note that the request is not itself flushed to the server automatically; use `pq-flush` if necessary.

In C:

```c
int PQsendFlushRequest(PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

#### Returns

- `BOOLEAN`


## Canceling Queries in Progress

### `pq-cancel-create`

```clips
(pq-cancel-create ?conn)
```

Makes a cancel connection for a connection, which is the object every other
`pq-cancel-*` function takes.

Nothing is sent by making one: the request is sent by `pq-cancel-blocking`, or
started by `pq-cancel-start`. A cancel connection can be used again after
`pq-cancel-reset`, and must be closed with `pq-cancel-finish`.

**Requires PostgreSQL 17 or later.** Built against an older libpq, this function is not defined at all; `pq-built-version` is how a program asks.

In C:

```c
PGcancelConn *PQcancelCreate(PGconn *conn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`: The connection whose command should be canceled.

#### Returns

- `EXTERNAL-ADDRESS`: The cancel connection. Close it with `pq-cancel-finish`.

### `pq-cancel-blocking`

```clips
(pq-cancel-blocking ?cancel-conn)
```

Sends a cancel request and waits for the outcome.

The request is sent, not obeyed: the server may finish the command before it
arrives, and a command that is canceled comes back as a result whose SQLSTATE
is `57014`.

**Requires PostgreSQL 17 or later.** Built against an older libpq, this function is not defined at all; `pq-built-version` is how a program asks.

In C:

```c
int PQcancelBlocking(PGcancelConn *cancelConn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `cancel-conn`

#### Returns

- `BOOLEAN`: `TRUE` if the request was delivered. `FALSE` if it could not be, with `pq-cancel-error-message` saying why.

### `pq-cancel-start`

```clips
(pq-cancel-start ?cancel-conn)
```

Starts a cancel request without waiting for it, to be carried the rest of the
way by `pq-cancel-poll`.

**Requires PostgreSQL 17 or later.** Built against an older libpq, this function is not defined at all; `pq-built-version` is how a program asks.

In C:

```c
int PQcancelStart(PGcancelConn *cancelConn);

PostgresPollingStatusType PQcancelPoll(PGcancelConn *cancelConn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `cancel-conn`

#### Returns

- `BOOLEAN`: `TRUE` if the request was started.

### `pq-cancel-poll`

```clips
(pq-cancel-poll ?cancel-conn)
```

Carries a cancel request started with `pq-cancel-start` one step further
along, exactly as `pq-connect-poll` does for a connection.

**Requires PostgreSQL 17 or later.** Built against an older libpq, this function is not defined at all; `pq-built-version` is how a program asks.

In C:

```c
int PQcancelStart(PGcancelConn *cancelConn);

PostgresPollingStatusType PQcancelPoll(PGcancelConn *cancelConn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `cancel-conn`

#### Returns

- `SYMBOL`: `PGRES_POLLING_READING`, `PGRES_POLLING_WRITING`, `PGRES_POLLING_OK` or `PGRES_POLLING_FAILED`.

### `pq-cancel-status`

```clips
(pq-cancel-status ?cancel-conn)
```

Returns the status of a cancel connection, in the same vocabulary `pq-status`
uses for an ordinary one.

**Requires PostgreSQL 17 or later.** Built against an older libpq, this function is not defined at all; `pq-built-version` is how a program asks.

In C:

```c
ConnStatusType PQcancelStatus(const PGcancelConn *cancelConn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `cancel-conn`

#### Returns

- `SYMBOL`: `CONNECTION_ALLOCATED` before anything has been sent, `CONNECTION_OK` once the request has been delivered, `CONNECTION_BAD` if it failed, or one of the intermediate states.

### `pq-cancel-socket`

```clips
(pq-cancel-socket ?cancel-conn)
```

Returns the file descriptor of the cancel connection's socket, for waiting on
between calls to `pq-cancel-poll`.

**Requires PostgreSQL 17 or later.** Built against an older libpq, this function is not defined at all; `pq-built-version` is how a program asks.

In C:

```c
int PQcancelSocket(const PGcancelConn *cancelConn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `cancel-conn`

#### Returns

- `INTEGER`: The descriptor, or `FALSE` when there is no open socket.

### `pq-cancel-error-message`

```clips
(pq-cancel-error-message ?cancel-conn)
```

Returns the message describing why the last operation on the cancel
connection failed.

**Requires PostgreSQL 17 or later.** Built against an older libpq, this function is not defined at all; `pq-built-version` is how a program asks.

In C:

```c
char *PQcancelErrorMessage(const PGcancelConn *cancelconn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `cancel-conn`

#### Returns

- `STRING`: The message, or `FALSE` when there is nothing to report.

### `pq-cancel-reset`

```clips
(pq-cancel-reset ?cancel-conn)
```

Puts a cancel connection back into the state it was created in, closing its
socket if one is open, so that it can be used to send another request.

**Requires PostgreSQL 17 or later.** Built against an older libpq, this function is not defined at all; `pq-built-version` is how a program asks.

In C:

```c
void PQcancelReset(PGcancelConn *cancelConn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `cancel-conn`

#### Returns

- `BOOLEAN`: `TRUE`.

### `pq-cancel-finish`

```clips
(pq-cancel-finish ?cancel-conn)
```

Closes a cancel connection and frees it. The handle is emptied, so a second
close is refused rather than freeing the same memory twice.

**Requires PostgreSQL 17 or later.** Built against an older libpq, this function is not defined at all; `pq-built-version` is how a program asks.

In C:

```c
void PQcancelFinish(PGcancelConn *cancelConn);
```

#### Arguments

- `EXTERNAL-ADDRESS` `cancel-conn`

#### Returns

- `BOOLEAN`: `TRUE`. `FALSE` if the handle was not a cancel connection, or had already been finished.


## Asynchronous Notification

### `pq-notifies`

```clips
(pq-notifies ?conn)
```

Returns the next notification waiting on the connection -- what a `NOTIFY`
command sent to a channel this connection has been told to `LISTEN` to.

Notifications arrive with whatever else is read from the connection, so this
is asked after `pq-consume-input` or after a command, rather than being a
call that waits. `FALSE` means none is waiting, which is not a failure and
writes no message.

```clips
(pq-consume-input ?conn)
(bind ?note (pq-notifies ?conn))
(if ?note then (println "channel " (nth$ 1 ?note) ": " (nth$ 3 ?note)))
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`: The connection to take a notification from.

#### Returns

- `MULTIFIELD`: The channel name as a symbol, the notifying backend's process id as an integer, and the payload as a string -- empty when the `NOTIFY` carried none. `FALSE` when nothing is waiting.


## Functions Associated with the COPY Command

### `pq-put-copy-data`

```clips
(pq-put-copy-data ?conn ?buffer)
```

Sends data to the server during a `COPY ... FROM STDIN`.

The data need not be split at row boundaries; the server reassembles it. It
may be a string, or a multifield of byte values for a binary copy.

In C:

```c
int PQputCopyData(PGconn *conn,
                  const char *buffer,
                  int nbytes);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `STRING`/`MULTIFIELD`/`SYMBOL` `buffer`: The data, as a string or a multifield of integers from 0 to 255.

#### Returns

- `SYMBOL`: `TRUE` when the data was queued, the symbol `busy` when a non-blocking connection's buffer is full and the same data should be offered again, or `FALSE` on failure.

### `pq-put-copy-end`

```clips
(pq-put-copy-end ?conn [?errormsg])
```

Ends a `COPY ... FROM STDIN`, either committing what was sent or abandoning it.

Passing a message makes the copy fail with that message, which is how a
client that finds bad data half way through refuses the whole copy rather
than committing what it has already sent.

In C:

```c
int PQputCopyEnd(PGconn *conn,
                 const char *errormsg);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `STRING`/`SYMBOL` `errormsg` (optional): Optional. A message that makes the copy fail. Omit it, or pass `nil`, to end the copy normally.

#### Returns

- `SYMBOL`: `TRUE` when the end was queued, the symbol `busy` when a non-blocking connection could not queue it, or `FALSE` on failure. The result of the copy is then read with `pq-get-result`.

### `pq-get-copy-data`

```clips
(pq-get-copy-data ?conn [?async])
```

Returns the next row of a `COPY ... TO STDOUT`.

One call, one row, until the copy is finished. Text rows come back as the
text the server printed, newline and all.

In C:

```c
int PQgetCopyData(PGconn *conn,
                  char **buffer,
                  int async);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `BOOLEAN` `async` (optional): Optional. `TRUE` returns at once rather than waiting for a row that has not arrived.

#### Returns

- `STRING`: The row, the symbol `done` when the copy is finished, the symbol `busy` when `async` was `TRUE` and no row has arrived yet, or `FALSE` on failure. After `done`, `pq-get-result` gives the result of the copy itself.


## Control Functions

### `pq-set-client-encoding`

```clips
(pq-set-client-encoding ?conn ?encoding)
```

Sets the client encoding of the connection.

In C:

```c
int PQsetClientEncoding(PGconn *conn, const char *encoding);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `STRING`/`SYMBOL` `encoding`: The encoding name, such as `UTF8` or `LATIN1`.

#### Returns

- `BOOLEAN`: `TRUE` if the encoding was set. `FALSE` for an encoding the server does not have.

### `pq-set-error-verbosity`

```clips
(pq-set-error-verbosity ?conn ?verbosity)
```

Sets how much of an error report the messages on this connection carry, and
answers with the setting it replaced.

The setting applies to messages made from then on, so a result keeps the
verbosity it was produced with; `pq-result-verbose-error-message` is how to
read an old result at a different one.

In C:

```c
typedef enum
{
    PQERRORS_TERSE,
    PQERRORS_DEFAULT,
    PQERRORS_VERBOSE,
    PQERRORS_SQLSTATE
} PGVerbosity;

PGVerbosity PQsetErrorVerbosity(PGconn *conn, PGVerbosity verbosity);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `INTEGER`/`STRING`/`SYMBOL` `verbosity`: `PQERRORS_TERSE`, `PQERRORS_DEFAULT`, `PQERRORS_VERBOSE` or `PQERRORS_SQLSTATE`.

#### Returns

- `SYMBOL`: The verbosity that was in force before this call.

### `pq-set-error-context-visibility`

```clips
(pq-set-error-context-visibility ?conn ?show-context)
```

Sets whether error messages on this connection include the `CONTEXT` field,
and answers with the setting it replaced.

In C:

```c
typedef enum
{
    PQSHOW_CONTEXT_NEVER,
    PQSHOW_CONTEXT_ERRORS,
    PQSHOW_CONTEXT_ALWAYS
} PGContextVisibility;

PGContextVisibility PQsetErrorContextVisibility(PGconn *conn, PGContextVisibility show_context);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `INTEGER`/`STRING`/`SYMBOL` `show-context`: `PQSHOW_CONTEXT_NEVER`, `PQSHOW_CONTEXT_ERRORS` or `PQSHOW_CONTEXT_ALWAYS`.

#### Returns

- `SYMBOL`: The setting that was in force before this call.


## Miscellaneous Functions

### `pq-lib-version`

```clips
(pq-lib-version)
```

Returns the version of the libpq this binary is linked against, as
PostgreSQL numbers itself: 180006 is 18.6.

This is the library's version, not the server's -- `pq-server-version` is
that, and the two need not agree.

In C:

```c
int PQlibVersion(void);
```

#### Returns

- `INTEGER`: The version number.

### `pq-built-version`

```clips
(pq-built-version)
```

Returns the version of the libpq the wrappers were compiled against, in the
same numbers PostgreSQL versions itself with: 180006 is 18.6, and 190000 is
19 before it has a minor version of its own.

This has no counterpart in libpq. It is here because which functions exist
depends on the libpq this library was built against, and CLIPS gives a
program no way to ask whether a function is defined -- so a program that
wants to use something PostgreSQL added recently asks this first:

```clips
(if (>= (pq-built-version) 170000)
 then (bind ?cancel (pq-cancel-create ?conn))
 else ...)
```

`pq-lib-version` is the other question -- the library loaded now, which need
not be the one this was compiled against. A binding compiled against 17 runs
with an 18 library under it and still has only the 17 functions in it, so it
is this one that says what can be called.

#### Returns

- `INTEGER`: The version of the libpq this binding was compiled against.

### `pq-isthreadsafe`

```clips
(pq-isthreadsafe)
```

Returns the thread safety status of the libpq library.

Answers `TRUE` if the libpq is thread-safe and 0 if it is not. Always answers `TRUE` on version 17 and above.

In C:

```c
int PQisthreadsafe();
```

#### Returns

- `BOOLEAN`

### `pq-encrypt-password-conn`

```clips
(pq-encrypt-password-conn ?conn ?passwd ?user [?algorithm])
```

Computes the encrypted form of a password, the way the server would store it,
without sending the password anywhere.

The result goes into `ALTER ROLE ... PASSWORD`, so that the password itself
never travels to the server or into its log. With no algorithm named, the
connection asks the server which one it wants.

In C:

```c
char *PQencryptPasswordConn(PGconn *conn, const char *passwd, const char *user, const char *algorithm);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `STRING`/`SYMBOL` `passwd`: The password to encrypt.

- `STRING`/`SYMBOL` `user`: The role the password is for, which is part of what is hashed.

- `STRING`/`SYMBOL` `algorithm` (optional): Optional. The algorithm to use, such as `scram-sha-256`. `nil` or omitted asks the server.

#### Returns

- `STRING`: The encrypted password.

### `pq-change-password`

```clips
(pq-change-password ?conn ?user ?passwd)
```

Changes a role's password, encrypting it on this side first so that the
password itself is never sent to the server or written to its log.

**Requires PostgreSQL 17 or later.** Built against an older libpq, this function is not defined at all; `pq-built-version` is how a program asks.

In C:

```c
PGresult *PQchangePassword(PGconn *conn, const char *user, const char *passwd);
```

#### Arguments

- `EXTERNAL-ADDRESS` `conn`

- `STRING`/`SYMBOL` `user`: The role whose password is being changed.

- `STRING`/`SYMBOL` `passwd`: The new password.

#### Returns

- `EXTERNAL-ADDRESS`: The result of the `ALTER ROLE` command. Clear it with `pq-clear`.


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

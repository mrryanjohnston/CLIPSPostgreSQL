# API.md overrides

The generator takes each entry's wording from the PostgreSQL documentation
for the version being built against. This file replaces that wording where
the CLIPS function does not behave like its C counterpart, and supplies it
outright for the functions the manual does not describe in an entry of their
own, and it is written in the same shape as the output: a `### ` heading
names the function, the paragraphs under it replace the description, each
bullet under `#### Arguments` names an argument and describes it, and the
lines under `#### Returns` are copied out as they stand.

### `pq-connectdb`

Makes a new connection to the database server, using the parameters taken
from the connection string, and waits for it to be established.

A connection object comes back whether or not the attempt succeeded --
`pq-status` is what says which, and on a connection that failed
`pq-error-message` says why. Either way it is the caller's to close with
`pq-finish`.

The string may be empty, to use every default; it may be a list of
`keyword=value` settings separated by whitespace; or it may be a URI. See
[Connection Strings](@DOCS_BASE@/libpq-connect.html#LIBPQ-CONNSTRING).

#### Arguments

- `conninfo`: Optional. The connection string. Defaults to the empty string, which uses the defaults for every parameter.

#### Returns

- `EXTERNAL-ADDRESS`: The connection, connected or not. Close it with `pq-finish`.

### `pq-connectdb-params`

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

#### Arguments

- `keywords`: The parameter names, as symbols or strings.
- `values`: The value for each keyword, in the same order. `nil` leaves a parameter at its default.
- `expand-dbname`: Optional, `TRUE` by default. When the `dbname` value contains an `=` sign or a URI prefix, it is taken as a connection string of its own and expanded.

#### Returns

- `EXTERNAL-ADDRESS`: The connection, connected or not. Close it with `pq-finish`.

### `pq-setdb-login`

Makes a new connection to the database server with a fixed set of parameters.

This is the predecessor of `pq-connectdb`. It has the same effect except that
every parameter it does not take is left at its default; `nil` for one it does
take leaves that one at its default too.

`pgtty` has been ignored since PostgreSQL 14 and is still taken so that the
argument list matches the C function.

#### Arguments

- `pghost`: The host to connect to, or `nil`.
- `pgport`: The port, or `nil`.
- `pgoptions`: Command-line options for the backend, or `nil`.
- `pgtty`: Ignored. Pass `nil`.
- `dbname`: The database name, or `nil`. A value containing `=` or a URI prefix is taken as a connection string.
- `login`: The user name, or `nil`.
- `pwd`: The password, or `nil`.

#### Returns

- `EXTERNAL-ADDRESS`: The connection, connected or not. Close it with `pq-finish`.

### `pq-connect-start`

Makes a new connection to the database server without waiting for it to be
established.

The connection is not usable until it has been polled through with
`pq-connect-poll`, which is the point of starting one this way: a CLIPS
program that has other work to do can do it between polls.

#### Arguments

- `conninfo`: Optional. The connection string. Defaults to the empty string.

#### Returns

- `EXTERNAL-ADDRESS`: A connection whose status is `CONNECTION_STARTED`, or `FALSE` if libpq could not allocate one. Close it with `pq-finish` however the polling ends.

### `pq-connect-start-params`

Makes a new connection to the database server, from keywords and values,
without waiting for it to be established. `pq-connectdb-params` describes the
two multifields; `pq-connect-poll` carries it the rest of the way.

#### Arguments

- `keywords`: The parameter names, as symbols or strings.
- `values`: The value for each keyword, in the same order. `nil` leaves a parameter at its default.
- `expand-dbname`: Optional, `TRUE` by default.

#### Returns

- `EXTERNAL-ADDRESS`: A connection whose status is `CONNECTION_STARTED`, or `FALSE` if libpq could not allocate one.

### `pq-finish`

Closes the connection to the server and frees everything held for it.

The handle is emptied, so any later call on it is refused rather than being a
second free of the same pointer. Results already taken from the connection
are not affected: they are copies, and stay readable until they are cleared.

#### Returns

- `BOOLEAN`: `TRUE`. `FALSE` if the handle was not a connection, or had already been finished.

### `pq-reset`

Closes the connection to the server and reopens it with the same parameters,
waiting for the new connection to be established.

This is what to do with a connection that has broken: the backend it was
talking to is gone, and everything in flight with it, but the parameters are
still here.

#### Returns

- `BOOLEAN`: `TRUE` once the attempt has finished. Whether it succeeded is what `pq-status` says.

### `pq-clear`

Frees the storage of a result.

Every result has to be cleared when it is finished with, or the memory it
holds is leaked for as long as the process runs. As with `pq-finish`, the
handle is emptied, so a second clear is refused rather than freeing the same
memory twice.

#### Returns

- `BOOLEAN`: `TRUE`. `FALSE` if the handle was not a result, or had already been cleared.

### `pq-conndefaults`

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

#### Returns

- `MULTIFIELD`: Keyword and value, alternating, for every option libpq has.

### `pq-conninfo`

Returns the connection options used by a live connection, in the same
flattened shape `pq-conndefaults` uses: keyword, value, keyword, value, with
`nil` for an option that is not set.

Passwords are not included, which is what makes this safe to print.

#### Arguments

- `conn`: The connection to describe.

#### Returns

- `MULTIFIELD`: Keyword and value, alternating, for every option of this connection.

### `pq-conninfo-parse`

Parses a connection string and returns the options it sets, in the same
flattened shape `pq-conndefaults` uses.

Only the options the string names have values; the rest are `nil`. A string
libpq cannot parse -- an unknown keyword, a keyword with no value -- is a
failure, and libpq's explanation is written to `STDERR`.

#### Arguments

- `conninfo`: The connection string to parse, in `keyword=value` or URI form.

#### Returns

- `MULTIFIELD`: Keyword and value, alternating.

### `pq-ping`


#### Arguments

- `conninfo`: Optional. The connection string naming the server to ask about.

#### Returns

- `SYMBOL`: `PQPING_OK`, `PQPING_REJECT`, `PQPING_NO_RESPONSE` or `PQPING_NO_ATTEMPT`.

### `pq-ping-params`

Reports whether the server can be reached, from keywords and values rather
than a connection string. `pq-connectdb-params` describes the two multifields.

#### Arguments

- `keywords`: The parameter names, as symbols or strings.
- `values`: The value for each keyword, in the same order.
- `expand-dbname`: Optional, `TRUE` by default.

#### Returns

- `SYMBOL`: `PQPING_OK`, `PQPING_REJECT`, `PQPING_NO_RESPONSE` or `PQPING_NO_ATTEMPT`.

### `pq-connect-poll`

Carries a connection started with `pq-connect-start` one step further along.

Call it until it answers `PGRES_POLLING_OK`, which means the connection is
ready, or `PGRES_POLLING_FAILED`, which means it will not be. Between calls,
`PGRES_POLLING_READING` and `PGRES_POLLING_WRITING` say which way the socket
should be waited on, which `pq-socket` and `pq-socket-poll` can do.

#### Returns

- `SYMBOL`: `PGRES_POLLING_READING`, `PGRES_POLLING_WRITING`, `PGRES_POLLING_OK` or `PGRES_POLLING_FAILED`.

### `pq-reset-poll`

Carries a reset started with `pq-reset-start` one step further along, exactly
as `pq-connect-poll` does for a new connection.

#### Returns

- `SYMBOL`: `PGRES_POLLING_READING`, `PGRES_POLLING_WRITING`, `PGRES_POLLING_OK` or `PGRES_POLLING_FAILED`.

### `pq-socket`

Returns the file descriptor of the connection's socket to the server, for a
program that wants to wait on it rather than block inside libpq.

#### Returns

- `INTEGER`: The descriptor, or `FALSE` when the connection has no open socket.

### `pq-error-message`

Returns the message describing the most recent operation on the connection
that failed.

Nearly every libpq call sets this when it fails, so it is read straight after
the call that failed rather than kept: the next failure replaces it. The
message ends in a newline, as libpq writes it.

#### Returns

- `STRING`: The message, or `FALSE` when there is nothing to report.

### `pq-status`


#### Returns

- `SYMBOL`: `CONNECTION_OK`, `CONNECTION_BAD`, or one of the states a connection being established passes through.

### `pq-transaction-status`


#### Returns

- `SYMBOL`: `PQTRANS_IDLE` (connected and idle), `PQTRANS_ACTIVE` (a command is in progress), `PQTRANS_INTRANS` (idle, in a transaction block), `PQTRANS_INERROR` (idle, in a failed transaction block) or `PQTRANS_UNKNOWN` (the connection is bad).

### `pq-parameter-status`

Returns the server's current setting of a parameter it reports to the client,
such as `server_version`, `client_encoding` or `TimeZone`.

#### Arguments

- `param-name`: The parameter to ask about.

#### Returns

- `STRING`: The value, or `FALSE` for a parameter this server does not report.

### `pq-client-encoding`

Returns the client encoding of the connection, as the integer id libpq
numbers encodings with.

The name is what most programs want, and
`(pq-parameter-status ?conn "client_encoding")` is where it is.

#### Returns

- `INTEGER`: The encoding id.

### `pq-ssl-attribute`

Returns one piece of information about the SSL in use on the connection --
`library`, `protocol`, `key_bits`, `cipher`, `compression`,
`alpn`. `pq-ssl-attribute-names` lists the ones this connection can answer.

#### Arguments

- `attribute-name`: The attribute to read.

#### Returns

- `STRING`: The value, or `FALSE` when the attribute has none, which is the answer for every attribute of a connection not using SSL.

### `pq-ssl-attribute-names`

Returns the names of the SSL attributes this connection can be asked about
with `pq-ssl-attribute`.

#### Returns

- `MULTIFIELD`: The attribute names, one symbol each. Empty when the connection is not using SSL.

### `pq-gss-enc-in-use`

Returns whether the connection is encrypted with GSSAPI.

#### Returns

- `BOOLEAN`: `TRUE` if GSSAPI encryption is in use.

### `pq-exec`

Submits a command to the server and waits for the result.

A command the server refused is a result like any other: its status is
`PGRES_FATAL_ERROR` and `pq-result-error-message` says what was wrong with it.
`FALSE` is only for the case where there is no result at all, which means the
connection is broken or out of memory.

The command string may contain several statements separated by semicolons,
in which case the whole lot runs in one transaction unless it contains its
own transaction commands, and the result is the last statement's.

Every result must be cleared with `pq-clear`.

#### Arguments

- `command`: The SQL to run.

#### Returns

- `EXTERNAL-ADDRESS`: The result. Clear it with `pq-clear`.

### `pq-exec-params`

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

#### Arguments

- `command`: The SQL to run, with `$1`, `$2` and so on where the parameters go.
- `params`: Optional. The parameter values, in order. `nil` is SQL NULL.

#### Returns

- `EXTERNAL-ADDRESS`: The result. Clear it with `pq-clear`.

### `pq-prepare`

Prepares a statement on the server under a name, for `pq-exec-prepared` to
run more than once.

The parameter types are left to the server to infer from the statement.

#### Arguments

- `statement-name`: The name to prepare it under. The empty string names the unnamed statement, which the next prepare replaces.
- `query`: The SQL, with `$1`, `$2` and so on where the parameters go.

#### Returns

- `EXTERNAL-ADDRESS`: A result whose status says whether the statement was prepared. Clear it with `pq-clear`.

### `pq-exec-prepared`

Runs a statement prepared with `pq-prepare` and waits for the result. The
parameters are a multifield, exactly as in `pq-exec-params`.

#### Arguments

- `statement-name`: The name the statement was prepared under.
- `params`: Optional. The parameter values, in order. `nil` is SQL NULL.

#### Returns

- `EXTERNAL-ADDRESS`: The result. Clear it with `pq-clear`.

### `pq-describe-prepared`

Asks the server about a prepared statement: the number of its parameters and
their types, from `pq-nparams` and `pq-paramtype`, and the columns it will
return, from the column functions.

#### Arguments

- `statement-name`: The name the statement was prepared under, or the empty string for the unnamed statement.

#### Returns

- `EXTERNAL-ADDRESS`: A result carrying the description. Clear it with `pq-clear`.

### `pq-describe-portal`

Asks the server about a portal -- what a cursor is on the wire -- returning a
result that describes the columns it will produce.

#### Arguments

- `portal-name`: The portal to describe, or the empty string for the unnamed portal.

#### Returns

- `EXTERNAL-ADDRESS`: A result carrying the description. Clear it with `pq-clear`.

### `pq-close-prepared`

Closes a prepared statement, freeing what the server was holding for it.
Closing a name that was never prepared is not an error: the point of the call
is that the name is free afterwards.

#### Arguments

- `statement-name`: The statement to close.

#### Returns

- `EXTERNAL-ADDRESS`: A result whose status says what happened. Clear it with `pq-clear`.

### `pq-close-portal`

Closes a portal, freeing what the server was holding for it. As with
`pq-close-prepared`, closing one that is not there is not an error.

#### Arguments

- `portal-name`: The portal to close.

#### Returns

- `EXTERNAL-ADDRESS`: A result whose status says what happened. Clear it with `pq-clear`.

### `pq-make-empty-pgresult`

Builds a result object with a status of the caller's choosing and nothing in
it, for a program that wants to hand back a result of its own.

#### Arguments

- `conn`: The connection to take the error settings from.
- `status`: The status the result should have, as the symbol or the integer.

#### Returns

- `EXTERNAL-ADDRESS`: The result. Clear it with `pq-clear`, like any other.

### `pq-result-status`


#### Returns

- `SYMBOL`: One of `PGRES_EMPTY_QUERY`, `PGRES_COMMAND_OK`, `PGRES_TUPLES_OK`, `PGRES_COPY_OUT`, `PGRES_COPY_IN`, `PGRES_COPY_BOTH`, `PGRES_BAD_RESPONSE`, `PGRES_NONFATAL_ERROR`, `PGRES_FATAL_ERROR`, `PGRES_SINGLE_TUPLE`, `PGRES_TUPLES_CHUNK`, `PGRES_PIPELINE_SYNC` or `PGRES_PIPELINE_ABORTED`.

### `pq-res-status`

Returns the name of a result status, for a message that has to name one. It
takes the status rather than the result, so it can be asked about a status
that no result has.

#### Arguments

- `status`: A result status, as the symbol or the integer behind it.

#### Returns

- `STRING`: The name of the status, as C spells it.

### `pq-result-error-message`

Returns the error message associated with a result, or `FALSE` for a result
that carries none -- which is every result of a command that succeeded.

Unlike `pq-error-message`, this belongs to the result and does not change, so
it can be read at any time while the result is alive.

#### Returns

- `STRING`: The message, ending in a newline, or `FALSE` if there is none.

### `pq-result-verbose-error-message`

Returns the error message of a result at a chosen verbosity, whatever
verbosity the connection had when the result was produced.

#### Arguments

- `verbosity`: `PQERRORS_TERSE`, `PQERRORS_DEFAULT`, `PQERRORS_VERBOSE` or `PQERRORS_SQLSTATE`.
- `show-context`: `PQSHOW_CONTEXT_NEVER`, `PQSHOW_CONTEXT_ERRORS` or `PQSHOW_CONTEXT_ALWAYS`.

#### Returns

- `STRING`: The message.

### `pq-result-error-field`


#### Arguments

- `fieldcode`: The field to read, as one of the `PG_DIAG_*` symbols or the character code behind it.

#### Returns

- `STRING`: The field, or `FALSE` when the report does not include it. Not every field is present in every report.

### `pq-fnumber`

Returns the number of the column with a given name.

The name is matched the way SQL matches an identifier: an unquoted name is
folded to lower case, and a name in double quotes is matched exactly.

#### Arguments

- `column-name`: The name to look for.

#### Returns

- `INTEGER`: The column number, counting from zero, or `-1` when the result has no such column.

### `pq-ftable`

Returns the OID of the table a column was selected from.

#### Returns

- `INTEGER`: The table's OID, or `FALSE` when the column is not a simple reference to a table column, which is the case for anything computed.

### `pq-ftablecol`

Returns the number of a column within the table it was selected from,
counting from one, as PostgreSQL numbers table columns.

#### Returns

- `INTEGER`: The column's number in its table, or `FALSE` when the column is not a simple reference to a table column.

### `pq-getvalue`

Returns one field of one row of a result.

A field that is SQL NULL comes back as the symbol `nil` rather than as the
empty string, so that a NULL and an empty value can be told apart without a
second call; `pq-getisnull` is still there for a caller that would rather ask.

Values arrive as the text PostgreSQL printed. The row mappers --
`pq-row-to-multifield` and the two beside it -- are what convert a whole row
to CLIPS types in one call.

#### Arguments

- `row-number`: The row, counting from zero.
- `column-number`: The column, counting from zero.

#### Returns

- `STRING`: The field's text, or the symbol `nil` if it is SQL NULL.

### `pq-getlength`

Returns the length in bytes of one field of one row, which for a text value
is the length of the string and for a binary one the size of the datum.

#### Arguments

- `row-number`: The row, counting from zero.
- `column-number`: The column, counting from zero.

#### Returns

- `INTEGER`: The length in bytes. Zero for a NULL field.

### `pq-getisnull`

Returns whether one field of one row is SQL NULL.

#### Arguments

- `row-number`: The row, counting from zero.
- `column-number`: The column, counting from zero.

#### Returns

- `BOOLEAN`: `TRUE` if the field is NULL.

### `pq-cmd-tuples`

Returns the number of rows the command affected.

libpq reports this as a string, and it is an integer here: `INSERT`, `UPDATE`,
`DELETE`, `MERGE`, `MOVE`, `FETCH` and `COPY` all count rows, and `SELECT`
reports the number it returned.

#### Returns

- `INTEGER`: The number of rows, or `FALSE` for a command that counts none.

### `pq-oid-value`

Returns the OID of the row an `INSERT` inserted.

Tables have not had OIDs since PostgreSQL 12, so this is `FALSE` for every
ordinary insert. A statement that needs the identifier of what it inserted
should use `INSERT ... RETURNING` instead.

#### Returns

- `INTEGER`: The OID, or `FALSE` when the statement inserted no row into a table with OIDs.

### `pq-escape-literal`

Escapes a string for use as a literal inside an SQL command, and puts the
quotes on it.

The result is ready to be concatenated into a command as it stands -- adding
quotes around it would be wrong. A parameter is still the better way to get a
value into a query; this is for the cases where a parameter cannot go, and
for building an identifier's default.

```clips
(str-cat "SELECT * FROM widgets WHERE name = " (pq-escape-literal ?conn ?name))
```

#### Arguments

- `str`: The text to escape.

#### Returns

- `STRING`: The escaped and quoted literal.

### `pq-escape-identifier`

Escapes a string for use as an SQL identifier -- a table or column name --
and puts the double quotes on it.

#### Arguments

- `str`: The identifier to escape.

#### Returns

- `STRING`: The escaped and quoted identifier.

### `pq-escape-string-conn`

Escapes a string for use inside an SQL literal, without adding the quotes.
`pq-escape-literal` is the one to use for new code; this is here because so
much existing SQL is built around it.

#### Arguments

- `from`: The text to escape.

#### Returns

- `STRING`: The escaped text, with no quotes around it.

### `pq-escape-bytea-conn`

Escapes binary data for use inside a `bytea` literal, in the format the
server's `standard_conforming_strings` setting calls for.

The data may be a multifield of byte values from 0 to 255, which is how a
`bytea` crosses in the other direction, or a string, for the common case of
text going into a `bytea` column.

#### Arguments

- `from`: The bytes, as a multifield of integers from 0 to 255, or a string.

#### Returns

- `STRING`: The escaped text, ready to be concatenated into a command.

### `pq-unescape-bytea`

Converts the text form of a `bytea` -- what the server prints for one, and
what `pq-escape-bytea-conn` produces -- back into the bytes it stands for.

The bytes come back as a multifield of integers so that a zero byte in the
middle of the data is a field like any other rather than the end of a string.

#### Arguments

- `from`: The escaped text.

#### Returns

- `MULTIFIELD`: The bytes, one integer from 0 to 255 each.

### `pq-row-to-multifield`

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

- `res`: The result to read from.
- `row-number`: The row, counting from zero.

#### Returns

- `MULTIFIELD`: The row's values in column order.

### `pq-row-to-fact`

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

- `res`: The result to read from.
- `row-number`: The row, counting from zero.
- `deftemplate`: The name of the deftemplate to assert.

#### Returns

- `FACT-ADDRESS`: The asserted fact.

### `pq-row-to-instance`

Makes an instance of a defclass from one row of a result, taking the column
names as slot names and converting each value as `pq-row-to-multifield` does.

As with `pq-row-to-fact`, the class must have a slot for every column of the
row. An instance's name is not a slot, so a column called `name` has nowhere
to go: it is written to the slot `_name`, or to whichever slot the fifth
argument names.

#### Arguments

- `res`: The result to read from.
- `row-number`: The row, counting from zero.
- `defclass`: The name of the defclass to make an instance of.
- `instance-name`: Optional. The name for the instance; `nil` leaves CLIPS to make one up, which is what a loop over rows wants.
- `name-slot`: Optional. The slot a column called `name` is written to. Defaults to `_name`.

#### Returns

- `INSTANCE-ADDRESS`: The new instance.

### `pq-result-to-multifields`

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

- `res`: The result to read.
- `headers`: Optional. `TRUE` to put the column names in front of the values. Defaults to `FALSE`; anything that is neither is refused.

#### Returns

- `MULTIFIELD`: The values row by row, preceded by the column names when `headers` is `TRUE`.

### `pq-result-to-facts`

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

- `res`: The result whose rows become facts.
- `deftemplate`: The name of the deftemplate to assert. Columns naming one of its slots fill that slot; the rest are passed over.

#### Returns

- `MULTIFIELD`: One fact address per row that was made, in row order.

### `pq-result-to-instances`

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

- `res`: The result whose rows become instances.
- `defclass`: The name of the defclass to instantiate. Columns naming one of its slots fill that slot; the rest are passed over.
- `instance-names`: Optional. What to call the instances, in row order: a multifield of names, or one name for the first row. Rows the list does not reach are named by CLIPS.

#### Returns

- `MULTIFIELD`: One instance address per row that was made, in row order.

### `pq-exec-to-multifields`

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

- `conn`: The connection to run the command on.
- `command`: The SQL to run.
- `headers`: Optional. `TRUE` to put the column names in front of the values. Defaults to `FALSE`.

#### Returns

- `MULTIFIELD`: The values row by row, preceded by the column names when `headers` is `TRUE`.

### `pq-exec-to-facts`

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

- `conn`: The connection to run the command on.
- `command`: The SQL to run.
- `deftemplate`: Optional. The name of the deftemplate to assert. Defaults to the one table the result's columns come from.

#### Returns

- `MULTIFIELD`: One fact address per row that was made, in row order.

### `pq-exec-to-instances`

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

- `conn`: The connection to run the command on.
- `command`: The SQL to run.
- `defclass`: Optional. The name of the defclass to instantiate. Defaults to the one table the result's columns come from, in capitals. A multifield here is the `instance-names` instead.
- `instance-names`: Optional. What to call the instances, in row order: a multifield of names, or one name for the first row. Rows the list does not reach are named by CLIPS.

#### Returns

- `MULTIFIELD`: One instance address per row that was made, in row order.

### `pq-send-query`

Submits a command without waiting for the result, which is then collected
with `pq-get-result`.

The connection will not take another command until every result of this one
has been read.

#### Arguments

- `command`: The SQL to run.

#### Returns

- `BOOLEAN`: `TRUE` if the command was sent. `FALSE` if it could not be, with libpq's reason on `STDERR`.

### `pq-send-query-params`

Submits a command with parameters without waiting for the result. The
parameters are a multifield, exactly as in `pq-exec-params`.

#### Arguments

- `command`: The SQL to run, with `$1`, `$2` and so on where the parameters go.
- `params`: Optional. The parameter values, in order. `nil` is SQL NULL.

#### Returns

- `BOOLEAN`: `TRUE` if the command was sent.

### `pq-send-prepare`

Prepares a statement without waiting for the result.

#### Arguments

- `statement-name`: The name to prepare it under.
- `query`: The SQL, with `$1`, `$2` and so on where the parameters go.

#### Returns

- `BOOLEAN`: `TRUE` if the request was sent.

### `pq-send-query-prepared`

Runs a prepared statement without waiting for the result. The parameters are
a multifield, exactly as in `pq-exec-params`.

#### Arguments

- `statement-name`: The name the statement was prepared under.
- `params`: Optional. The parameter values, in order. `nil` is SQL NULL.

#### Returns

- `BOOLEAN`: `TRUE` if the command was sent.

### `pq-get-result`

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

#### Returns

- `EXTERNAL-ADDRESS`: The next result, to be cleared with `pq-clear`, or `FALSE` when the command has no more.

### `pq-is-busy`

Returns whether a command is still in flight, which is to say whether
`pq-get-result` would block. Ask `pq-consume-input` for what has arrived
first, or this will keep saying the same thing.

#### Returns

- `BOOLEAN`: `TRUE` while the command is still busy.

### `pq-flush`

Sends whatever is still queued on the connection.

On a blocking connection this either finishes or fails. On a non-blocking one
it may do neither: the socket would have blocked and some of the data is
still queued, which is the symbol `busy` and is not a failure.

#### Returns

- `SYMBOL`: `TRUE` when everything has been sent, the symbol `busy` when some of it is still queued, or `FALSE` on failure.

### `pq-setnonblocking`

Sets the blocking state of the connection: in non-blocking mode a send that
would block queues the data and answers instead of waiting.

#### Arguments

- `arg`: `TRUE` for non-blocking, `FALSE` for blocking.

#### Returns

- `BOOLEAN`: `TRUE` if the state was changed.

### `pq-socket-poll`

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

#### Arguments

- `sock`: The file descriptor, from `pq-socket` or `pq-cancel-socket`.
- `for-read`: `TRUE` to wait until it can be read from.
- `for-write`: `TRUE` to wait until it can be written to.
- `end-time`: The deadline, in microseconds since the epoch. `-1` to wait forever, `0` to return at once.

#### Returns

- `INTEGER`: Greater than zero when the socket is ready, zero when the deadline passed first, `FALSE` if the socket could not be polled.

### `pq-get-current-time-usec`

Returns the current time in microseconds since the epoch, in the form
`pq-socket-poll` takes as a deadline.

#### Returns

- `INTEGER`: The current time in microseconds.

### `pq-set-chunked-rows-mode`

Puts the connection into chunked-rows mode for the command just sent, so that
its rows arrive as a series of results of the given size rather than one
result holding all of them.

Each chunk comes back with the status `PGRES_TUPLES_CHUNK`, and the last one
is followed by a `PGRES_TUPLES_OK` result with no rows in it.

#### Arguments

- `chunk-size`: How many rows each result should hold. Must be greater than zero.

#### Returns

- `BOOLEAN`: `TRUE` if the mode was set. `FALSE` if the connection was not in a state where it could be.

### `pq-pipeline-status`

Returns whether the connection is in pipeline mode, and whether the current
pipeline has been aborted by a command that failed.

#### Returns

- `SYMBOL`: `PQ_PIPELINE_ON`, `PQ_PIPELINE_OFF` or `PQ_PIPELINE_ABORTED`.

### `pq-cancel-create`

Makes a cancel connection for a connection, which is the object every other
`pq-cancel-*` function takes.

Nothing is sent by making one: the request is sent by `pq-cancel-blocking`, or
started by `pq-cancel-start`. A cancel connection can be used again after
`pq-cancel-reset`, and must be closed with `pq-cancel-finish`.

#### Arguments

- `conn`: The connection whose command should be canceled.

#### Returns

- `EXTERNAL-ADDRESS`: The cancel connection. Close it with `pq-cancel-finish`.

### `pq-cancel-blocking`

Sends a cancel request and waits for the outcome.

The request is sent, not obeyed: the server may finish the command before it
arrives, and a command that is canceled comes back as a result whose SQLSTATE
is `57014`.

#### Returns

- `BOOLEAN`: `TRUE` if the request was delivered. `FALSE` if it could not be, with `pq-cancel-error-message` saying why.

### `pq-cancel-start`

Starts a cancel request without waiting for it, to be carried the rest of the
way by `pq-cancel-poll`.

#### Returns

- `BOOLEAN`: `TRUE` if the request was started.

### `pq-cancel-poll`

Carries a cancel request started with `pq-cancel-start` one step further
along, exactly as `pq-connect-poll` does for a connection.

#### Returns

- `SYMBOL`: `PGRES_POLLING_READING`, `PGRES_POLLING_WRITING`, `PGRES_POLLING_OK` or `PGRES_POLLING_FAILED`.

### `pq-cancel-status`

Returns the status of a cancel connection, in the same vocabulary `pq-status`
uses for an ordinary one.

#### Returns

- `SYMBOL`: `CONNECTION_ALLOCATED` before anything has been sent, `CONNECTION_OK` once the request has been delivered, `CONNECTION_BAD` if it failed, or one of the intermediate states.

### `pq-cancel-socket`

Returns the file descriptor of the cancel connection's socket, for waiting on
between calls to `pq-cancel-poll`.

#### Returns

- `INTEGER`: The descriptor, or `FALSE` when there is no open socket.

### `pq-cancel-error-message`

Returns the message describing why the last operation on the cancel
connection failed.

#### Returns

- `STRING`: The message, or `FALSE` when there is nothing to report.

### `pq-cancel-reset`

Puts a cancel connection back into the state it was created in, closing its
socket if one is open, so that it can be used to send another request.

#### Returns

- `BOOLEAN`: `TRUE`.

### `pq-cancel-finish`

Closes a cancel connection and frees it. The handle is emptied, so a second
close is refused rather than freeing the same memory twice.

#### Returns

- `BOOLEAN`: `TRUE`. `FALSE` if the handle was not a cancel connection, or had already been finished.

### `pq-notifies`

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

- `conn`: The connection to take a notification from.

#### Returns

- `MULTIFIELD`: The channel name as a symbol, the notifying backend's process id as an integer, and the payload as a string -- empty when the `NOTIFY` carried none. `FALSE` when nothing is waiting.

### `pq-put-copy-data`

Sends data to the server during a `COPY ... FROM STDIN`.

The data need not be split at row boundaries; the server reassembles it. It
may be a string, or a multifield of byte values for a binary copy.

#### Arguments

- `buffer`: The data, as a string or a multifield of integers from 0 to 255.

#### Returns

- `SYMBOL`: `TRUE` when the data was queued, the symbol `busy` when a non-blocking connection's buffer is full and the same data should be offered again, or `FALSE` on failure.

### `pq-put-copy-end`

Ends a `COPY ... FROM STDIN`, either committing what was sent or abandoning it.

Passing a message makes the copy fail with that message, which is how a
client that finds bad data half way through refuses the whole copy rather
than committing what it has already sent.

#### Arguments

- `errormsg`: Optional. A message that makes the copy fail. Omit it, or pass `nil`, to end the copy normally.

#### Returns

- `SYMBOL`: `TRUE` when the end was queued, the symbol `busy` when a non-blocking connection could not queue it, or `FALSE` on failure. The result of the copy is then read with `pq-get-result`.

### `pq-get-copy-data`

Returns the next row of a `COPY ... TO STDOUT`.

One call, one row, until the copy is finished. Text rows come back as the
text the server printed, newline and all.

#### Arguments

- `async`: Optional. `TRUE` returns at once rather than waiting for a row that has not arrived.

#### Returns

- `STRING`: The row, the symbol `done` when the copy is finished, the symbol `busy` when `async` was `TRUE` and no row has arrived yet, or `FALSE` on failure. After `done`, `pq-get-result` gives the result of the copy itself.

### `pq-set-error-verbosity`

Sets how much of an error report the messages on this connection carry, and
answers with the setting it replaced.

The setting applies to messages made from then on, so a result keeps the
verbosity it was produced with; `pq-result-verbose-error-message` is how to
read an old result at a different one.

#### Arguments

- `verbosity`: `PQERRORS_TERSE`, `PQERRORS_DEFAULT`, `PQERRORS_VERBOSE` or `PQERRORS_SQLSTATE`.

#### Returns

- `SYMBOL`: The verbosity that was in force before this call.

### `pq-set-error-context-visibility`

Sets whether error messages on this connection include the `CONTEXT` field,
and answers with the setting it replaced.

#### Arguments

- `show-context`: `PQSHOW_CONTEXT_NEVER`, `PQSHOW_CONTEXT_ERRORS` or `PQSHOW_CONTEXT_ALWAYS`.

#### Returns

- `SYMBOL`: The setting that was in force before this call.

### `pq-set-client-encoding`

Sets the client encoding of the connection.

#### Arguments

- `encoding`: The encoding name, such as `UTF8` or `LATIN1`.

#### Returns

- `BOOLEAN`: `TRUE` if the encoding was set. `FALSE` for an encoding the server does not have.

### `pq-lib-version`

Returns the version of the libpq this binary is linked against, as
PostgreSQL numbers itself: 180006 is 18.6.

This is the library's version, not the server's -- `pq-server-version` is
that, and the two need not agree.

#### Returns

- `INTEGER`: The version number.

### `pq-built-version`

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

### `pq-encrypt-password-conn`

Computes the encrypted form of a password, the way the server would store it,
without sending the password anywhere.

The result goes into `ALTER ROLE ... PASSWORD`, so that the password itself
never travels to the server or into its log. With no algorithm named, the
connection asks the server which one it wants.

#### Arguments

- `passwd`: The password to encrypt.
- `user`: The role the password is for, which is part of what is hashed.
- `algorithm`: Optional. The algorithm to use, such as `scram-sha-256`. `nil` or omitted asks the server.

#### Returns

- `STRING`: The encrypted password.

### `pq-change-password`

Changes a role's password, encrypting it on this side first so that the
password itself is never sent to the server or written to its log.

#### Arguments

- `user`: The role whose password is being changed.
- `passwd`: The new password.

#### Returns

- `EXTERNAL-ADDRESS`: The result of the `ALTER ROLE` command. Clear it with `pq-clear`.

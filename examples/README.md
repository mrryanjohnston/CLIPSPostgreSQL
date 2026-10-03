# Examples

Each of these is a CLIPS batch file. Run one with the binary the build
produced:

```
./vendor/clips/clips -f2 examples/1-rules-over-sql.bat
```

They connect with an empty connection string, which means libpq takes
everything from the environment: `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`
and the rest, as `psql` does. Point them at a scratch database -- they create
tables and write rows.

```
PGDATABASE=scratch ./vendor/clips/clips -f2 examples/1-rules-over-sql.bat
```

Everything each one creates is a temporary table, which the server drops when
the connection closes -- except the table in `2-listen-notify.bat`, which has
to outlive a transaction to be notified about, and is dropped at the end.

`make test` runs all of them, and checks each against the `.expected` file
beside it: the lines there have to appear in the example's output, it has to
exit cleanly, and it has to write nothing to `STDERR`. So an example that
stops working, or starts saying something else, fails the suite rather than
sitting here misleading someone. `make test-examples` runs only these.

The `.expected` files leave out what differs between machines -- a socket
path, a server version, the process id of a backend -- and pin what the
example is demonstrating.

| | |
| --- | --- |
| [1-rules-over-sql.bat](1-rules-over-sql.bat) | Rows become facts, rules run over them, and what the rules concluded goes back to the server as parameters. |
| [2-listen-notify.bat](2-listen-notify.bat) | A rule fires on what another session did, through `LISTEN` and `NOTIFY`. |
| [3-copy-and-aggregate.bat](3-copy-and-aggregate.bat) | A bulk load with `COPY`, and reading the result of an aggregate back. |
| [4-reading-rows.bat](4-reading-rows.bat) | Every way of reading rows, side by side: field by field as text, one row converted by type, every row of a result at once, and the forms that run the command as well and infer the deftemplate or defclass from the table. |

; ======================================================================
; Running commands, and everything a result says about what happened.
; ======================================================================

(println crlf "exec-test-suite")

(defglobal ?*econn* = (connect))

(run-sql ?*econn* "CREATE TEMP TABLE widgets (id serial PRIMARY KEY, name text, weight float8)")

; ----------------------------------------------------------------------
; A command that changes rows
; ----------------------------------------------------------------------

(defglobal ?*insert* =
  (pq-exec ?*econn* "INSERT INTO widgets (name, weight) VALUES ('bolt', 1.5), ('nut', 0.25)"))

(expect "an INSERT comes back as a command, not a set of rows"
        PGRES_COMMAND_OK (pq-result-status ?*insert*))
(expect "pq-cmd-status is the tag the server put on it"
        "INSERT 0 2" (pq-cmd-status ?*insert*))
(expect "pq-cmd-tuples counts the rows it touched"
        2 (pq-cmd-tuples ?*insert*))
(expect "a command result has no rows" 0 (pq-ntuples ?*insert*))
(expect "and no columns" 0 (pq-nfields ?*insert*))

; Tables have had no OIDs since PostgreSQL 12, so there is no OID to report.
(expect "pq-oid-value has nothing to report for an ordinary INSERT"
        FALSE (pq-oid-value ?*insert*))
(expect-true "a result knows how much memory it holds"
             (> (pq-result-memory-size ?*insert*) 0))
(expect "pq-clear frees it" TRUE (pq-clear ?*insert*))

; ----------------------------------------------------------------------
; A command that returns rows
; ----------------------------------------------------------------------

(defglobal ?*rows* =
  (pq-exec ?*econn* "SELECT id, name, weight FROM widgets ORDER BY id"))

(expect "a SELECT comes back as rows" PGRES_TUPLES_OK (pq-result-status ?*rows*))
(expect "two of them" 2 (pq-ntuples ?*rows*))
(expect "of three columns" 3 (pq-nfields ?*rows*))
(expect "pq-cmd-status names the command" "SELECT 2" (pq-cmd-status ?*rows*))
(expect "and pq-cmd-tuples counts the rows returned" 2 (pq-cmd-tuples ?*rows*))

(expect "pq-getvalue reads a value out as text" "bolt" (pq-getvalue ?*rows* 0 1))
(expect "including one that is a number in the database"
        "1.5" (pq-getvalue ?*rows* 0 2))
(expect "pq-getlength is the length of that text"
        4 (pq-getlength ?*rows* 0 1))
(expect "pq-getisnull is FALSE for a value that is there"
        FALSE (pq-getisnull ?*rows* 0 1))

(defglobal ?*past-end* = (pq-getvalue ?*rows* 2 0))
(expect "a row past the end of the result is refused" FALSE ?*past-end*)

(defglobal ?*past-side* = (pq-getvalue ?*rows* 0 3))
(expect "so is a column past the last one" FALSE ?*past-side*)

(defglobal ?*negative* = (pq-getvalue ?*rows* -1 0))
(expect "and a negative row number" FALSE ?*negative*)

(pq-clear ?*rows*)

; ----------------------------------------------------------------------
; SQL NULL, which is not the empty string
; ----------------------------------------------------------------------

(run-sql ?*econn* "INSERT INTO widgets (name, weight) VALUES (NULL, NULL)")
(defglobal ?*nulls* =
  (pq-exec ?*econn* "SELECT name, weight FROM widgets WHERE name IS NULL"))

(expect "pq-getisnull says a NULL is null" TRUE (pq-getisnull ?*nulls* 0 0))
(expect "pq-getvalue answers nil rather than an empty string"
        nil (pq-getvalue ?*nulls* 0 0))
(expect "and its length is zero" 0 (pq-getlength ?*nulls* 0 0))
(pq-clear ?*nulls*)

; ----------------------------------------------------------------------
; A command the server refuses
;
; This is a result like any other, and reading it is how a program finds out
; what was wrong with what it sent.
; ----------------------------------------------------------------------

(defglobal ?*syntax* = (pq-exec ?*econn* "SELEC 1"))

(expect-true "a rejected command still produces a result" (neq FALSE ?*syntax*))
(expect "whose status is the failure" PGRES_FATAL_ERROR (pq-result-status ?*syntax*))
(expect-true "with a message" (stringp (pq-result-error-message ?*syntax*)))
(expect "and a SQLSTATE, which is the part a program can branch on"
        "42601" (pq-result-error-field ?*syntax* PG_DIAG_SQLSTATE))
(expect-true "and a severity" (stringp (pq-result-error-field ?*syntax* PG_DIAG_SEVERITY)))
(expect "an error field the server did not send has no value"
        FALSE (pq-result-error-field ?*syntax* PG_DIAG_CONSTRAINT_NAME))
(expect-true "pq-result-verbose-error-message says more than the message did"
             (> (str-length (pq-result-verbose-error-message
                              ?*syntax* PQERRORS_VERBOSE PQSHOW_CONTEXT_ALWAYS))
                (str-length (pq-result-error-message ?*syntax*))))
(pq-clear ?*syntax*)

; A constraint violation, where the server does name the constraint.
(defglobal ?*constraint* =
  (pq-exec ?*econn* "INSERT INTO widgets (id, name) VALUES (1, 'duplicate')"))
(expect "a unique violation has its own SQLSTATE"
        "23505" (pq-result-error-field ?*constraint* PG_DIAG_SQLSTATE))
(expect "and names the constraint that was broken"
        "widgets_pkey" (pq-result-error-field ?*constraint* PG_DIAG_CONSTRAINT_NAME))
(expect "and the table it was on" "widgets" (pq-result-error-field ?*constraint* PG_DIAG_TABLE_NAME))
(pq-clear ?*constraint*)

; ----------------------------------------------------------------------
; pq-res-status, which names a status without needing a result
; ----------------------------------------------------------------------

(expect "pq-res-status names a status" "PGRES_TUPLES_OK" (pq-res-status PGRES_TUPLES_OK))
(expect "and an empty query is its own status"
        "PGRES_EMPTY_QUERY" (pq-res-status PGRES_EMPTY_QUERY))

(defglobal ?*empty-query* = (pq-exec ?*econn* ""))
(expect "which is what an empty command string produces"
        PGRES_EMPTY_QUERY (pq-result-status ?*empty-query*))
(pq-clear ?*empty-query*)

; ----------------------------------------------------------------------
; A result the client made up, which the callers of the notice hooks need
; and which nothing else here would produce
; ----------------------------------------------------------------------

(defglobal ?*fabricated* = (pq-make-empty-pgresult ?*econn* PGRES_COMMAND_OK))
(expect "pq-make-empty-pgresult builds a result with the status it was given"
        PGRES_COMMAND_OK (pq-result-status ?*fabricated*))
(expect "with no rows in it" 0 (pq-ntuples ?*fabricated*))
(expect "and it is cleared like any other" TRUE (pq-clear ?*fabricated*))

(defglobal ?*fabricated-bad* = (pq-make-empty-pgresult ?*econn* PGRES_NOT_A_STATUS))
(expect "a status libpq does not have is refused" FALSE ?*fabricated-bad*)

; ----------------------------------------------------------------------
; Portals, which are what a cursor is on the wire
; ----------------------------------------------------------------------

(run-sql ?*econn* "BEGIN")
(run-sql ?*econn* "DECLARE widget_cursor CURSOR FOR SELECT id, name FROM widgets")

(defglobal ?*portal* = (pq-describe-portal ?*econn* "widget_cursor"))
(expect "a portal describes the columns it will produce"
        PGRES_COMMAND_OK (pq-result-status ?*portal*))
(expect "two of them" 2 (pq-nfields ?*portal*))
(expect "named as the query named them" "name" (pq-fname ?*portal* 1))
(pq-clear ?*portal*)

; Closing the portal is tested in tests/pg17-test-suite.bat: pq-close-portal
; arrived in PostgreSQL 17.

(run-sql ?*econn* "ROLLBACK")

(pq-finish ?*econn*)

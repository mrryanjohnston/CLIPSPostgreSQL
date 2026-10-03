; ======================================================================
; Parameters and prepared statements.
;
; Everything here sends its values out of band, which is the reason to use
; any of it: a value that travels as a parameter is never part of the
; command text and can never be read as SQL.
; ======================================================================

(println crlf "params-test-suite")

(defglobal ?*pconn* = (connect))

(run-sql ?*pconn* "CREATE TEMP TABLE parts (id int, label text, mass float8)")

; ----------------------------------------------------------------------
; pq-exec-params
; ----------------------------------------------------------------------

(defglobal ?*inserted* =
  (pq-exec-params ?*pconn* "INSERT INTO parts VALUES ($1, $2, $3)"
                  (create$ 1 "flange" 2.75)))
(expect "a parameterised INSERT runs" PGRES_COMMAND_OK (pq-result-status ?*inserted*))
(expect "and inserts one row" 1 (pq-cmd-tuples ?*inserted*))
(pq-clear ?*inserted*)

; The types come from the statement, not from the caller: an integer, a
; string and a float go out as text and the server reads them as the column
; types they are being compared with.
(defglobal ?*found* =
  (pq-exec-params ?*pconn* "SELECT label, mass FROM parts WHERE id = $1" (create$ 1)))
(expect "a parameterised SELECT finds the row" 1 (pq-ntuples ?*found*))
(expect "with the text that was sent" "flange" (pq-getvalue ?*found* 0 0))
(expect "and the number" "2.75" (pq-getvalue ?*found* 0 1))
(pq-clear ?*found*)

; nil is how a CLIPS program spells SQL NULL, in a parameter as everywhere
; else here.
(defglobal ?*null-param* =
  (pq-exec-params ?*pconn* "INSERT INTO parts VALUES ($1, $2, $3)"
                  (create$ 2 nil nil)))
(expect "nil goes out as SQL NULL" PGRES_COMMAND_OK (pq-result-status ?*null-param*))
(pq-clear ?*null-param*)

(defglobal ?*null-row* =
  (pq-exec-params ?*pconn* "SELECT label IS NULL FROM parts WHERE id = $1" (create$ 2)))
(expect "and the server agrees that it was one" "t" (pq-getvalue ?*null-row* 0 0))
(pq-clear ?*null-row*)

; TRUE goes out as the text true, which the server reads a boolean from.
; FALSE is the other spelling of nil here, and goes out as SQL NULL.
(defglobal ?*bool-params* =
  (pq-exec-params ?*pconn* "SELECT $1::boolean, $2::boolean IS NULL" (create$ TRUE FALSE)))
(expect "TRUE goes out as a boolean" "t" (pq-getvalue ?*bool-params* 0 0))
(expect "and FALSE as NULL, like nil" "t" (pq-getvalue ?*bool-params* 0 1))
(pq-clear ?*bool-params*)

; The parameters may be left out entirely, which is the same as sending none.
(defglobal ?*no-params* = (pq-exec-params ?*pconn* "SELECT 1"))
(expect "a command with no parameters needs no multifield"
        PGRES_TUPLES_OK (pq-result-status ?*no-params*))
(pq-clear ?*no-params*)

(defglobal ?*too-few* =
  (pq-exec-params ?*pconn* "SELECT $1::int, $2::int" (create$ 1)))
(expect "sending fewer parameters than the command uses is the server's error"
        PGRES_FATAL_ERROR (pq-result-status ?*too-few*))
; The bind message is short, which the server sees as a protocol violation
; rather than as anything about the SQL.
(expect "reported as a protocol violation"
        "08P01" (pq-result-error-field ?*too-few* PG_DIAG_SQLSTATE))
(pq-clear ?*too-few*)

; A parameter CLIPS has no text for at all -- an external address -- is
; refused before anything is sent.
(defglobal ?*unusable* =
  (pq-exec-params ?*pconn* "SELECT $1::int" (create$ ?*pconn*)))
(expect "a parameter with no printed form is refused" FALSE ?*unusable*)

; ----------------------------------------------------------------------
; Prepared statements
; ----------------------------------------------------------------------

(defglobal ?*prepared* =
  (pq-prepare ?*pconn* "by_id" "SELECT label FROM parts WHERE id = $1"))
(expect "pq-prepare prepares" PGRES_COMMAND_OK (pq-result-status ?*prepared*))
(pq-clear ?*prepared*)

(defglobal ?*described* = (pq-describe-prepared ?*pconn* "by_id"))
(expect "the prepared statement can be described"
        PGRES_COMMAND_OK (pq-result-status ?*described*))
(expect "it takes one parameter" 1 (pq-nparams ?*described*))
(expect "whose type the server inferred as integer" 23 (pq-paramtype ?*described* 0))
(expect "and it returns one column" 1 (pq-nfields ?*described*))
(expect "named for the column it selects" "label" (pq-fname ?*described* 0))

(defglobal ?*past-params* = (pq-paramtype ?*described* 1))
(expect "a parameter number past the last is refused" FALSE ?*past-params*)
(pq-clear ?*described*)

(defglobal ?*executed* = (pq-exec-prepared ?*pconn* "by_id" (create$ 1)))
(expect "the prepared statement runs" PGRES_TUPLES_OK (pq-result-status ?*executed*))
(expect "and finds the row" "flange" (pq-getvalue ?*executed* 0 0))
(pq-clear ?*executed*)

(defglobal ?*executed-again* = (pq-exec-prepared ?*pconn* "by_id" (create$ 2)))
(expect "and again with a different parameter"
        nil (pq-getvalue ?*executed-again* 0 0))
(pq-clear ?*executed-again*)

(defglobal ?*unprepared* = (pq-exec-prepared ?*pconn* "no_such_statement" (create$ 1)))
(expect "a statement that was never prepared is the server's error"
        PGRES_FATAL_ERROR (pq-result-status ?*unprepared*))
(pq-clear ?*unprepared*)

; Closing a prepared statement is tested in tests/pg17-test-suite.bat:
; pq-close-prepared arrived in PostgreSQL 17.

(pq-finish ?*pconn*)

; ======================================================================
; What PostgreSQL 17 added.
;
; Closing a prepared statement or a portal by name, chunked-rows mode,
; waiting on a socket, queueing a pipeline sync without flushing it, and
; changing a password without sending it. The cancel connection arrived in
; 17 as well and is big enough to have its own file, tests/cancel-test-suite.bat.
;
; See tests/pg16-test-suite.bat for why this is a file of its own. The drain
; and pipeline-statuses deffunctions come from tests/async-test-suite.bat and
; tests/pipeline-test-suite.bat, both batched before this one.
; ======================================================================

(println crlf "pg17-test-suite")

(defglobal ?*conn17* = (connect))

; ----------------------------------------------------------------------
; Closing a prepared statement by name
;
; Before this, a name could only be freed with DEALLOCATE, which is a
; command the server has to parse.
; ----------------------------------------------------------------------

(run-sql ?*conn17* "CREATE TEMP TABLE pg17_parts (id int, label text)")

(defglobal ?*prepared17* =
  (pq-prepare ?*conn17* "pg17_stmt" "SELECT label FROM pg17_parts WHERE id = $1"))
(pq-clear ?*prepared17*)

(defglobal ?*unprepare* = (pq-close-prepared ?*conn17* "pg17_stmt"))
(expect "pq-close-prepared closes a prepared statement"
        PGRES_COMMAND_OK (pq-result-status ?*unprepare*))
(pq-clear ?*unprepare*)

(defglobal ?*after-close* = (pq-describe-prepared ?*conn17* "pg17_stmt"))
(expect "after which the server does not have it"
        PGRES_FATAL_ERROR (pq-result-status ?*after-close*))
(pq-clear ?*after-close*)

; Closing something that is not there is not an error: the point of the call
; is that the name is free afterwards.
(defglobal ?*close-again* = (pq-close-prepared ?*conn17* "pg17_stmt"))
(expect "closing a statement that is already gone is not an error"
        PGRES_COMMAND_OK (pq-result-status ?*close-again*))
(pq-clear ?*close-again*)

; ----------------------------------------------------------------------
; And a portal
; ----------------------------------------------------------------------

(run-sql ?*conn17* "BEGIN")
(run-sql ?*conn17* "DECLARE pg17_cursor CURSOR FOR SELECT id FROM pg17_parts")

(defglobal ?*closed-portal* = (pq-close-portal ?*conn17* "pg17_cursor"))
(expect "pq-close-portal closes a portal"
        PGRES_COMMAND_OK (pq-result-status ?*closed-portal*))
(pq-clear ?*closed-portal*)

(defglobal ?*gone-portal* = (pq-describe-portal ?*conn17* "pg17_cursor"))
(expect "after which the server no longer has it"
        PGRES_FATAL_ERROR (pq-result-status ?*gone-portal*))
(pq-clear ?*gone-portal*)
(run-sql ?*conn17* "ROLLBACK")

; ----------------------------------------------------------------------
; The same two without waiting
; ----------------------------------------------------------------------

(defglobal ?*async-prepared* =
  (pq-prepare ?*conn17* "pg17_async" "SELECT $1::int"))
(pq-clear ?*async-prepared*)

(expect "pq-send-close-prepared sends the close"
        TRUE (pq-send-close-prepared ?*conn17* "pg17_async"))
(expect "and the answer is a command result"
        (create$ PGRES_COMMAND_OK) (drain ?*conn17*))

(run-sql ?*conn17* "BEGIN")
(run-sql ?*conn17* "DECLARE pg17_async_cursor CURSOR FOR SELECT 1")
(expect "pq-send-close-portal does the same for a portal"
        TRUE (pq-send-close-portal ?*conn17* "pg17_async_cursor"))
(expect "and answers the same way"
        (create$ PGRES_COMMAND_OK) (drain ?*conn17*))
(run-sql ?*conn17* "ROLLBACK")

; ----------------------------------------------------------------------
; Rows a chunk at a time
;
; Single-row mode was already there; this is the same idea with a size, so
; that a large result can be read without holding all of it and without a
; result object per row.
; ----------------------------------------------------------------------

(pq-send-query ?*conn17* "SELECT generate_series(1, 5)")
(expect "pq-set-chunked-rows-mode takes the size of the chunk"
        TRUE (pq-set-chunked-rows-mode ?*conn17* 2))
(expect "and the rows arrive in chunks of it, the last one short"
        (create$ PGRES_TUPLES_CHUNK PGRES_TUPLES_CHUNK PGRES_TUPLES_CHUNK PGRES_TUPLES_OK)
        (drain ?*conn17*))

(defglobal ?*zero-chunk* = (pq-set-chunked-rows-mode ?*conn17* 0))
(expect "a chunk of no rows is refused" FALSE ?*zero-chunk*)

; Chunked mode, like single-row mode, is a request about the command in
; flight: with nothing in flight libpq says no, without saying why.
(defglobal ?*chunked-idle* = (pq-set-chunked-rows-mode ?*conn17* 2))
(expect "and so is chunked mode asked for with nothing in flight" FALSE ?*chunked-idle*)

; ----------------------------------------------------------------------
; Waiting on a socket
;
; A clock in microseconds and a wait until a deadline, which is what a CLIPS
; program needs to wait for a query without spinning.
; ----------------------------------------------------------------------

(defglobal ?*now* = (pq-get-current-time-usec))
(expect-true "pq-get-current-time-usec is a positive number of microseconds"
             (> ?*now* 0))
(expect-true "and does not go backwards"
             (>= (pq-get-current-time-usec) ?*now*))

(pq-send-query ?*conn17* "SELECT pg_sleep(0.05), 1")

(defglobal ?*ready* =
  (pq-socket-poll (pq-socket ?*conn17*) TRUE FALSE
                  (+ (pq-get-current-time-usec) 5000000)))
(expect-true "the socket becomes readable while the query is running"
             (> ?*ready* 0))
(expect "and the query reads out as one result"
        (create$ PGRES_TUPLES_OK) (drain ?*conn17*))

; A deadline that has already passed is how to ask without waiting at all.
(defglobal ?*not-ready* = (pq-socket-poll (pq-socket ?*conn17*) TRUE FALSE 0))
(expect "polling with no time to wait answers at once" 0 ?*not-ready*)

; ----------------------------------------------------------------------
; Queueing a pipeline sync without sending it
; ----------------------------------------------------------------------

(pq-enter-pipeline-mode ?*conn17*)
(pq-send-query-params ?*conn17* "SELECT 1" (create$))
(expect "pq-send-pipeline-sync queues a sync" TRUE (pq-send-pipeline-sync ?*conn17*))
(expect "which pq-flush sends" TRUE (pq-flush ?*conn17*))
(expect "leaving the result and the sync to read"
        (create$ PGRES_TUPLES_OK end PGRES_PIPELINE_SYNC)
        (pipeline-statuses ?*conn17* 10))
(pq-exit-pipeline-mode ?*conn17*)

; ----------------------------------------------------------------------
; Changing a password without sending it
;
; pq-change-password encrypts on this side, so the password itself never
; reaches the server or its log. The role is made here and dropped again; a
; server where this connection cannot make roles says so, and the wrapper is
; exercised either way.
; ----------------------------------------------------------------------

(defglobal ?*made-role* = (pq-exec ?*conn17* "CREATE ROLE clipspg_password_test LOGIN"))
(defglobal ?*can-make-roles* = (eq (pq-result-status ?*made-role*) PGRES_COMMAND_OK))
(pq-clear ?*made-role*)

(if ?*can-make-roles*
 then
   (defglobal ?*changed* =
     (pq-change-password ?*conn17* "clipspg_password_test" "hunter2"))
   (expect "pq-change-password changes it"
           PGRES_COMMAND_OK (pq-result-status ?*changed*))
   (pq-clear ?*changed*)
   (run-sql ?*conn17* "DROP ROLE clipspg_password_test"))

(defglobal ?*no-such-role* =
  (pq-change-password ?*conn17* "clipspg_no_such_role" "hunter2"))
(expect "and a role that does not exist is the server's error"
        PGRES_FATAL_ERROR (pq-result-status ?*no-such-role*))
(pq-clear ?*no-such-role*)

; ----------------------------------------------------------------------
; Arguments these refuse
;
; The rest of the argument guards are in tests/arg-guard-test-suite.bat;
; these are here because the functions they name do not exist before 17.
; ----------------------------------------------------------------------

(defglobal ?*guard17* = FALSE)
(defglobal ?*not-a-socket* = "not a socket")
(defglobal ?*not-a-handle* = 42)

(bind ?*guard17* (pq-socket-poll ?*not-a-socket* TRUE FALSE 0))
(expect "pq-socket-poll refuses a string where a socket belongs" FALSE ?*guard17*)

(bind ?*guard17* (pq-cancel-finish ?*not-a-handle*))
(expect "pq-cancel-finish refuses an integer" FALSE ?*guard17*)

(bind ?*guard17* (pq-change-password ?*conn17* ?*not-a-handle* "hunter2"))
(expect "pq-change-password refuses an integer where the user name belongs" FALSE ?*guard17*)

(defglobal ?*emptied17* = (connect))
(pq-finish ?*emptied17*)

(bind ?*guard17* (pq-cancel-create ?*emptied17*))
(expect "pq-cancel-create refuses an emptied connection" FALSE ?*guard17*)

(bind ?*guard17* (pq-change-password ?*emptied17* "someone" "hunter2"))
(expect "pq-change-password refuses one too" FALSE ?*guard17*)

(bind ?*guard17* (pq-set-chunked-rows-mode ?*emptied17* 2))
(expect "and so does pq-set-chunked-rows-mode" FALSE ?*guard17*)

(pq-finish ?*conn17*)

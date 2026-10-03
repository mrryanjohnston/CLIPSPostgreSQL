; ======================================================================
; Sending a command without waiting for it.
;
; The whole of this interface is one loop: send, then read results until
; there are none left. A program that stops reading early leaves the
; connection with a result still on it and the next command will refuse.
; ======================================================================

(println crlf "async-test-suite")

(defglobal ?*aconn* = (connect))

; Reads every result the connection still owes and answers with their
; statuses in order. FALSE from pq-get-result is the end of the command, not
; a failure, which is what makes this loop terminate.
(deffunction drain (?conn)
  (bind ?statuses (create$))
  (bind ?res (pq-get-result ?conn))
  (while ?res
    (bind ?statuses (create$ ?statuses (pq-result-status ?res)))
    (pq-clear ?res)
    (bind ?res (pq-get-result ?conn)))
  ?statuses)

; ----------------------------------------------------------------------
; One command, one result
; ----------------------------------------------------------------------

(expect "pq-send-query sends" TRUE (pq-send-query ?*aconn* "SELECT 1"))
(expect "and the command produces one result"
        (create$ PGRES_TUPLES_OK) (drain ?*aconn*))

; A connection with a command in flight will not take another one.
(pq-send-query ?*aconn* "SELECT 1")
(defglobal ?*while-busy* = (pq-send-query ?*aconn* "SELECT 2"))
(expect "a second command sent before the first is read is refused"
        FALSE ?*while-busy*)
(drain ?*aconn*)

; ----------------------------------------------------------------------
; Several commands in one string, which is the reason results come one at a
; time rather than all at once
; ----------------------------------------------------------------------

(pq-send-query ?*aconn* "SELECT 1; SELECT 2; CREATE TEMP TABLE t (i int)")
(expect "three commands produce three results, in order"
        (create$ PGRES_TUPLES_OK PGRES_TUPLES_OK PGRES_COMMAND_OK)
        (drain ?*aconn*))

; ----------------------------------------------------------------------
; The other send-side calls
; ----------------------------------------------------------------------

(expect "pq-send-query-params sends a parameterised command"
        TRUE (pq-send-query-params ?*aconn* "SELECT $1::int" (create$ 7)))
(expect "which produces one result"
        (create$ PGRES_TUPLES_OK) (drain ?*aconn*))

(expect "pq-send-prepare prepares without waiting"
        TRUE (pq-send-prepare ?*aconn* "async_stmt" "SELECT $1::int"))
(expect "and says so with a command result"
        (create$ PGRES_COMMAND_OK) (drain ?*aconn*))

(expect "pq-send-describe-prepared asks about it"
        TRUE (pq-send-describe-prepared ?*aconn* "async_stmt"))
(expect "and the answer is a command result too"
        (create$ PGRES_COMMAND_OK) (drain ?*aconn*))

(expect "pq-send-query-prepared runs it"
        TRUE (pq-send-query-prepared ?*aconn* "async_stmt" (create$ 3)))
(expect "and returns rows" (create$ PGRES_TUPLES_OK) (drain ?*aconn*))

; pq-send-close-prepared and pq-send-close-portal are tested in
; tests/pg17-test-suite.bat: both arrived in PostgreSQL 17.
(run-sql ?*aconn* "DEALLOCATE async_stmt")

(run-sql ?*aconn* "BEGIN")
(run-sql ?*aconn* "DECLARE async_cursor CURSOR FOR SELECT 1")
(expect "pq-send-describe-portal asks about a portal"
        TRUE (pq-send-describe-portal ?*aconn* "async_cursor"))
(expect "and answers" (create$ PGRES_COMMAND_OK) (drain ?*aconn*))
(run-sql ?*aconn* "ROLLBACK")

; ----------------------------------------------------------------------
; Watching the socket, which is the point of sending this way
; ----------------------------------------------------------------------

(pq-send-query ?*aconn* "SELECT pg_sleep(0.05), 1")

(expect-true "the connection has a socket to wait on" (> (pq-socket ?*aconn*) 0))

(expect "pq-consume-input takes what has arrived" TRUE (pq-consume-input ?*aconn*))

; Reading input until the connection is no longer busy is what a program
; that had other things to do would be doing between these calls.
; wait-for-input waits on the socket where this libpq can (17 and later) and
; simply asks for input where it cannot; either way the loop ends when the
; answer has arrived.
(deffunction wait-until-idle (?conn)
  (while (pq-is-busy ?conn)
    (wait-for-input ?conn))
  TRUE)

(expect "and waiting on it ends with a result ready" TRUE (wait-until-idle ?*aconn*))
(expect "which reads out as one result"
        (create$ PGRES_TUPLES_OK) (drain ?*aconn*))
(expect "after which the connection is not busy" FALSE (pq-is-busy ?*aconn*))

; ----------------------------------------------------------------------
; Non-blocking mode
; ----------------------------------------------------------------------

(expect "a connection starts out blocking" FALSE (pq-isnonblocking ?*aconn*))
(expect "and can be made non-blocking" TRUE (pq-setnonblocking ?*aconn* TRUE))
(expect "which it then reports" TRUE (pq-isnonblocking ?*aconn*))

(pq-send-query ?*aconn* "SELECT 1")
(defglobal ?*flushed* = (pq-flush ?*aconn*))
(expect-true "pq-flush either finishes or says there is more to send"
             (or (eq ?*flushed* TRUE) (eq ?*flushed* busy)))
(drain ?*aconn*)

(expect "and it can be put back" TRUE (pq-setnonblocking ?*aconn* FALSE))
(expect "which it reports too" FALSE (pq-isnonblocking ?*aconn*))

; ----------------------------------------------------------------------
; Row at a time, and a chunk at a time
;
; Both change what pq-get-result hands back rather than what is sent: the
; rows arrive as several results instead of one.
; ----------------------------------------------------------------------

(pq-send-query ?*aconn* "SELECT generate_series(1, 3)")
(expect "pq-set-single-row-mode is accepted after the command is sent"
        TRUE (pq-set-single-row-mode ?*aconn*))
(expect "and each row comes back as its own result, followed by the end"
        (create$ PGRES_SINGLE_TUPLE PGRES_SINGLE_TUPLE PGRES_SINGLE_TUPLE PGRES_TUPLES_OK)
        (drain ?*aconn*))

; Chunked-rows mode is tested in tests/pg17-test-suite.bat:
; pq-set-chunked-rows-mode arrived in PostgreSQL 17.

; ----------------------------------------------------------------------
; Sending while a command is in flight
;
; Every send-side call refuses while the results of the last one are still
; to be read, and says so with libpq's message.
; ----------------------------------------------------------------------

(pq-send-query ?*aconn* "SELECT 1")

(defglobal ?*sent-while-busy* = (pq-send-query-params ?*aconn* "SELECT 2" (create$)))
(expect "pq-send-query-params is refused while a command is in flight"
        FALSE ?*sent-while-busy*)

(bind ?*sent-while-busy* (pq-send-prepare ?*aconn* "busy_stmt" "SELECT 2"))
(expect "so is pq-send-prepare" FALSE ?*sent-while-busy*)

(bind ?*sent-while-busy* (pq-send-query-prepared ?*aconn* "busy_stmt" (create$)))
(expect "and pq-send-query-prepared" FALSE ?*sent-while-busy*)

(expect "and the command in flight still reads out"
        (create$ PGRES_TUPLES_OK) (drain ?*aconn*))

; Single-row mode is a request about the command in flight, made after the
; send and before the first result. With nothing in flight there is nothing
; to ask it of, and libpq says no without saying why.
(defglobal ?*single-row-idle* = (pq-set-single-row-mode ?*aconn*))
(expect "pq-set-single-row-mode is refused with no command in flight"
        FALSE ?*single-row-idle*)

; ----------------------------------------------------------------------
; Output the socket cannot take at once
;
; In non-blocking mode a send queues what the socket would not take, and
; pq-flush answers busy until the socket has taken it. A parameter of 32
; megabytes is more than any socket buffer holds, and more than the server
; reads back between two calls from here, so the flush is still busy when
; asked -- and a return to blocking mode, which has to flush first, is
; refused until the output is gone.
; ----------------------------------------------------------------------

(defglobal ?*big* = "xxxxxxxxxxxxxxxx")
(loop-for-count 21 (bind ?*big* (str-cat ?*big* ?*big*)))
(expect "the parameter is 32 megabytes" 33554432 (str-length ?*big*))

(pq-setnonblocking ?*aconn* TRUE)
(expect "the send is accepted with the data still queued"
        TRUE (pq-send-query-params ?*aconn* "SELECT length($1)" (create$ ?*big*)))
(expect "pq-flush says busy while the socket will not take the rest"
        busy (pq-flush ?*aconn*))

(defglobal ?*blocking-refused* = (pq-setnonblocking ?*aconn* FALSE))
(expect "and blocking mode cannot be restored until it has" FALSE ?*blocking-refused*)

; Reading the result sends whatever is still queued first, and waits for
; the socket to take it.
(defglobal ?*big-result* = (pq-get-result ?*aconn*))
(expect "the server got all of it" "33554432" (pq-getvalue ?*big-result* 0 0))
(pq-clear ?*big-result*)
(pq-get-result ?*aconn*)

(expect "after which blocking mode can be restored" TRUE (pq-setnonblocking ?*aconn* FALSE))
(expect "and the connection is back to blocking" FALSE (pq-isnonblocking ?*aconn*))

(pq-finish ?*aconn*)

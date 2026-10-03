; ======================================================================
; COPY, in both directions.
;
; A COPY leaves the connection in a state where ordinary commands are
; refused until the copy is finished, which is what most of this is about:
; the result that starts it, the data, and the result that ends it.
; ======================================================================

(println crlf "copy-test-suite")

(defglobal ?*copyconn* = (connect))

; COPY data is separated by tabs and terminated by newlines, and CLIPS
; string literals have no escape for either: (format nil ...) is where those
; two characters come from.
(defglobal ?*tab* = (format nil "%t"))
(defglobal ?*newline* = (format nil "%n"))

(run-sql ?*copyconn* "CREATE TEMP TABLE parts_in (id int, label text)")

; ----------------------------------------------------------------------
; Into the server
; ----------------------------------------------------------------------

(defglobal ?*copy-in* = (pq-exec ?*copyconn* "COPY parts_in FROM STDIN"))
(expect "COPY FROM STDIN puts the connection into copy-in state"
        PGRES_COPY_IN (pq-result-status ?*copy-in*))
(pq-clear ?*copy-in*)

(expect "a row goes in"
        TRUE (pq-put-copy-data ?*copyconn* (str-cat "1" ?*tab* "flange" ?*newline*)))
(expect "and another"
        TRUE (pq-put-copy-data ?*copyconn* (str-cat "2" ?*tab* "bolt" ?*newline*)))

; The data need not be split at row boundaries: the server reassembles it.
(expect "and half a row" TRUE (pq-put-copy-data ?*copyconn* (str-cat "3" ?*tab*)))
(expect "followed by the rest of it"
        TRUE (pq-put-copy-data ?*copyconn* (str-cat "nut" ?*newline*)))

(expect "pq-put-copy-end finishes the copy" TRUE (pq-put-copy-end ?*copyconn*))

(defglobal ?*copy-in-result* = (pq-get-result ?*copyconn*))
(expect "which the server confirms with a command result"
        PGRES_COMMAND_OK (pq-result-status ?*copy-in-result*))
(expect "counting the rows it took" 3 (pq-cmd-tuples ?*copy-in-result*))
(pq-clear ?*copy-in-result*)

(expect "and the rows are in the table" "3" (scalar ?*copyconn* "SELECT count(*) FROM parts_in"))

; ----------------------------------------------------------------------
; Out of the server
; ----------------------------------------------------------------------

(defglobal ?*copy-out* =
  (pq-exec ?*copyconn* "COPY (SELECT id, label FROM parts_in ORDER BY id) TO STDOUT"))
(expect "COPY TO STDOUT puts the connection into copy-out state"
        PGRES_COPY_OUT (pq-result-status ?*copy-out*))
(pq-clear ?*copy-out*)

; One call, one row, until the symbol done says there are no more.
(deffunction copy-rows (?conn)
  (bind ?rows (create$))
  (bind ?row (pq-get-copy-data ?conn))
  (while (and (neq ?row done) (neq ?row FALSE))
    (bind ?rows (create$ ?rows ?row))
    (bind ?row (pq-get-copy-data ?conn)))
  ?rows)

(defglobal ?*rows-out* = (copy-rows ?*copyconn*))

(expect "every row comes back" 3 (length$ ?*rows-out*))
(expect "as the text the server prints, newline and all"
        (str-cat "1" ?*tab* "flange" ?*newline*) (nth$ 1 ?*rows-out*))
(expect "in the order the query asked for"
        (str-cat "3" ?*tab* "nut" ?*newline*) (nth$ 3 ?*rows-out*))

(defglobal ?*copy-out-result* = (pq-get-result ?*copyconn*))
(expect "and the copy ends with a command result"
        PGRES_COMMAND_OK (pq-result-status ?*copy-out-result*))
(pq-clear ?*copy-out-result*)

(expect "after which the connection takes commands again"
        "3" (scalar ?*copyconn* "SELECT count(*) FROM parts_in"))

; ----------------------------------------------------------------------
; Asking for data that has not arrived
;
; pq-get-copy-data waits for the next row unless told not to: with TRUE for
; the async flag it answers busy when the server has sent nothing yet,
; which is what a program with other things to do wants to hear. The server
; here sleeps before each row, and a row wide enough to have been sent on
; its own is what keeps the two apart.
; ----------------------------------------------------------------------

(defglobal ?*slow-copy* =
  (pq-exec ?*copyconn*
    "COPY (SELECT repeat('x', 20000), pg_sleep(0.3) FROM generate_series(1, 2)) TO STDOUT"))
(expect "a slow copy starts like any other" PGRES_COPY_OUT (pq-result-status ?*slow-copy*))
(pq-clear ?*slow-copy*)

(expect-true "the first row arrives when waited for"
             (stringp (pq-get-copy-data ?*copyconn*)))
(expect "asked for without waiting, the second row is not there yet"
        busy (pq-get-copy-data ?*copyconn* TRUE))
(expect-true "waited for, it arrives" (stringp (pq-get-copy-data ?*copyconn*)))
(expect "and then the copy is done" done (pq-get-copy-data ?*copyconn*))

(defglobal ?*slow-copy-result* = (pq-get-result ?*copyconn*))
(expect "with a command result to close it"
        PGRES_COMMAND_OK (pq-result-status ?*slow-copy-result*))
(pq-clear ?*slow-copy-result*)

(expect "and the connection takes commands again"
        "3" (scalar ?*copyconn* "SELECT count(*) FROM parts_in"))

; ----------------------------------------------------------------------
; A copy the client abandons
;
; The error message passed to pq-put-copy-end is what the server raises, so
; a client that finds bad data half way through says so rather than
; committing what it has already sent.
; ----------------------------------------------------------------------

(defglobal ?*aborted-copy* = (pq-exec ?*copyconn* "COPY parts_in FROM STDIN"))
(expect "another copy starts" PGRES_COPY_IN (pq-result-status ?*aborted-copy*))
(pq-clear ?*aborted-copy*)

(pq-put-copy-data ?*copyconn* (str-cat "4" ?*tab* "spare" ?*newline*))
(expect "and is ended with a complaint instead of a commit"
        TRUE (pq-put-copy-end ?*copyconn* "the client changed its mind"))

(defglobal ?*aborted-result* = (pq-get-result ?*copyconn*))
(expect "which the server reports as the failure it was"
        PGRES_FATAL_ERROR (pq-result-status ?*aborted-result*))
(expect "with the message the client gave it"
        "57014" (pq-result-error-field ?*aborted-result* PG_DIAG_SQLSTATE))
(pq-clear ?*aborted-result*)

(expect "and the row that was sent is not in the table"
        "3" (scalar ?*copyconn* "SELECT count(*) FROM parts_in"))

; ----------------------------------------------------------------------
; Copy data where there is no copy
; ----------------------------------------------------------------------

(defglobal ?*no-copy* = (pq-put-copy-data ?*copyconn* (str-cat "1" ?*tab* "nowhere" ?*newline*)))
(expect "sending copy data outside a copy is refused" FALSE ?*no-copy*)

(defglobal ?*no-copy-out* = (pq-get-copy-data ?*copyconn*))
(expect "and so is asking for it" FALSE ?*no-copy-out*)

(pq-finish ?*copyconn*)

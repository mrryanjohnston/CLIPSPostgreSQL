; ======================================================================
; Canceling a query that is already running.
;
; The cancel goes over a connection of its own -- the one the query is on is
; busy -- which is why this is a handle with its own status and its own
; socket rather than a single call.
; ======================================================================

(println crlf "cancel-test-suite")

(defglobal ?*cconn* = (connect))

; The SQLSTATE of the last result read below, which is the part of a
; canceled query worth asserting on.
(defglobal ?*sqlstate* = FALSE)

; The statuses of everything the connection still owes, which after a cancel
; is the error the server raised in place of the result.
(deffunction results-after-cancel (?conn)
  (bind ?statuses (create$))
  (bind ?res (pq-get-result ?conn))
  (while ?res
    (bind ?statuses (create$ ?statuses (pq-result-status ?res)))
    (bind ?*sqlstate* (pq-result-error-field ?res PG_DIAG_SQLSTATE))
    (pq-clear ?res)
    (bind ?res (pq-get-result ?conn)))
  ?statuses)

; ----------------------------------------------------------------------
; The blocking form
; ----------------------------------------------------------------------

(expect "a long query is sent" TRUE (pq-send-query ?*cconn* "SELECT pg_sleep(30)"))

(defglobal ?*cancel* = (pq-cancel-create ?*cconn*))
(expect-true "pq-cancel-create makes a cancel connection" (neq FALSE ?*cancel*))
(expect "which has not connected to anything yet"
        CONNECTION_ALLOCATED (pq-cancel-status ?*cancel*))
(expect "and so has no error to report" FALSE (pq-cancel-error-message ?*cancel*))

(expect "pq-cancel-blocking sends the request and waits for it"
        TRUE (pq-cancel-blocking ?*cancel*))

(expect "the query comes back as an error rather than a result"
        (create$ PGRES_FATAL_ERROR) (results-after-cancel ?*cconn*))
(expect "with the SQLSTATE the server uses for a canceled statement"
        "57014" ?*sqlstate*)

; ----------------------------------------------------------------------
; The same thing without blocking
; ----------------------------------------------------------------------

(expect "a cancel connection is reusable once it is reset"
        TRUE (pq-cancel-reset ?*cancel*))
(expect "which puts it back where it started"
        CONNECTION_ALLOCATED (pq-cancel-status ?*cancel*))

(pq-send-query ?*cconn* "SELECT pg_sleep(30)")

(expect "pq-cancel-start starts the request" TRUE (pq-cancel-start ?*cancel*))
(expect-true "which opens a socket to wait on" (> (pq-cancel-socket ?*cancel*) 0))

; Polling a cancel connection through is the same loop as polling a
; connection through: ask, wait on the socket, ask again.
(deffunction poll-cancel (?cancel)
  (bind ?state (pq-cancel-poll ?cancel))
  (while (and (neq ?state PGRES_POLLING_OK) (neq ?state PGRES_POLLING_FAILED))
    (pq-socket-poll (pq-cancel-socket ?cancel)
                    (eq ?state PGRES_POLLING_READING)
                    (eq ?state PGRES_POLLING_WRITING)
                    (+ (pq-get-current-time-usec) 5000000))
    (bind ?state (pq-cancel-poll ?cancel)))
  ?state)

(expect "and polling it through delivers the cancel"
        PGRES_POLLING_OK (poll-cancel ?*cancel*))
(expect "leaving the cancel connection good" CONNECTION_OK (pq-cancel-status ?*cancel*))

(expect "and this query was canceled too"
        (create$ PGRES_FATAL_ERROR) (results-after-cancel ?*cconn*))
(expect "with the same SQLSTATE" "57014" ?*sqlstate*)

; ----------------------------------------------------------------------
; Closing it
; ----------------------------------------------------------------------

(expect "pq-cancel-finish closes the cancel connection" TRUE (pq-cancel-finish ?*cancel*))

(defglobal ?*finish-again* = (pq-cancel-finish ?*cancel*))
(expect "and a second close is refused" FALSE ?*finish-again*)

(defglobal ?*after-finish* = (pq-cancel-status ?*cancel*))
(expect "as is anything else asked of it" FALSE ?*after-finish*)

(bind ?*after-finish* (pq-cancel-blocking ?*cancel*))
(expect "pq-cancel-blocking refuses an emptied handle" FALSE ?*after-finish*)

(bind ?*after-finish* (pq-cancel-start ?*cancel*))
(expect "so does pq-cancel-start" FALSE ?*after-finish*)

(bind ?*after-finish* (pq-cancel-poll ?*cancel*))
(expect "and pq-cancel-poll" FALSE ?*after-finish*)

(bind ?*after-finish* (pq-cancel-socket ?*cancel*))
(expect "and pq-cancel-socket" FALSE ?*after-finish*)

(bind ?*after-finish* (pq-cancel-reset ?*cancel*))
(expect "and pq-cancel-reset" FALSE ?*after-finish*)

; ----------------------------------------------------------------------
; A cancel connection for a connection that was never made
;
; pq-cancel-create copies what it needs from the connection, and a
; connection with no socket has nothing to copy: the cancel connection
; exists, says CONNECTION_BAD, and carries libpq's reason. Everything that
; would send the request refuses on it.
; ----------------------------------------------------------------------

(defglobal ?*never-made* = (pq-connectdb "host=/nonexistent-socket-dir connect_timeout=1"))
(defglobal ?*hopeless* = (pq-cancel-create ?*never-made*))

(expect-true "a cancel connection is made even for a connection that was not"
             (neq FALSE ?*hopeless*))
(expect "and it is bad from the start" CONNECTION_BAD (pq-cancel-status ?*hopeless*))
(expect-true "with a message saying why" (stringp (pq-cancel-error-message ?*hopeless*)))

(defglobal ?*hopeless-result* = (pq-cancel-socket ?*hopeless*))
(expect "it has no socket" FALSE ?*hopeless-result*)

(bind ?*hopeless-result* (pq-cancel-blocking ?*hopeless*))
(expect "pq-cancel-blocking refuses to send on it" FALSE ?*hopeless-result*)

(bind ?*hopeless-result* (pq-cancel-start ?*hopeless*))
(expect "and so does pq-cancel-start" FALSE ?*hopeless-result*)

(pq-cancel-finish ?*hopeless*)
(pq-finish ?*never-made*)

; The connection itself is untouched by all of this.
(expect "the connection the queries were canceled on is still good"
        CONNECTION_OK (pq-status ?*cconn*))
(expect "and still runs commands" "1" (scalar ?*cconn* "SELECT 1"))

(pq-finish ?*cconn*)

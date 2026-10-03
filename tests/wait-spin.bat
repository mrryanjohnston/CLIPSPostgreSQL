; ======================================================================
; Waiting, on PostgreSQL 16 and earlier.
;
; pq-socket-poll and pq-get-current-time-usec arrived in 17, so there is
; nothing here to wait on a socket with: these ask the connection for input
; rather than waiting for it to arrive, and the callers are written to ask
; more than once.
;
; tests/wait-poll.bat is the same two functions for a libpq that has the
; waiting, and tests/test.bat batches whichever one this libpq calls for.
; ======================================================================

(deffunction wait-for-input (?conn)
  (pq-consume-input ?conn))

(deffunction poll-connection (?conn)
  (bind ?state (pq-connect-poll ?conn))
  (while (and (neq ?state PGRES_POLLING_OK) (neq ?state PGRES_POLLING_FAILED))
    (bind ?state (pq-connect-poll ?conn)))
  ?state)

; ======================================================================
; Waiting, on PostgreSQL 17 and later.
;
; pq-socket-poll arrived in 17. Where it is there, waiting for a connection
; to have something to say is a wait on its socket, which is what a program
; with other things to do would write.
;
; tests/wait-spin.bat is the same two functions for an older libpq, and
; tests/test.bat batches whichever one this libpq calls for.
; ======================================================================

; Waits until the connection has input to read, or a second passes, and
; takes whatever arrived.
(deffunction wait-for-input (?conn)
  (pq-socket-poll (pq-socket ?conn) TRUE FALSE
                  (+ (pq-get-current-time-usec) 1000000))
  (pq-consume-input ?conn))

; Carries a connection being made without blocking through to whatever it
; ends up as, waiting on the socket the way each state asks to be waited on.
(deffunction poll-connection (?conn)
  (bind ?state (pq-connect-poll ?conn))
  (while (and (neq ?state PGRES_POLLING_OK) (neq ?state PGRES_POLLING_FAILED))
    (pq-socket-poll (pq-socket ?conn)
                    (eq ?state PGRES_POLLING_READING)
                    (eq ?state PGRES_POLLING_WRITING)
                    (+ (pq-get-current-time-usec) 5000000))
    (bind ?state (pq-connect-poll ?conn)))
  ?state)

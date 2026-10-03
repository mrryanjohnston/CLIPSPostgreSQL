; ======================================================================
; What PostgreSQL 16 added.
;
; tests/test.bat batches this only where the libpq being built against has
; it, because the wrapper for it is not compiled in anywhere else -- and
; CLIPS resolves the name of a function when it reads the call, so a file
; that mentions one an older build does not have cannot be read at all.
; ======================================================================

(println crlf "pg16-test-suite")

(defglobal ?*conn16* = (connect))

; PQconnectionUsedGSSAPI joins the pair that were already there:
; pq-connection-needs-password and pq-connection-used-password.
(expect "a Unix socket connection did not authenticate with GSSAPI"
        FALSE (pq-connection-used-gssapi ?*conn16*))

(defglobal ?*gssapi-emptied* = (connect))
(pq-finish ?*gssapi-emptied*)
(defglobal ?*gssapi-refused* = (pq-connection-used-gssapi ?*gssapi-emptied*))
(expect "and an emptied connection is refused, as everywhere else"
        FALSE ?*gssapi-refused*)

(pq-finish ?*conn16*)

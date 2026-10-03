; ======================================================================
; What PostgreSQL 18 added.
;
; See tests/pg16-test-suite.bat for why this is a file of its own.
; ======================================================================

(println crlf "pg18-test-suite")

(defglobal ?*conn18* = (connect))

; PQprotocolVersion has always answered 3. PQfullProtocolVersion answers the
; minor version too, which is what a client has to look at now that there is
; a 3.2 to tell from a 3.0.
(expect "the protocol is still version 3" 3 (pq-protocol-version ?*conn18*))
(expect-true "and its minor version is readable"
             (>= (pq-full-protocol-version ?*conn18*) 30000))
(expect-true "which agrees with the major version it belongs to"
             (= 3 (div (pq-full-protocol-version ?*conn18*) 10000)))

(defglobal ?*protocol-emptied* = (connect))
(pq-finish ?*protocol-emptied*)
(defglobal ?*protocol-refused* = (pq-full-protocol-version ?*protocol-emptied*))
(expect "an emptied connection is refused" FALSE ?*protocol-refused*)

(pq-finish ?*conn18*)

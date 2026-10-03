; ======================================================================
; A connection that was made, and everything readable from it.
; ======================================================================

(println crlf "connect-test-suite")

(defglobal ?*conn* = (connect))

(expect "a connection to the test server is good"
        CONNECTION_OK (pq-status ?*conn*))

(expect "the database is the one the connection string named"
        "postgres" (pq-db ?*conn*))

(expect-true "the user is readable" (stringp (pq-user ?*conn*)))
; Trust authentication sends no password, and libpq answers with the empty
; string rather than refusing.
(expect-true "so is the password, such as it is" (stringp (pq-pass ?*conn*)))
(expect-true "the host is readable" (stringp (pq-host ?*conn*)))
(expect-true "the port is readable" (stringp (pq-port ?*conn*)))

; A connection over a Unix socket has no address of its own, and libpq says
; so with an empty string rather than by refusing.
(expect-true "the host address is readable"
             (or (eq FALSE (pq-hostaddr ?*conn*)) (stringp (pq-hostaddr ?*conn*))))

(expect "no command-line options were passed to the backend"
        "" (pq-options ?*conn*))

(expect-true "the server is PostgreSQL 18 or later"
             (>= (pq-server-version ?*conn*) 180000))
(expect "the frontend/backend protocol is version 3"
        3 (pq-protocol-version ?*conn*))

(expect-true "the connection has an open socket" (> (pq-socket ?*conn*) 0))
(expect-true "and a backend process behind it" (> (pq-backend-pid ?*conn*) 0))

(expect "a connection with nothing running on it is idle"
        PQTRANS_IDLE (pq-transaction-status ?*conn*))

; ----------------------------------------------------------------------
; Parameters the server reported at startup
; ----------------------------------------------------------------------

(expect-true "the server reported its version as a parameter"
             (stringp (pq-parameter-status ?*conn* "server_version")))
(expect "the client encoding was set to UTF8 by initdb"
        "UTF8" (pq-parameter-status ?*conn* "client_encoding"))
(expect "a parameter the server never sent has no value"
        FALSE (pq-parameter-status ?*conn* "no_such_parameter"))

; ----------------------------------------------------------------------
; How the connection was authenticated and protected
; ----------------------------------------------------------------------

(expect "a trust-authenticated connection needed no password"
        FALSE (pq-connection-needs-password ?*conn*))
(expect "and used none" FALSE (pq-connection-used-password ?*conn*))
(expect "a Unix socket connection is not encrypted with SSL"
        FALSE (pq-ssl-in-use ?*conn*))
(expect "nor with GSSAPI" FALSE (pq-gss-enc-in-use ?*conn*))

(defglobal ?*ssl-names* = (pq-ssl-attribute-names ?*conn*))
(expect-true "the SSL attribute names are a multifield, empty or not"
             (>= (length$ ?*ssl-names*) 0))
(expect-true "an SSL attribute of a connection with no SSL has no value"
             (eq FALSE (pq-ssl-attribute ?*conn* "cipher")))

; ----------------------------------------------------------------------
; Encoding
; ----------------------------------------------------------------------

(defglobal ?*encoding* = (pq-client-encoding ?*conn*))
(expect-true "the client encoding has an id" (>= ?*encoding* 0))

(expect "the client encoding can be changed"
        TRUE (pq-set-client-encoding ?*conn* "LATIN1"))
(expect "and the change is visible"
        "LATIN1" (pq-parameter-status ?*conn* "client_encoding"))
(expect "and changed back" TRUE (pq-set-client-encoding ?*conn* "UTF8"))

(defglobal ?*bad-encoding* = (pq-set-client-encoding ?*conn* "NOT_AN_ENCODING"))
(expect "an encoding the server does not have is refused"
        FALSE ?*bad-encoding*)

; ----------------------------------------------------------------------
; What the connection was built from
; ----------------------------------------------------------------------

(defglobal ?*live-conninfo* = (pq-conninfo ?*conn*))
(expect "pq-conninfo reads the live connection's own settings back"
        "postgres" (conninfo-value ?*live-conninfo* dbname))

; ----------------------------------------------------------------------
; Transaction status follows what the connection is doing
; ----------------------------------------------------------------------

(run-sql ?*conn* "BEGIN")
(expect "inside a transaction the status says so"
        PQTRANS_INTRANS (pq-transaction-status ?*conn*))

(defglobal ?*broken* = (pq-exec ?*conn* "SELECT nonexistent_column_xyz"))
(expect "a statement the server rejected leaves the transaction in error"
        PQTRANS_INERROR (pq-transaction-status ?*conn*))
(pq-clear ?*broken*)

(run-sql ?*conn* "ROLLBACK")
(expect "and rolling back returns it to idle"
        PQTRANS_IDLE (pq-transaction-status ?*conn*))

; ----------------------------------------------------------------------
; Error verbosity, which the connection remembers and reports back
; ----------------------------------------------------------------------

(defglobal ?*previous-verbosity* = (pq-set-error-verbosity ?*conn* PQERRORS_VERBOSE))
(expect "pq-set-error-verbosity answers with the setting it replaced"
        PQERRORS_DEFAULT ?*previous-verbosity*)
(expect "and the next change reports the one just made"
        PQERRORS_VERBOSE (pq-set-error-verbosity ?*conn* PQERRORS_DEFAULT))

(defglobal ?*previous-context* =
  (pq-set-error-context-visibility ?*conn* PQSHOW_CONTEXT_ALWAYS))
(expect "pq-set-error-context-visibility does the same"
        PQSHOW_CONTEXT_ERRORS ?*previous-context*)
(pq-set-error-context-visibility ?*conn* PQSHOW_CONTEXT_ERRORS)

(defglobal ?*bad-verbosity* = (pq-set-error-verbosity ?*conn* PQERRORS_LOUD))
(expect "a verbosity libpq does not have is refused" FALSE ?*bad-verbosity*)

; ----------------------------------------------------------------------
; Passwords the server would accept, computed without sending one
; ----------------------------------------------------------------------

(defglobal ?*encrypted* = (pq-encrypt-password-conn ?*conn* "hunter2" "someone"))
(expect-true "pq-encrypt-password-conn returns a verifier"
             (and (stringp ?*encrypted*) (> (str-length ?*encrypted*) 0)))
(expect "and it is a SCRAM verifier, which is what the server asks for"
        "SCRAM-SHA-256" (sub-string 1 13 ?*encrypted*))

(defglobal ?*bad-algorithm* =
  (pq-encrypt-password-conn ?*conn* "hunter2" "someone" "rot13"))
(expect "an algorithm the server does not have is refused" FALSE ?*bad-algorithm*)

; ----------------------------------------------------------------------
; Reconnecting
; ----------------------------------------------------------------------

(defglobal ?*pid-before* = (pq-backend-pid ?*conn*))
(expect "pq-reset reconnects" TRUE (pq-reset ?*conn*))
(expect "and the connection is good again" CONNECTION_OK (pq-status ?*conn*))
(expect-true "on a different backend than before"
             (neq ?*pid-before* (pq-backend-pid ?*conn*)))

; The same thing without blocking: start it, then poll until libpq says it
; is done one way or the other.
(deffunction poll-until-done (?conn)
  (bind ?state (pq-reset-poll ?conn))
  (while (and (neq ?state PGRES_POLLING_OK) (neq ?state PGRES_POLLING_FAILED))
    (bind ?state (pq-reset-poll ?conn)))
  ?state)

(expect "pq-reset-start starts a reconnection" TRUE (pq-reset-start ?*conn*))
(expect "and polling it through reaches a connected state"
        PGRES_POLLING_OK (poll-until-done ?*conn*))
(expect "which leaves the connection good" CONNECTION_OK (pq-status ?*conn*))

; ----------------------------------------------------------------------
; Connecting without blocking
;
; The same connection, made the other way: start it, then poll it through,
; waiting on the socket between polls rather than inside libpq.
; ----------------------------------------------------------------------

; poll-connection comes from tests/wait-poll.bat on a libpq that has
; pq-socket-poll, and from tests/wait-spin.bat on one that does not.

(defglobal ?*started* = (pq-connect-start ?*dsn*))

(expect-true "pq-connect-start hands back a connection at once"
             (neq FALSE ?*started*))
(expect "which is not connected yet"
        FALSE (eq (pq-status ?*started*) CONNECTION_OK))
(expect "polling it through connects it"
        PGRES_POLLING_OK (poll-connection ?*started*))
(expect "and it is a connection like any other"
        "1" (scalar ?*started* "SELECT 1"))
(pq-finish ?*started*)

; The same again from keywords and values, which pq-conninfo-parse is happy
; to produce from the connection string the suite was given.
(deffunction dsn-fields (?dsn ?which)
  (bind ?options (pq-conninfo-parse ?dsn))
  (bind ?fields (create$))
  (bind ?i 1)
  (while (< ?i (length$ ?options))
    (if (neq (nth$ (+ ?i 1) ?options) nil)
     then
       (bind ?fields (create$ ?fields
                       (if (eq ?which keywords)
                        then (nth$ ?i ?options)
                        else (nth$ (+ ?i 1) ?options)))))
    (bind ?i (+ ?i 2)))
  ?fields)

(defglobal ?*started-params* =
  (pq-connect-start-params (dsn-fields ?*dsn* keywords)
                           (dsn-fields ?*dsn* values)))

(expect "pq-connect-start-params starts one from keywords and values"
        PGRES_POLLING_OK (poll-connection ?*started-params*))
(expect "and it reaches the same database"
        (pq-db ?*conn*) (pq-db ?*started-params*))
(pq-finish ?*started-params*)

(pq-finish ?*conn*)

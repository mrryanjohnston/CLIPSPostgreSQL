; ======================================================================
; Connection strings, defaults, and what a connection that cannot be made
; looks like. None of this needs a server: a connection to nowhere is still
; a connection object, and reading it is how a program finds out why.
; ======================================================================

(println crlf "conninfo-test-suite")

; pq-conndefaults, pq-conninfo and pq-conninfo-parse all answer with the same
; flat multifield: a keyword, then its value or the symbol nil, over and over.
(deffunction conninfo-value (?options ?keyword)
  (bind ?found nil)
  (bind ?i 1)
  (while (< ?i (length$ ?options))
    (if (eq (nth$ ?i ?options) ?keyword)
     then (bind ?found (nth$ (+ ?i 1) ?options)))
    (bind ?i (+ ?i 2)))
  ?found)

; ----------------------------------------------------------------------
; pq-conndefaults
; ----------------------------------------------------------------------

(defglobal ?*defaults* = (pq-conndefaults))

(expect-true "pq-conndefaults answers with keyword/value pairs"
             (and (> (length$ ?*defaults*) 0)
                  (= 0 (mod (length$ ?*defaults*) 2))))

; Every value in the defaults may be nil -- what is asserted is that the
; keywords are there to be read.
(deffunction conninfo-has (?options ?keyword)
  (bind ?found FALSE)
  (bind ?i 1)
  (while (< ?i (length$ ?options))
    (if (eq (nth$ ?i ?options) ?keyword) then (bind ?found TRUE))
    (bind ?i (+ ?i 2)))
  ?found)

(expect "pq-conndefaults knows the dbname keyword"
        TRUE (conninfo-has ?*defaults* dbname))
(expect "pq-conndefaults knows the sslmode keyword"
        TRUE (conninfo-has ?*defaults* sslmode))

; ----------------------------------------------------------------------
; pq-conninfo-parse
; ----------------------------------------------------------------------

(defglobal ?*parsed* = (pq-conninfo-parse "dbname=clipspg user=someone port=5433"))

(expect "pq-conninfo-parse reads the database name back"
        "clipspg" (conninfo-value ?*parsed* dbname))
(expect "pq-conninfo-parse reads the user back"
        "someone" (conninfo-value ?*parsed* user))
(expect "pq-conninfo-parse reads the port back"
        "5433" (conninfo-value ?*parsed* port))
(expect "a keyword the string did not set comes back as nil"
        nil (conninfo-value ?*parsed* passfile))

(defglobal ?*empty* = (pq-conninfo-parse ""))
(expect-true "the empty connection string parses into the defaults"
             (> (length$ ?*empty*) 0))

; A keyword libpq has never heard of is the error case, and the message
; libpq wrote about it is what reaches stderr.
(defglobal ?*bad* = (pq-conninfo-parse "not_a_keyword=1"))
(expect "an unknown keyword is refused" FALSE ?*bad*)

(defglobal ?*malformed* = (pq-conninfo-parse "dbname"))
(expect "a keyword with no value is refused" FALSE ?*malformed*)

; ----------------------------------------------------------------------
; pq-ping, which asks without connecting
; ----------------------------------------------------------------------

(expect "pinging a socket directory that does not exist gets no response"
        PQPING_NO_RESPONSE (pq-ping "host=/nonexistent-socket-dir connect_timeout=1"))

(expect "pq-ping refuses a connection string it cannot parse"
        PQPING_NO_ATTEMPT (pq-ping "not_a_keyword=1"))

(expect "pq-ping-params refuses the same string the same way"
        PQPING_NO_ATTEMPT (pq-ping-params (create$ not_a_keyword) (create$ 1)))

; ----------------------------------------------------------------------
; A connection that cannot be made
;
; libpq answers with a connection object either way. The difference is its
; status, and a program that does not look is a program that will call
; pq-exec on a connection to nothing.
; ----------------------------------------------------------------------

(defglobal ?*dead* = (pq-connectdb "host=/nonexistent-socket-dir dbname=nowhere connect_timeout=1"))

(expect-true "a connection that failed is still a handle" (neq ?*dead* FALSE))
(expect "and its status says so" CONNECTION_BAD (pq-status ?*dead*))
(expect-true "and its error message says why"
             (neq FALSE (pq-error-message ?*dead*)))
(expect "the database it was asked for is still readable"
        "nowhere" (pq-db ?*dead*))
(expect "so is the host" "/nonexistent-socket-dir" (pq-host ?*dead*))
(expect "a connection that was never made has no socket"
        FALSE (pq-socket ?*dead*))
(expect "pq-finish closes it" TRUE (pq-finish ?*dead*))

; The handle is emptied by pq-finish, which is what makes this a refusal
; rather than a second free of the same pointer.
(defglobal ?*again* = (pq-finish ?*dead*))
(expect "and a second pq-finish is refused" FALSE ?*again*)

(defglobal ?*after* = (pq-status ?*dead*))
(expect "as is anything else asked of a finished connection" FALSE ?*after*)

; ----------------------------------------------------------------------
; pq-connectdb-params, where the two multifields must line up
; ----------------------------------------------------------------------

(defglobal ?*mismatched* = (pq-connectdb-params (create$ dbname user) (create$ one)))
(expect "keywords and values of different lengths are refused"
        FALSE ?*mismatched*)

(defglobal ?*byparams* = (pq-connectdb-params
                    (create$ host dbname connect_timeout)
                    (create$ "/nonexistent-socket-dir" nowhere 1)))
(expect "pq-connectdb-params builds the same failed connection"
        CONNECTION_BAD (pq-status ?*byparams*))
(expect "and reads its keywords back through pq-conninfo"
        "nowhere" (conninfo-value (pq-conninfo ?*byparams*) dbname))
(pq-finish ?*byparams*)

; pq-setdb-login is the oldest of these, and takes nil for every parameter it
; should default.
(defglobal ?*login* = (pq-setdb-login "/nonexistent-socket-dir" nil nil nil nowhere nil nil))
(expect "pq-setdb-login takes nil for the parameters it should default"
        CONNECTION_BAD (pq-status ?*login*))
(pq-finish ?*login*)

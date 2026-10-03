; ======================================================================
; CLIPSPostgreSQL in-process test suite
;
; Every suite batched from here shares one CLIPS environment, one process and
; one assertion counter, and the run ends with a non-zero exit status if any
; assertion failed.
;
; Two rules hold throughout:
;
;   1. A call whose arguments are wrong for the wrapper goes through a
;      defglobal, never a literal. CLIPS screens literal arguments against the
;      AddUDF restriction string at parse time, so a literal never reaches the
;      wrapper's own guard -- which is the thing being tested.
;
;   2. Such a call is bound to a global on a line of its own and asserted on
;      the next line. A refused argument raises an [ARGACCES2] evaluation
;      error, and an error raised inside an (expect ...) aborts the expect
;      itself: the assertion would vanish from the count instead of failing.
;      The messages the wrappers write to stderr are the exercise, not noise.
;
; tests/run.sh writes tests/tmp/dsn.bat before this runs. It says whether
; there is a server to talk to and how to reach it; the suites that need one
; are batched only when there is.
; ======================================================================

(defglobal
  ?*tests-ran*    = 0
  ?*tests-failed* = 0)

(deffunction expect (?msg ?expected ?actual)
  (bind ?*tests-ran* (+ ?*tests-ran* 1))
  (if (eq ?expected ?actual)
   then
     (print ".")
   else
     (bind ?*tests-failed* (+ ?*tests-failed* 1))
     (println crlf "FAILURE: " ?msg
             crlf "  expected=" ?expected
             crlf "  actual=" ?actual)))

; For values that are real but not fixed -- a process id, a socket number, a
; server version. Asserting the exact value would make the suite a record of
; this machine rather than of the wrapper.
(deffunction expect-true (?msg ?actual)
  (expect ?msg TRUE (if ?actual then TRUE else FALSE)))

(batch* tests/tmp/dsn.bat)
(batch* tests/constructs.bat)

; ----------------------------------------------------------------------
; Which libpq this binary was built against, in the numbers PostgreSQL
; versions itself with: 180006 is 18.6, 190000 is 19 before it has a minor
; version of its own.
;
; pq-built-version, not pq-lib-version: what a wrapper was compiled against
; decides whether it exists, and a binary built against 17 runs perfectly
; well with an 18 library loaded under it. It is the compiled-in set the
; suites have to match.
;
; A function PostgreSQL added in 16, 17 or 18 is not compiled in when the
; libpq being built against does not have it, and CLIPS resolves the name of
; a function when it reads the call rather than when it runs it -- so a
; suite that mentions one cannot even be read by an older build. That is why
; those suites are separate files: a file that is never batched is never
; read.
; ----------------------------------------------------------------------

(defglobal ?*libpq* = (pq-built-version))

(deffunction have-16 () (>= ?*libpq* 160000))
(deffunction have-17 () (>= ?*libpq* 170000))
(deffunction have-18 () (>= ?*libpq* 180000))

(if (have-17)
 then (batch* tests/wait-poll.bat)
 else (batch* tests/wait-spin.bat))

; ----------------------------------------------------------------------
; What every suite that needs a server uses to get one, and what they use to
; run the statements they are not testing -- the CREATE TABLE before the
; SELECT that is the actual subject.
; ----------------------------------------------------------------------

(deffunction connect ()
  (bind ?conn (pq-connectdb ?*dsn*))
  (if (neq (pq-status ?conn) CONNECTION_OK)
   then (println crlf "cannot connect: " (pq-error-message ?conn)))
  ?conn)

; Runs a command, asserts that the server was happy with it, and clears the
; result. The message names the command so a failure here is readable.
(deffunction run-sql (?conn ?sql)
  (bind ?res (pq-exec ?conn ?sql))
  (if (not ?res)
   then
     (expect (str-cat "no result at all from: " ?sql) TRUE FALSE)
   else
     (bind ?status (pq-result-status ?res))
     (if (and (neq ?status PGRES_COMMAND_OK) (neq ?status PGRES_TUPLES_OK))
      then
        (expect (str-cat ?sql " -- " (pq-result-error-message ?res))
                PGRES_COMMAND_OK ?status))
     (pq-clear ?res)))

; The one-value query, which several suites want and none of them are
; testing: the value in the first column of the first row, as a string.
(deffunction scalar (?conn ?sql)
  (bind ?res (pq-exec ?conn ?sql))
  (bind ?value (pq-getvalue ?res 0 0))
  (pq-clear ?res)
  ?value)

(println "CLIPSPostgreSQL test suite: built for libpq " ?*libpq*
         ", running with " (pq-lib-version))
(if ?*have-server*
 then (println "server: " ?*dsn*)
 else (println "no server: the suites that need one are skipped"))
(println)

; ----------------------------------------------------------------------
; The suites that need nothing but the library
; ----------------------------------------------------------------------

(batch* tests/version-test-suite.bat)
(batch* tests/conninfo-test-suite.bat)
(batch* tests/arg-guard-test-suite.bat)

; ----------------------------------------------------------------------
; The suites that need a server
; ----------------------------------------------------------------------

(deffunction server-suites ()
  (batch* tests/connect-test-suite.bat)
  (batch* tests/exec-test-suite.bat)
  (batch* tests/params-test-suite.bat)
  (batch* tests/metadata-test-suite.bat)
  (batch* tests/row-mapping-test-suite.bat)
  (batch* tests/result-mapping-test-suite.bat)
  (batch* tests/escape-test-suite.bat)
  (batch* tests/async-test-suite.bat)
  (batch* tests/pipeline-test-suite.bat)
  (batch* tests/notify-test-suite.bat)
  (batch* tests/copy-test-suite.bat)
  (batch* tests/handle-lifetime-test-suite.bat)

  ; What each of the last few releases added, tested only where it is there.
  (if (have-16) then (batch* tests/pg16-test-suite.bat))
  (if (have-17) then (batch* tests/pg17-test-suite.bat))
  (if (have-17) then (batch* tests/cancel-test-suite.bat))
  (if (have-18) then (batch* tests/pg18-test-suite.bat)))

(if ?*have-server* then (server-suites))

(println)
(println "Tests run: " ?*tests-ran* "  Failures: " ?*tests-failed*)
(exit (if (> ?*tests-failed* 0) then 1 else 0))

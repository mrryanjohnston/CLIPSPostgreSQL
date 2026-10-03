; ======================================================================
; What the wrappers do with arguments they cannot use.
;
; Two kinds of refusal are covered here, and they are not the same thing:
;
;   CLIPS refuses first. Every registration declares what it accepts, and a
;   value of the wrong type never reaches the wrapper: CLIPS raises an
;   [ARGACCES2] error and the call yields FALSE. The assertion is that the
;   call is refused rather than run on a value nobody checked.
;
;   The wrapper refuses. A NULL handle, an index past the end of a result,
;   an enumeration name this libpq does not have -- all of these are the
;   right CLIPS type and still unusable, so the wrapper is what catches
;   them. This is the part that would segfault if it did not.
;
; Every call goes through a defglobal, because CLIPS screens literal
; arguments at parse time and a literal would never reach either check. Each
; is bound on a line of its own and asserted on the next, because an error
; raised inside an (expect ...) would abort the expect instead of failing it.
; ======================================================================

(println crlf "arg-guard-test-suite")

(defglobal
  ?*integer*  = 42
  ?*string*   = "not a handle"
  ?*symbol*   = a-symbol
  ?*float*    = 1.5
  ?*multi*    = (create$ 1 2 3)
  ?*result*   = FALSE)

; ----------------------------------------------------------------------
; A handle is the argument most of these take, and the one most worth
; getting wrong.
; ----------------------------------------------------------------------

(bind ?*result* (pq-status ?*integer*))
(expect "pq-status refuses an integer where a connection belongs" FALSE ?*result*)

(bind ?*result* (pq-status ?*string*))
(expect "pq-status refuses a string" FALSE ?*result*)

(bind ?*result* (pq-exec ?*symbol* "SELECT 1"))
(expect "pq-exec refuses a symbol where a connection belongs" FALSE ?*result*)

(bind ?*result* (pq-clear ?*multi*))
(expect "pq-clear refuses a multifield where a result belongs" FALSE ?*result*)

(bind ?*result* (pq-ntuples ?*float*))
(expect "pq-ntuples refuses a float" FALSE ?*result*)

; ----------------------------------------------------------------------
; A handle that has been emptied. pq-finish and pq-clear leave the CLIPS
; value holding a NULL pointer on purpose, and every wrapper checks for it.
; ----------------------------------------------------------------------

(defglobal ?*emptied* = (pq-connectdb "host=/nonexistent-socket-dir connect_timeout=1"))
(pq-finish ?*emptied*)

(bind ?*result* (pq-db ?*emptied*))
(expect "pq-db refuses an emptied connection" FALSE ?*result*)

(bind ?*result* (pq-exec ?*emptied* "SELECT 1"))
(expect "pq-exec refuses an emptied connection" FALSE ?*result*)

(bind ?*result* (pq-send-query ?*emptied* "SELECT 1"))
(expect "pq-send-query refuses an emptied connection" FALSE ?*result*)

(bind ?*result* (pq-get-result ?*emptied*))
(expect "pq-get-result refuses an emptied connection" FALSE ?*result*)

(bind ?*result* (pq-notifies ?*emptied*))
(expect "pq-notifies refuses an emptied connection" FALSE ?*result*)

(bind ?*result* (pq-escape-literal ?*emptied* "x"))
(expect "pq-escape-literal refuses an emptied connection" FALSE ?*result*)

(bind ?*result* (pq-conninfo ?*emptied*))
(expect "pq-conninfo refuses an emptied connection" FALSE ?*result*)

; ----------------------------------------------------------------------
; Values of the right CLIPS type that are still not usable.
; ----------------------------------------------------------------------

(bind ?*result* (pq-res-status NOT_A_STATUS))
(expect "pq-res-status refuses a status name libpq does not have" FALSE ?*result*)

(bind ?*result* (pq-result-error-field ?*emptied* PG_DIAG_SQLSTATE))
(expect "pq-result-error-field refuses an emptied result" FALSE ?*result*)

(bind ?*result* (pq-connectdb-params ?*multi* (create$ 1 2)))
(expect "pq-connectdb-params refuses lists of different lengths" FALSE ?*result*)

(bind ?*result* (pq-connectdb-params ?*integer* ?*integer*))
(expect "pq-connectdb-params refuses an integer where a multifield belongs"
        FALSE ?*result*)

(bind ?*result* (pq-unescape-bytea ?*integer*))
(expect "pq-unescape-bytea refuses an integer" FALSE ?*result*)

(bind ?*result* (pq-result-to-facts ?*integer* orders))
(expect "pq-result-to-facts refuses an integer where a result belongs" FALSE ?*result*)

(bind ?*result* (pq-result-to-multifields ?*emptied*))
(expect "pq-result-to-multifields refuses an emptied handle" FALSE ?*result*)

(bind ?*result* (pq-exec-to-facts ?*emptied* "SELECT 1"))
(expect "pq-exec-to-facts refuses an emptied connection" FALSE ?*result*)

(bind ?*result* (pq-exec-to-instances ?*string* "SELECT 1"))
(expect "pq-exec-to-instances refuses a string where a connection belongs" FALSE ?*result*)

; The guards on the functions PostgreSQL 17 added are in
; tests/pg17-test-suite.bat, which is only read where they exist.

; The enumeration argument accepts a symbol or the integer behind it, and
; nothing else: an integer that is not one of the values is a value this
; libpq will be asked about, and PQresStatus is the one that will say so.
(bind ?*result* (pq-res-status 0))
(expect "pq-res-status takes the integer behind the name"
        (pq-res-status PGRES_EMPTY_QUERY) ?*result*)

; ----------------------------------------------------------------------
; The rest of the guards, one call per wrapper
;
; Every wrapper checks its own arguments before libpq sees them, and each
; check is a line of its own in that wrapper: a guard no suite has tripped
; is a guard nothing has shown to be there. Three handles cover them all
; without a server. ?*emptied* above is a closed connection; a connection
; to nowhere is a live handle libpq made and will not use; and a result
; libpq made up for it is a result with no rows and no columns to index.
; ----------------------------------------------------------------------

(defglobal
  ?*nowhere*      = (pq-connectdb "host=/nonexistent-socket-dir connect_timeout=1")
  ?*empty-result* = (pq-make-empty-pgresult ?*nowhere* PGRES_TUPLES_OK)
  ?*not-boolean*  = maybe)

(expect "a connection to nowhere is still a handle to guard with"
        CONNECTION_BAD (pq-status ?*nowhere*))
(expect "and a made-up result has no rows to index"
        0 (pq-ntuples ?*empty-result*))

; making a connection

(bind ?*result* (pq-connectdb ?*integer*))
(expect "pq-connectdb refuses an integer where a connection string belongs" FALSE ?*result*)

(bind ?*result* (pq-connect-start ?*integer*))
(expect "so does pq-connect-start" FALSE ?*result*)

(bind ?*result* (pq-ping ?*integer*))
(expect "and pq-ping" FALSE ?*result*)

(bind ?*result* (pq-setdb-login ?*integer* nil nil nil nil nil nil))
(expect "pq-setdb-login refuses an integer where the host belongs" FALSE ?*result*)

(bind ?*result* (pq-connect-start-params ?*integer* ?*multi*))
(expect "pq-connect-start-params refuses an integer where the keywords belong" FALSE ?*result*)

(bind ?*result* (pq-ping-params ?*integer* ?*multi*))
(expect "so does pq-ping-params" FALSE ?*result*)

(bind ?*result* (pq-connectdb-params ?*multi* ?*integer*))
(expect "pq-connectdb-params refuses an integer where the values belong" FALSE ?*result*)

(bind ?*result* (pq-ping-params (create$ host) (create$ "/nonexistent-socket-dir") ?*integer*))
(expect "and an integer where the expand-dbname flag belongs" FALSE ?*result*)

; A keyword or a value is a symbol, a string or a number, whose printed
; form is what libpq is given. A handle has no printed form, nor does an
; instance name.
(bind ?*result* (pq-ping-params (create$ ?*emptied*) (create$ x)))
(expect "a keyword with no printed form is refused" FALSE ?*result*)

(bind ?*result* (pq-ping-params (create$ host) (create$ [nowhere])))
(expect "and so is a value with none" FALSE ?*result*)

; polling and resetting

(bind ?*result* (pq-connect-poll ?*emptied*))
(expect "pq-connect-poll refuses an emptied connection" FALSE ?*result*)

(bind ?*result* (pq-reset-start ?*emptied*))
(expect "so does pq-reset-start" FALSE ?*result*)

(bind ?*result* (pq-reset-poll ?*emptied*))
(expect "and pq-reset-poll" FALSE ?*result*)

; asking about a connection

(bind ?*result* (pq-transaction-status ?*emptied*))
(expect "pq-transaction-status refuses an emptied connection" FALSE ?*result*)

(bind ?*result* (pq-parameter-status ?*nowhere* ?*integer*))
(expect "pq-parameter-status refuses an integer where the parameter name belongs" FALSE ?*result*)

(bind ?*result* (pq-ssl-in-use ?*emptied*))
(expect "pq-ssl-in-use refuses an emptied connection" FALSE ?*result*)

(bind ?*result* (pq-gss-enc-in-use ?*emptied*))
(expect "so does pq-gss-enc-in-use" FALSE ?*result*)

(bind ?*result* (pq-ssl-attribute-names ?*emptied*))
(expect "and pq-ssl-attribute-names" FALSE ?*result*)

(bind ?*result* (pq-ssl-attribute ?*nowhere* ?*integer*))
(expect "pq-ssl-attribute refuses an integer where the attribute name belongs" FALSE ?*result*)

; running a command

(bind ?*result* (pq-exec ?*nowhere* ?*integer*))
(expect "pq-exec refuses an integer where the command belongs" FALSE ?*result*)

(bind ?*result* (pq-exec-params ?*nowhere* "SELECT 1" ?*integer*))
(expect "pq-exec-params refuses an integer where the parameters belong" FALSE ?*result*)

(bind ?*result* (pq-prepare ?*emptied* "stmt" "SELECT 1"))
(expect "pq-prepare refuses an emptied connection" FALSE ?*result*)

(bind ?*result* (pq-prepare ?*nowhere* "stmt" ?*integer*))
(expect "and an integer where the query belongs" FALSE ?*result*)

(bind ?*result* (pq-exec-prepared ?*emptied* "stmt"))
(expect "pq-exec-prepared refuses an emptied connection" FALSE ?*result*)

(bind ?*result* (pq-exec-prepared ?*nowhere* ?*integer*))
(expect "an integer where the statement name belongs" FALSE ?*result*)

(bind ?*result* (pq-exec-prepared ?*nowhere* "stmt" ?*integer*))
(expect "and an integer where the parameters belong" FALSE ?*result*)

; A connection that was never made runs nothing: libpq answers with no
; result at all, and that comes through as FALSE with libpq's reason, where
; a command the server refused would be a result whose status says so.
(bind ?*result* (pq-exec ?*nowhere* "SELECT 1"))
(expect "pq-exec on a connection that was never made is refused" FALSE ?*result*)

(bind ?*result* (pq-setnonblocking ?*nowhere* TRUE))
(expect "and so is changing its blocking mode" FALSE ?*result*)

; reading a result

(bind ?*result* (pq-fname ?*emptied* 0))
(expect "pq-fname refuses an emptied handle where a result belongs" FALSE ?*result*)

(bind ?*result* (pq-fname ?*empty-result* ?*string*))
(expect "and a string where a column number belongs" FALSE ?*result*)

(bind ?*result* (pq-fformat ?*empty-result* 0))
(expect "pq-fformat refuses a column the result does not have" FALSE ?*result*)

(bind ?*result* (pq-ftype ?*empty-result* 0))
(expect "so does pq-ftype" FALSE ?*result*)

(bind ?*result* (pq-fmod ?*empty-result* 0))
(expect "and pq-fmod" FALSE ?*result*)

(bind ?*result* (pq-fsize ?*empty-result* 0))
(expect "and pq-fsize" FALSE ?*result*)

(bind ?*result* (pq-fnumber ?*emptied* "id"))
(expect "pq-fnumber refuses an emptied handle" FALSE ?*result*)

(bind ?*result* (pq-fnumber ?*empty-result* ?*integer*))
(expect "and an integer where the column name belongs" FALSE ?*result*)

(bind ?*result* (pq-paramtype ?*empty-result* ?*string*))
(expect "pq-paramtype refuses a string where a parameter number belongs" FALSE ?*result*)

(bind ?*result* (pq-getvalue ?*empty-result* ?*string* 0))
(expect "pq-getvalue refuses a string where a row number belongs" FALSE ?*result*)

(bind ?*result* (pq-getisnull ?*emptied* 0 0))
(expect "pq-getisnull refuses an emptied handle" FALSE ?*result*)

(bind ?*result* (pq-getisnull ?*empty-result* 0 0))
(expect "and a row the result does not have" FALSE ?*result*)

(bind ?*result* (pq-getlength ?*emptied* 0 0))
(expect "pq-getlength refuses an emptied handle" FALSE ?*result*)

(bind ?*result* (pq-getlength ?*empty-result* 0 0))
(expect "and a row the result does not have" FALSE ?*result*)

(bind ?*result* (pq-binary-tuples ?*emptied*))
(expect "pq-binary-tuples refuses an emptied handle" FALSE ?*result*)

(bind ?*result* (pq-cmd-status ?*emptied*))
(expect "so does pq-cmd-status" FALSE ?*result*)

(bind ?*result* (pq-cmd-tuples ?*emptied*))
(expect "and pq-cmd-tuples" FALSE ?*result*)

(bind ?*result* (pq-result-memory-size ?*emptied*))
(expect "and pq-result-memory-size" FALSE ?*result*)

(bind ?*result* (pq-res-status ?*float*))
(expect "pq-res-status refuses a float where a status belongs" FALSE ?*result*)

(bind ?*result* (pq-result-verbose-error-message ?*emptied* PQERRORS_TERSE PQSHOW_CONTEXT_NEVER))
(expect "pq-result-verbose-error-message refuses an emptied handle" FALSE ?*result*)

(bind ?*result* (pq-result-verbose-error-message ?*empty-result* PQERRORS_LOUD PQSHOW_CONTEXT_NEVER))
(expect "and a verbosity libpq does not have" FALSE ?*result*)

(bind ?*result* (pq-result-error-field ?*empty-result* PG_DIAG_NOT_A_FIELD))
(expect "pq-result-error-field refuses a field libpq does not have" FALSE ?*result*)

; A result with nothing wrong in it has no error message, and one that
; counted no rows has no count: FALSE for both, which everywhere here means
; there is nothing to report rather than that the call was refused.
(expect "a result with no error has no error message"
        FALSE (pq-result-error-message ?*empty-result*))
(expect "and a result that counted nothing has no row count"
        FALSE (pq-cmd-tuples ?*empty-result*))

; escaping

(bind ?*result* (pq-escape-literal ?*nowhere* ?*integer*))
(expect "pq-escape-literal refuses an integer where the text belongs" FALSE ?*result*)

(bind ?*result* (pq-escape-string-conn ?*emptied* "x"))
(expect "pq-escape-string-conn refuses an emptied connection" FALSE ?*result*)

(bind ?*result* (pq-escape-string-conn ?*nowhere* ?*integer*))
(expect "and an integer where the text belongs" FALSE ?*result*)

(bind ?*result* (pq-escape-bytea-conn ?*nowhere* ?*integer*))
(expect "pq-escape-bytea-conn refuses an integer where the bytes belong" FALSE ?*result*)

; sending without waiting

(bind ?*result* (pq-send-query ?*nowhere* ?*integer*))
(expect "pq-send-query refuses an integer where the command belongs" FALSE ?*result*)

(bind ?*result* (pq-send-query-params ?*emptied* "SELECT 1"))
(expect "pq-send-query-params refuses an emptied connection" FALSE ?*result*)

(bind ?*result* (pq-send-query-params ?*nowhere* ?*integer*))
(expect "an integer where the command belongs" FALSE ?*result*)

(bind ?*result* (pq-send-query-params ?*nowhere* "SELECT 1" ?*integer*))
(expect "and an integer where the parameters belong" FALSE ?*result*)

(bind ?*result* (pq-send-prepare ?*emptied* "stmt" "SELECT 1"))
(expect "pq-send-prepare refuses an emptied connection" FALSE ?*result*)

(bind ?*result* (pq-send-prepare ?*nowhere* "stmt" ?*integer*))
(expect "and an integer where the query belongs" FALSE ?*result*)

(bind ?*result* (pq-send-query-prepared ?*emptied* "stmt"))
(expect "pq-send-query-prepared refuses an emptied connection" FALSE ?*result*)

(bind ?*result* (pq-send-query-prepared ?*nowhere* ?*integer*))
(expect "an integer where the statement name belongs" FALSE ?*result*)

(bind ?*result* (pq-send-query-prepared ?*nowhere* "stmt" ?*integer*))
(expect "and an integer where the parameters belong" FALSE ?*result*)

(bind ?*result* (pq-consume-input ?*emptied*))
(expect "pq-consume-input refuses an emptied connection" FALSE ?*result*)

(bind ?*result* (pq-is-busy ?*emptied*))
(expect "so does pq-is-busy" FALSE ?*result*)

(bind ?*result* (pq-setnonblocking ?*emptied* TRUE))
(expect "and pq-setnonblocking" FALSE ?*result*)

(bind ?*result* (pq-setnonblocking ?*nowhere* ?*not-boolean*))
(expect "which also refuses a symbol that is neither TRUE nor FALSE" FALSE ?*result*)

(bind ?*result* (pq-isnonblocking ?*emptied*))
(expect "pq-isnonblocking refuses an emptied connection" FALSE ?*result*)

(bind ?*result* (pq-flush ?*emptied*))
(expect "so does pq-flush" FALSE ?*result*)

(bind ?*result* (pq-pipeline-status ?*emptied*))
(expect "and pq-pipeline-status" FALSE ?*result*)

; COPY

(bind ?*result* (pq-put-copy-data ?*emptied* "x"))
(expect "pq-put-copy-data refuses an emptied connection" FALSE ?*result*)

(bind ?*result* (pq-put-copy-data ?*nowhere* ?*integer*))
(expect "and an integer where the data belongs" FALSE ?*result*)

(bind ?*result* (pq-put-copy-end ?*emptied*))
(expect "pq-put-copy-end refuses an emptied connection" FALSE ?*result*)

(bind ?*result* (pq-put-copy-end ?*nowhere* ?*integer*))
(expect "and an integer where the error message belongs" FALSE ?*result*)

(bind ?*result* (pq-get-copy-data ?*nowhere* ?*integer*))
(expect "pq-get-copy-data refuses an integer where the async flag belongs" FALSE ?*result*)

; control

(bind ?*result* (pq-set-client-encoding ?*emptied* "UTF8"))
(expect "pq-set-client-encoding refuses an emptied connection" FALSE ?*result*)

(bind ?*result* (pq-set-error-context-visibility ?*emptied* PQSHOW_CONTEXT_NEVER))
(expect "so does pq-set-error-context-visibility" FALSE ?*result*)

(bind ?*result* (pq-set-error-context-visibility ?*nowhere* PQSHOW_CONTEXT_LOUDLY))
(expect "which also refuses a visibility libpq does not have" FALSE ?*result*)

(bind ?*result* (pq-encrypt-password-conn ?*emptied* "hunter2" "someone"))
(expect "pq-encrypt-password-conn refuses an emptied connection" FALSE ?*result*)

(bind ?*result* (pq-encrypt-password-conn ?*nowhere* ?*integer* "someone"))
(expect "and an integer where the password belongs" FALSE ?*result*)

; ----------------------------------------------------------------------
; A value libpq answers that no table here names
;
; An enumeration argument is also taken as the integer behind its name, and
; libpq keeps whatever integer it is given. What it answers the next time
; is then a value no table here has a name for, which comes back as
; <unknown> rather than as a name made up for it.
; ----------------------------------------------------------------------

(pq-set-error-verbosity ?*nowhere* 99)
(expect "a verbosity set as an integer no name stands for reads back as <unknown>"
        (sym-cat "<" "unknown>") (pq-set-error-verbosity ?*nowhere* PQERRORS_DEFAULT))

; ----------------------------------------------------------------------
; A connection string libpq could not parse
;
; The connection object exists and its status is CONNECTION_BAD, but libpq
; never got as far as filling it in: the settings a connection answers are
; missing rather than empty, and a reconnection has nothing to reconnect
; with -- which libpq says by refusing without a message.
; ----------------------------------------------------------------------

(defglobal ?*unparsed* = (pq-connectdb "not_a_keyword=1"))

(expect "a connection string libpq cannot parse still makes a handle"
        CONNECTION_BAD (pq-status ?*unparsed*))
(expect "which has no options to report" FALSE (pq-options ?*unparsed*))
(expect "and no user" FALSE (pq-user ?*unparsed*))

(bind ?*result* (pq-reset-start ?*unparsed*))
(expect "and cannot start a reconnection" FALSE ?*result*)

(pq-finish ?*unparsed*)
(pq-clear ?*empty-result*)
(pq-finish ?*nowhere*)

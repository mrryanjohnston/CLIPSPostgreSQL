; ======================================================================
; Rules over SQL
;
; The database holds the rows; CLIPS holds the reasoning. This reads a table
; into facts, lets rules decide something about them, and sends what the
; rules concluded back as parameters.
;
;   ./vendor/clips/clips -f2 examples/1-rules-over-sql.bat
; ======================================================================

(defglobal ?*conn* = (pq-connectdb ""))

(if (neq (pq-status ?*conn*) CONNECTION_OK)
 then
   (println "cannot connect: " (pq-error-message ?*conn*))
   (println "libpq reads PGHOST, PGDATABASE and PGUSER from the environment.")
   (exit 1))

(println "connected to " (pq-db ?*conn*) " on " (pq-host ?*conn*)
         ", server " (pq-server-version ?*conn*))

; ----------------------------------------------------------------------
; Something to reason about
; ----------------------------------------------------------------------

(deffunction run-sql (?sql)
  (bind ?res (pq-exec ?*conn* ?sql))
  (if (not ?res)
   then (println "no result: " (pq-error-message ?*conn*)) (exit 1))
  (if (eq (pq-result-status ?res) PGRES_FATAL_ERROR)
   then (println (pq-result-error-message ?res)) (exit 1))
  (pq-clear ?res))

(run-sql "CREATE TEMP TABLE parts (
            id      int PRIMARY KEY,
            name    text NOT NULL,
            weight  float8,
            in_use  boolean)")

(run-sql "INSERT INTO parts VALUES
            (1, 'flange',  12.5, true),
            (2, 'bolt',     0.4, true),
            (3, 'gasket',   0.1, false),
            (4, 'housing', 44.0, true),
            (5, 'shim',    NULL, false)")

; ----------------------------------------------------------------------
; The rows, as facts
;
; pq-row-to-fact takes the column names as slot names, so the template is
; written to match the query rather than the table.
; ----------------------------------------------------------------------

(deftemplate part
  (slot id) (slot name) (slot weight) (slot in_use))

(deftemplate heavy   (slot id) (slot name))
(deftemplate unknown (slot id) (slot name))

(defglobal ?*rows* =
  (pq-exec ?*conn* "SELECT id, name, weight, in_use FROM parts ORDER BY id"))

(defglobal ?*last* = (- (pq-ntuples ?*rows*) 1))

(loop-for-count (?row 0 ?*last*)
  (pq-row-to-fact ?*rows* ?row part))

(pq-clear ?*rows*)

(println "read " (+ ?*last* 1) " rows into facts")

; ----------------------------------------------------------------------
; The reasoning
;
; NULL arrived as the symbol nil, which is a value a rule can match on --
; the point of converting rather than leaving everything a string.
; ----------------------------------------------------------------------

(defrule heavy-part
  (part (id ?id) (name ?name) (weight ?weight&:(numberp ?weight)))
  (test (> ?weight 10.0))
  =>
  (assert (heavy (id ?id) (name ?name))))

(defrule unweighed-part
  (part (id ?id) (name ?name) (weight nil))
  =>
  (assert (unknown (id ?id) (name ?name))))

(run)

; ----------------------------------------------------------------------
; What the rules concluded, back to the server
;
; Every value goes out as a parameter: nothing the rules produced is ever
; part of the command text.
; ----------------------------------------------------------------------

(run-sql "CREATE TEMP TABLE findings (id int, name text, finding text)")

(deffunction record (?id ?name ?finding)
  (bind ?res (pq-exec-params ?*conn*
               "INSERT INTO findings (id, name, finding) VALUES ($1, $2, $3)"
               (create$ ?id ?name ?finding)))
  (if (eq (pq-result-status ?res) PGRES_FATAL_ERROR)
   then (println (pq-result-error-message ?res)))
  (pq-clear ?res))

(defrule report-heavy
  (declare (salience -10))
  (heavy (id ?id) (name ?name))
  =>
  (record ?id ?name "over 10kg"))

(defrule report-unknown
  (declare (salience -10))
  (unknown (id ?id) (name ?name))
  =>
  (record ?id ?name "no weight recorded"))

(run)

; ----------------------------------------------------------------------
; And back out again
; ----------------------------------------------------------------------

(defglobal ?*findings* =
  (pq-exec ?*conn* "SELECT name, finding FROM findings ORDER BY id"))

(println)
(println "findings:")
(loop-for-count (?row 0 (- (pq-ntuples ?*findings*) 1))
  (println "  " (pq-getvalue ?*findings* ?row 0)
           ": " (pq-getvalue ?*findings* ?row 1)))

(pq-clear ?*findings*)
(pq-finish ?*conn*)
(exit)

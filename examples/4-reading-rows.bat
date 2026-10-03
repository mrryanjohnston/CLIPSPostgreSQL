; ======================================================================
; Every way of reading rows
;
; libpq hands rows over as text, one field at a time. This library keeps
; that, and adds nine functions that convert rows to CLIPS values by their
; type: three that take one row, three that take every row of a result, and
; three that run the command as well. This walks through all of them over
; one small table, so the shapes can be compared side by side.
;
;   ./vendor/clips/clips -f2 examples/4-reading-rows.bat
; ======================================================================

(defglobal ?*conn* = (pq-connectdb ""))

(if (neq (pq-status ?*conn*) CONNECTION_OK)
 then (println "cannot connect: " (pq-error-message ?*conn*)) (exit 1))

(deffunction run-sql (?sql)
  (bind ?res (pq-exec ?*conn* ?sql))
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

; The shapes the rows are read into. Column names are slot names, and the
; pq-exec-to-* forms can infer which shape from the table the columns come
; from, so these are named after the table: the deftemplate as it is, the
; defclass in capitals. An instance's name is not a slot, so a column
; called "name" goes to the slot _name.
(deftemplate parts (slot id) (slot name) (slot weight) (slot in_use))
(defclass PARTS (is-a USER) (role concrete)
  (slot id) (slot _name) (slot weight) (slot in_use))

(defglobal ?*res* =
  (pq-exec ?*conn* "SELECT id, name, weight, in_use FROM parts ORDER BY id"))

; ----------------------------------------------------------------------
; 1. Field by field, as text
;
; What libpq itself offers: every value is the text the server printed,
; and SQL NULL is the symbol nil.
; ----------------------------------------------------------------------

(println)
(println "1. field by field: " (pq-ntuples ?*res*) " rows of "
         (pq-nfields ?*res*) " columns")

(loop-for-count (?row 0 (- (pq-ntuples ?*res*) 1))
  (print "   ")
  (loop-for-count (?col 0 (- (pq-nfields ?*res*) 1))
    (print (pq-fname ?*res* ?col) "=" (pq-getvalue ?*res* ?row ?col) " "))
  (println))

(println "   weight of row 4 is " (pq-getvalue ?*res* 4 2)
         ", and stringp says " (stringp (pq-getvalue ?*res* 0 2))
         " of the others")

; ----------------------------------------------------------------------
; 2. One row, converted by type
;
; The integers become integers, float8 becomes a float, boolean becomes
; TRUE or FALSE, and NULL stays nil -- values a rule can match on.
; ----------------------------------------------------------------------

(println)
(println "2. one row, converted")

(defglobal ?*row-0* = (pq-row-to-multifield ?*res* 0))
(println "   pq-row-to-multifield: " ?*row-0*)
(println "   the weight is a float: " (floatp (nth$ 3 ?*row-0*)))

(defglobal ?*fact-1* = (pq-row-to-fact ?*res* 1 parts))
(println "   pq-row-to-fact: " (fact-slot-value ?*fact-1* name)
         " weighs " (fact-slot-value ?*fact-1* weight))

(defglobal ?*inst-2* = (pq-row-to-instance ?*res* 2 PARTS gasket))
(println "   pq-row-to-instance: " (instance-name ?*inst-2*)
         " is " (send ?*inst-2* get-_name)
         ", in use " (send ?*inst-2* get-in_use))

; ----------------------------------------------------------------------
; 3. Every row of the result
;
; The same conversion over the whole result in one call, answering what
; was made in row order.
; ----------------------------------------------------------------------

(println)
(println "3. every row of the result")

(defglobal ?*all* = (pq-result-to-multifields ?*res*))
(println "   pq-result-to-multifields: " (length$ ?*all*) " fields, "
         (pq-nfields ?*res*) " per row")
(println "   with headers: "
         (subseq$ (pq-result-to-multifields ?*res* TRUE) 1 8) " ...")

; The bolt is already a fact from step 2, so CLIPS answers that fact for
; its row rather than a second copy.
(defglobal ?*facts* = (pq-result-to-facts ?*res* parts))
(println "   pq-result-to-facts: " (length$ ?*facts*) " facts, "
         (length$ (find-all-facts ((?p parts)) TRUE)) " in working memory")
(println "   the bolt's fact is the one from step 2: "
         (eq (nth$ 2 ?*facts*) ?*fact-1*))

; Names are positional: the rows past the end of the list are named by
; CLIPS.
(defglobal ?*instances* =
  (pq-result-to-instances ?*res* PARTS (create$ flange bolt)))
(println "   pq-result-to-instances: " (length$ ?*instances*) " instances, "
         "the first two named " (instance-name (nth$ 1 ?*instances*))
         " and " (instance-name (nth$ 2 ?*instances*)))

(pq-clear ?*res*)

; ----------------------------------------------------------------------
; 4. Running the command as well
;
; One call: the query runs, the rows land, the result is cleared. The
; deftemplate or defclass can be left out when every column comes from
; one table, which is then its name.
; ----------------------------------------------------------------------

(println)
(println "4. running the command as well")

(println "   pq-exec-to-multifields: "
         (pq-exec-to-multifields ?*conn*
           "SELECT name, weight FROM parts WHERE in_use ORDER BY id"))

; Every column comes from parts, so the deftemplate is inferred; every row
; is already a fact, so working memory does not grow.
(defglobal ?*again* =
  (pq-exec-to-facts ?*conn*
    "SELECT id, name, weight, in_use FROM parts ORDER BY id"))
(println "   pq-exec-to-facts, deftemplate inferred: " (length$ ?*again*)
         " facts, still " (length$ (find-all-facts ((?p parts)) TRUE))
         " in working memory")

; The class is inferred the same way, in capitals.
(defglobal ?*heavy* =
  (pq-exec-to-instances ?*conn*
    "SELECT id, name, weight FROM parts WHERE weight > 10 ORDER BY id"))
(println "   pq-exec-to-instances, defclass inferred: "
         (length$ ?*heavy*) " instances of " (class (nth$ 1 ?*heavy*))
         ", the first " (send (nth$ 1 ?*heavy*) get-_name))

; An aggregate's columns match no table, so its shape is named -- and a
; SQL alias is how a column is made to match a slot.
(defclass USAGE (is-a USER) (role concrete)
  (slot in_use) (slot n) (slot total))

(pq-exec-to-instances ?*conn*
  "SELECT in_use, count(*) AS n, sum(weight) AS total
     FROM parts GROUP BY in_use ORDER BY in_use"
  USAGE (create$ idle busy))
(println "   pq-exec-to-instances, named: " (send [busy] get-n)
         " parts in use weighing " (send [busy] get-total)
         ", " (send [idle] get-n) " idle")

; ----------------------------------------------------------------------
; And what that was for: the rows are in working memory, so a rule can
; reason over them.
; ----------------------------------------------------------------------

(defrule unweighed
  (parts (name ?name) (weight nil))
  =>
  (println)
  (println "the rule found " ?name " has no weight recorded"))

(run)

(pq-finish ?*conn*)
(exit)

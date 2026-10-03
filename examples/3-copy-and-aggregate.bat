; ======================================================================
; Loading with COPY, and asking the server to do the arithmetic
;
; COPY is the fast way to get many rows into PostgreSQL: one command, then
; the data, then one result. What comes back afterwards is an aggregate --
; the sort of thing worth leaving to the database rather than doing over
; facts.
;
;   ./vendor/clips/clips -f2 examples/3-copy-and-aggregate.bat
; ======================================================================

(defglobal ?*conn* = (pq-connectdb ""))

(if (neq (pq-status ?*conn*) CONNECTION_OK)
 then (println "cannot connect: " (pq-error-message ?*conn*)) (exit 1))

(deffunction run-sql (?sql)
  (bind ?res (pq-exec ?*conn* ?sql))
  (if (eq (pq-result-status ?res) PGRES_FATAL_ERROR)
   then (println (pq-result-error-message ?res)) (exit 1))
  (pq-clear ?res))

(run-sql "CREATE TEMP TABLE readings (
            sensor  text,
            minute  int,
            celsius float8)")

; ----------------------------------------------------------------------
; The load
;
; COPY data is tab-separated and newline-terminated, and CLIPS string
; literals have no escape for either character: (format nil ...) is where
; they come from.
; ----------------------------------------------------------------------

(defglobal ?*tab*     = (format nil "%t"))
(defglobal ?*newline* = (format nil "%n"))

(defglobal ?*copy* = (pq-exec ?*conn* "COPY readings FROM STDIN"))

(if (neq (pq-result-status ?*copy*) PGRES_COPY_IN)
 then (println "the server would not start a copy: "
               (pq-result-error-message ?*copy*)) (exit 1))
(pq-clear ?*copy*)

; COPY carries values, not expressions: every field is the text form of what
; goes in the column.
(deffunction reading (?sensor ?minute ?celsius)
  (pq-put-copy-data ?*conn*
    (str-cat ?sensor ?*tab* ?minute ?*tab* ?celsius ?*newline*)))

; The rows can be sent in as many pieces as suits the sender; the server
; puts them back together.
(loop-for-count (?i 1 200)
  (reading "boiler" ?i (+ 80.0 (mod ?i 7)))
  (reading "intake" ?i (+ 11.0 (mod ?i 3))))

(pq-put-copy-end ?*conn*)

(defglobal ?*loaded* = (pq-get-result ?*conn*))

(if (neq (pq-result-status ?*loaded*) PGRES_COMMAND_OK)
 then (println "the copy failed: " (pq-result-error-message ?*loaded*)) (exit 1))

(println "loaded " (pq-cmd-tuples ?*loaded*) " rows")
(pq-clear ?*loaded*)

; ----------------------------------------------------------------------
; The question
; ----------------------------------------------------------------------

(deftemplate sensor-summary
  (slot sensor) (slot readings) (slot warmest) (slot average))

(defglobal ?*summary* = (pq-exec ?*conn*
  "SELECT sensor,
          count(*)               AS readings,
          max(celsius)           AS warmest,
          round(avg(celsius)::numeric, 2)::float8 AS average
     FROM readings
    GROUP BY sensor
    ORDER BY sensor"))

(loop-for-count (?row 0 (- (pq-ntuples ?*summary*) 1))
  (pq-row-to-fact ?*summary* ?row sensor-summary))

(pq-clear ?*summary*)

(defrule report
  (sensor-summary (sensor ?s) (readings ?n) (warmest ?max) (average ?avg))
  =>
  (println "  " ?s ": " ?n " readings, warmest " ?max ", average " ?avg))

(defrule running-hot
  (declare (salience -10))
  (sensor-summary (sensor ?s) (average ?avg&:(> ?avg 50.0)))
  =>
  (println "  " ?s " is running hot"))

(println)
(run)

; ----------------------------------------------------------------------
; And back out again, one row at a time
;
; COPY TO STDOUT is the other direction: one call, one row, until the symbol
; done says there are no more.
; ----------------------------------------------------------------------

(defglobal ?*out* = (pq-exec ?*conn*
  "COPY (SELECT sensor, celsius FROM readings ORDER BY minute LIMIT 3)
   TO STDOUT"))
(pq-clear ?*out*)

(println)
(println "the three most recent readings, as the server prints them:")

(defglobal ?*row* = (pq-get-copy-data ?*conn*))
(while (and (neq ?*row* done) (neq ?*row* FALSE))
  (print "  " ?*row*)
  (bind ?*row* (pq-get-copy-data ?*conn*)))

(defglobal ?*copied-out* = (pq-get-result ?*conn*))
(pq-clear ?*copied-out*)

(pq-finish ?*conn*)
(exit)

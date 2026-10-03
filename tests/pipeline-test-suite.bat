; ======================================================================
; Pipeline mode.
;
; Several commands go out without waiting for the results of the ones before
; them, and the results come back in the order they were sent, separated by
; the end-of-command FALSE that pq-get-result answers between them.
; ======================================================================

(println crlf "pipeline-test-suite")

(defglobal ?*plconn* = (connect))

; Reads results until the sync point that closes the pipeline, recording
; each status and writing "end" where pq-get-result marked the end of one
; command's results. The limit is there so that a build that never produces
; the sync point fails the suite instead of hanging it.
(deffunction pipeline-statuses (?conn ?limit)
  (bind ?statuses (create$))
  (bind ?count 0)
  (bind ?done FALSE)
  (while (and (not ?done) (< ?count ?limit))
    (bind ?count (+ ?count 1))
    (bind ?res (pq-get-result ?conn))
    (if ?res
     then
       (bind ?status (pq-result-status ?res))
       (bind ?statuses (create$ ?statuses ?status))
       (pq-clear ?res)
       (if (eq ?status PGRES_PIPELINE_SYNC) then (bind ?done TRUE))
     else
       (bind ?statuses (create$ ?statuses end))))
  ?statuses)

(expect "a connection is not in pipeline mode to begin with"
        PQ_PIPELINE_OFF (pq-pipeline-status ?*plconn*))

(expect "pq-enter-pipeline-mode enters it" TRUE (pq-enter-pipeline-mode ?*plconn*))
(expect "and the connection says so" PQ_PIPELINE_ON (pq-pipeline-status ?*plconn*))

; ----------------------------------------------------------------------
; Two commands, one round trip
; ----------------------------------------------------------------------

(expect "the first command is queued"
        TRUE (pq-send-query-params ?*plconn* "SELECT $1::int" (create$ 1)))
(expect "and the second"
        TRUE (pq-send-query-params ?*plconn* "SELECT $1::int" (create$ 2)))
(expect "pq-pipeline-sync closes the batch and sends it"
        TRUE (pq-pipeline-sync ?*plconn*))

(expect "the results come back in order, each ended, then the sync"
        (create$ PGRES_TUPLES_OK end PGRES_TUPLES_OK end PGRES_PIPELINE_SYNC)
        (pipeline-statuses ?*plconn* 10))

; ----------------------------------------------------------------------
; A command that fails takes the rest of the batch with it
; ----------------------------------------------------------------------

(pq-send-query-params ?*plconn* "SELECT no_such_column" (create$))
(pq-send-query-params ?*plconn* "SELECT 1" (create$))
(pq-pipeline-sync ?*plconn*)

(expect "the failure is reported, and what followed it was never run"
        (create$ PGRES_FATAL_ERROR end PGRES_PIPELINE_ABORTED end PGRES_PIPELINE_SYNC)
        (pipeline-statuses ?*plconn* 10))

; The pipeline is usable again after the sync that ended the aborted batch.
(expect "and the pipeline recovers with the next sync"
        PQ_PIPELINE_ON (pq-pipeline-status ?*plconn*))

; ----------------------------------------------------------------------
; Asking for results without ending the batch
; ----------------------------------------------------------------------

(pq-send-query-params ?*plconn* "SELECT 1" (create$))
(expect "pq-send-flush-request asks the server for what it has so far"
        TRUE (pq-send-flush-request ?*plconn*))
(expect "pq-flush sends it" TRUE (pq-flush ?*plconn*))

(defglobal ?*flushed-result* = (pq-get-result ?*plconn*))
(expect "and the result arrives without a sync"
        PGRES_TUPLES_OK (pq-result-status ?*flushed-result*))
(pq-clear ?*flushed-result*)

(defglobal ?*end-marker* = (pq-get-result ?*plconn*))
(expect "followed by the end of that command's results" FALSE ?*end-marker*)

; pq-send-pipeline-sync, which queues a sync without flushing, is tested in
; tests/pg17-test-suite.bat: it arrived in PostgreSQL 17.
(pq-pipeline-sync ?*plconn*)
(expect "the sync that ends this batch reads out"
        (create$ PGRES_PIPELINE_SYNC) (pipeline-statuses ?*plconn* 5))

; ----------------------------------------------------------------------
; Leaving
; ----------------------------------------------------------------------

(expect "pq-exit-pipeline-mode leaves once everything has been read"
        TRUE (pq-exit-pipeline-mode ?*plconn*))
(expect "and the connection is back to ordinary mode"
        PQ_PIPELINE_OFF (pq-pipeline-status ?*plconn*))

; The simple query protocol has no place in a pipeline. libpq 15 and later
; refuse it rather than sending something the server would not understand.
;
; libpq 14 accepts it, and what follows from that is not worth asserting on:
; the result never arrives and the next read waits for it forever. What is
; being checked is that a refusal happens where there is one, so it runs
; where there is one -- and it asks pq-lib-version, because this is the one
; behaviour in this suite that comes from the library loaded rather than
; from the library the wrappers were compiled against.
(defglobal ?*simple-in-pipeline* = nil)

(if (>= (pq-lib-version) 150000)
 then
   (pq-enter-pipeline-mode ?*plconn*)
   (bind ?*simple-in-pipeline* (pq-send-query ?*plconn* "SELECT 1"))
   (expect "pq-send-query is refused inside a pipeline"
           FALSE ?*simple-in-pipeline*)
   (pq-exit-pipeline-mode ?*plconn*))

(defglobal ?*exit-twice* = (pq-exit-pipeline-mode ?*plconn*))
(expect "leaving a mode the connection is not in is not an error"
        TRUE ?*exit-twice*)

(pq-finish ?*plconn*)

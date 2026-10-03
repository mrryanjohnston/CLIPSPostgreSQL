; ======================================================================
; A rule that fires on what another session did
;
; LISTEN and NOTIFY are how PostgreSQL tells a client that something
; happened without being asked. Here one connection listens, another does
; the work, and the notifications become facts for the rules to act on.
;
;   ./vendor/clips/clips -f2 examples/2-listen-notify.bat
; ======================================================================

(defglobal ?*listener* = (pq-connectdb ""))
(defglobal ?*worker*   = (pq-connectdb ""))

(if (or (neq (pq-status ?*listener*) CONNECTION_OK)
        (neq (pq-status ?*worker*) CONNECTION_OK))
 then
   (println "cannot connect: " (pq-error-message ?*listener*))
   (exit 1))

(deffunction run-on (?conn ?sql)
  (bind ?res (pq-exec ?conn ?sql))
  (if (eq (pq-result-status ?res) PGRES_FATAL_ERROR)
   then (println (pq-result-error-message ?res)) (exit 1))
  (pq-clear ?res))

; ----------------------------------------------------------------------
; A table, and a trigger that announces what happens to it
; ----------------------------------------------------------------------

(run-on ?*worker* "CREATE TABLE IF NOT EXISTS example_orders (
                     id     serial PRIMARY KEY,
                     item   text,
                     amount int)")
(run-on ?*worker* "TRUNCATE example_orders")

(run-on ?*worker* "CREATE OR REPLACE FUNCTION example_announce()
                   RETURNS trigger LANGUAGE plpgsql AS $$
                   BEGIN
                     PERFORM pg_notify('orders', NEW.item || ' ' || NEW.amount);
                     RETURN NEW;
                   END $$")

(run-on ?*worker* "CREATE OR REPLACE TRIGGER example_announce_trigger
                   AFTER INSERT ON example_orders
                   FOR EACH ROW EXECUTE FUNCTION example_announce()")

(run-on ?*listener* "LISTEN orders")
(println "listening on channel orders")

; ----------------------------------------------------------------------
; The work, done by the other session
; ----------------------------------------------------------------------

(run-on ?*worker* "INSERT INTO example_orders (item, amount)
                   VALUES ('flange', 3), ('bolt', 500), ('gasket', 12)")

; ----------------------------------------------------------------------
; Collecting what arrived
;
; A notification arrives with whatever else is read from the connection, so
; the loop reads input and asks, over and over, until one is there.
; pq-notifies answers FALSE when nothing is waiting, which is not a failure
; -- it is how the loop knows to keep asking.
;
; On PostgreSQL 17 and later there is a better way to spend that time:
; (pq-socket-poll (pq-socket ?conn) TRUE FALSE deadline) waits until the
; connection has something to say rather than asking repeatedly, with
; pq-get-current-time-usec giving the deadline. This example asks, so that
; it runs against every version the library supports.
; ----------------------------------------------------------------------

(deftemplate order-placed (slot item) (slot amount) (slot from-backend))

(deffunction collect-notifications (?conn ?attempts)
  (bind ?count 0)
  (while (> ?attempts 0)
    (bind ?attempts (- ?attempts 1))
    (pq-consume-input ?conn)
    (bind ?note (pq-notifies ?conn))
    (while ?note
      (bind ?payload (explode$ (nth$ 3 ?note)))
      (assert (order-placed (item (nth$ 1 ?payload))
                            (amount (nth$ 2 ?payload))
                            (from-backend (nth$ 2 ?note))))
      (bind ?count (+ ?count 1))
      (bind ?note (pq-notifies ?conn)))
    (if (> ?count 0) then (return ?count)))
  ?count)

(defglobal ?*arrived* = (collect-notifications ?*listener* 500))

(println "notifications: " ?*arrived*)

; ----------------------------------------------------------------------
; The rules
; ----------------------------------------------------------------------

(defrule large-order
  (order-placed (item ?item) (amount ?amount&:(> ?amount 100)) (from-backend ?pid))
  =>
  (println "  large order: " ?amount " x " ?item " (backend " ?pid ")"))

(defrule ordinary-order
  (order-placed (item ?item) (amount ?amount&:(<= ?amount 100)))
  =>
  (println "  order: " ?amount " x " ?item))

(run)

; ----------------------------------------------------------------------
; Cleaning up after an example that made a table outside a transaction
; ----------------------------------------------------------------------

(run-on ?*worker* "DROP TABLE example_orders")
(run-on ?*worker* "DROP FUNCTION example_announce()")

(pq-finish ?*worker*)
(pq-finish ?*listener*)
(exit)

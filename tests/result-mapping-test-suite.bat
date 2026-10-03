; ======================================================================
; Whole results as CLIPS data.
;
; pq-exec-to-facts / -to-instances / -to-multifields and their result-taking
; halves: one call that leaves every row of a result in working memory, or in
; one flat multifield, and answers what it made in row order.
;
; The cell conversion is the one the row mappers use and
; row-mapping-test-suite.bat covers; what is under test here is the walk
; over the rows -- which columns land, which rows are lost and what happens
; to the rows around them -- and, for the pq-exec-to-* forms, the shape
; inferred from the table the columns come from.
; ======================================================================

(println crlf "result-mapping-test-suite")

(defglobal ?*wconn* = (connect))

; The scratch global every refusal below is bound through, on a line of its
; own, so that a refusal fails an assertion rather than aborting one.
(defglobal ?*w* = nothing)

(run-sql ?*wconn* "CREATE TEMP TABLE orders (id int, product text, amount float8)")
(run-sql ?*wconn* "INSERT INTO orders VALUES (1, 'widget', 19.99), (2, 'gadget', 49.5), (3, NULL, 99.0)")

; a second table with no deftemplate and no defclass of its own, for the two
; refusals that need one: a join over two tables, and an inferred name with
; no shape behind it
(run-sql ?*wconn* "CREATE TEMP TABLE plain (id int)")

; ----------------------------------------------------------------------
; Facts, with the deftemplate named
; ----------------------------------------------------------------------

(defglobal ?*facts* = (pq-exec-to-facts ?*wconn*
  "SELECT id, product, amount FROM orders ORDER BY id" orders))

(expect "one fact per row" 3 (length$ ?*facts*))

(defglobal ?*fact-1* = (nth$ 1 ?*facts*))
(expect-true "the answer holds fact addresses" (fact-existp ?*fact-1*))
(expect "an integer column lands in its slot" 1 (fact-slot-value ?*fact-1* id))
(expect "a text column lands in its slot" "widget" (fact-slot-value ?*fact-1* product))
(expect "a float column lands in its slot" 19.99 (fact-slot-value ?*fact-1* amount))
(expect "in row order" 3 (fact-slot-value (nth$ 3 ?*facts*) id))
(expect "and SQL NULL is nil" nil (fact-slot-value (nth$ 3 ?*facts*) product))

; the facts are in working memory, not merely described
(defglobal ?*found* = (find-all-facts ((?f orders)) (eq ?f:product "gadget")))
(expect "the facts are in working memory" 1 (length$ ?*found*))

; CLIPS refuses a duplicate fact and answers the one that already carries the
; row, so the answer stays row-aligned while working memory does not grow
(defglobal ?*facts-again* = (pq-exec-to-facts ?*wconn*
  "SELECT id, product, amount FROM orders ORDER BY id" orders))
(expect "a repeated query still answers one entry per row" 3 (length$ ?*facts-again*))
(expect-true "and names the facts that already held those rows"
             (eq (nth$ 1 ?*facts-again*) ?*fact-1*))
(expect "so working memory did not grow" 3
        (length$ (find-all-facts ((?f orders)) TRUE)))

; ----------------------------------------------------------------------
; The deftemplate inferred from the table the columns come from
; ----------------------------------------------------------------------

(defglobal ?*inferred* = (pq-exec-to-facts ?*wconn*
  "SELECT id, product, amount FROM orders ORDER BY id"))
(expect "the deftemplate is inferred from the table" 3 (length$ ?*inferred*))
(expect-true "and is the one the named call used"
             (eq (nth$ 1 ?*inferred*) ?*fact-1*))

; a computed column says nothing about where it came from and is not
; counted, so an aggregate over one table still infers that table
(defglobal ?*grouped* = (pq-exec-to-facts ?*wconn*
  "SELECT id, product, sum(amount) AS amount FROM orders GROUP BY id, product"))
(expect "a GROUP BY over one table still infers it" 3 (length$ ?*grouped*))

; a self-join is still one table
(defglobal ?*self-joined* = (pq-exec-to-facts ?*wconn*
  "SELECT a.id, b.product FROM orders a JOIN orders b ON a.id = b.id"))
(expect "a self-join is still one table" 3 (length$ ?*self-joined*))

; ----------------------------------------------------------------------
; Instances
; ----------------------------------------------------------------------

(defglobal ?*instances* = (pq-exec-to-instances ?*wconn*
  "SELECT id, product, amount FROM orders ORDER BY id" ORDERS))

(expect "one instance per row" 3 (length$ ?*instances*))

(defglobal ?*instance-1* = (nth$ 1 ?*instances*))
(expect-true "the answer holds instance addresses" (instancep ?*instance-1*))
(expect "a slot carries what the row held" 1 (send ?*instance-1* get-id))
(expect "and so does a string slot" "widget" (send ?*instance-1* get-product))

; unlike facts, instances are not deduplicated
(defglobal ?*instances-again* = (pq-exec-to-instances ?*wconn*
  "SELECT id, product, amount FROM orders ORDER BY id" ORDERS))
(expect "a second call makes new instances" 3 (length$ ?*instances-again*))
(expect "which are not the first call's" FALSE
        (eq (nth$ 1 ?*instances-again*) ?*instance-1*))

; the defclass is inferred as the table name in capitals
(defglobal ?*instances-inferred* = (pq-exec-to-instances ?*wconn*
  "SELECT id, product, amount FROM orders ORDER BY id"))
(expect "the defclass is inferred" 3 (length$ ?*instances-inferred*))
(expect "as the table name in capitals" ORDERS (class (nth$ 1 ?*instances-inferred*)))

; ----------------------------------------------------------------------
; Naming the instances. The last argument is positional: the nth name goes
; to the nth row, and a row with no name of its own is named by CLIPS.
; ----------------------------------------------------------------------

(defglobal ?*named* = (pq-exec-to-instances ?*wconn*
  "SELECT id FROM orders ORDER BY id" ORDERS (create$ n-a n-b n-c)))
(expect "a name apiece still makes one instance per row" 3 (length$ ?*named*))
(expect "the first row takes the first name" [n-a] (instance-name (nth$ 1 ?*named*)))
(expect "in row order" [n-b] (instance-name (nth$ 2 ?*named*)))
(expect "to the last of them" [n-c] (instance-name (nth$ 3 ?*named*)))
(expect "and the named instance holds the row" 1 (send (nth$ 1 ?*named*) get-id))

; shorter than the result: the rows past the end are named by CLIPS
(defglobal ?*named-short* = (pq-exec-to-instances ?*wconn*
  "SELECT id FROM orders ORDER BY id" ORDERS (create$ n-short)))
(expect "a short list still makes every row" 3 (length$ ?*named-short*))
(expect "naming the rows it has entries for" [n-short]
        (instance-name (nth$ 1 ?*named-short*)))
(expect "and leaving the rest to CLIPS" FALSE
        (eq (instance-name (nth$ 2 ?*named-short*)) [n-short]))

; longer than the result: the surplus is never asked for
(defglobal ?*named-long* = (pq-exec-to-instances ?*wconn*
  "SELECT id FROM orders ORDER BY id" ORDERS (create$ n-l1 n-l2 n-l3 n-l4 n-l5)))
(expect "a long list makes no more rows than the result has" 3 (length$ ?*named-long*))
(expect "and the surplus names nothing" 0
        (length$ (find-all-instances ((?i ORDERS)) (eq (instance-name ?i) [n-l4]))))

; an empty multifield is the argument left out
(defglobal ?*named-none* = (pq-exec-to-instances ?*wconn*
  "SELECT id FROM orders ORDER BY id" ORDERS (create$)))
(expect "an empty list names nothing" 3 (length$ ?*named-none*))

; one lexeme is the one-entry list: it names the first row only
(defglobal ?*named-one* = (pq-exec-to-instances ?*wconn*
  "SELECT id FROM orders ORDER BY id" ORDERS n-one))
(expect "a single symbol names the first row" [n-one]
        (instance-name (nth$ 1 ?*named-one*)))
(expect "and leaves the rest to CLIPS" FALSE
        (eq (instance-name (nth$ 2 ?*named-one*)) [n-one]))

; a string and an instance name are taken as readily as a symbol
(defglobal ?*named-kinds* = (pq-exec-to-instances ?*wconn*
  "SELECT id FROM orders ORDER BY id" ORDERS (create$ "n-str" [n-ins] n-sym)))
(expect "a string names a row" [n-str] (instance-name (nth$ 1 ?*named-kinds*)))
(expect "so does an instance name" [n-ins] (instance-name (nth$ 2 ?*named-kinds*)))
(expect "and a symbol" [n-sym] (instance-name (nth$ 3 ?*named-kinds*)))

; a multifield argument can arrive as a window onto a longer one, so the
; names are read from where the window starts
(defglobal ?*named-slice* = (pq-exec-to-instances ?*wconn*
  "SELECT id FROM orders ORDER BY id" ORDERS (rest$ (create$ n-skipped n-sl1 n-sl2))))
(expect "a sliced list starts where the slice does" [n-sl1]
        (instance-name (nth$ 1 ?*named-slice*)))
(expect "and does not read the field in front of it" [n-sl2]
        (instance-name (nth$ 2 ?*named-slice*)))
(expect "so the name outside the slice names nothing" 0
        (length$ (find-all-instances ((?i ORDERS)) (eq (instance-name ?i) [n-skipped]))))

; a multifield in the third position is the names, not the class: a class is
; one lexeme and a list of names is a multifield, so the two cannot be
; confused, and this is how rows are named while the class is still inferred
(defglobal ?*named-inferred* = (pq-exec-to-instances ?*wconn*
  "SELECT id FROM orders ORDER BY id" (create$ n-inf)))
(expect "a multifield third argument still infers the class" ORDERS
        (class (nth$ 1 ?*named-inferred*)))
(expect "and names the rows" [n-inf] (instance-name (nth$ 1 ?*named-inferred*)))

; reusing a name is CLIPS's own rule: the old instance of the same class is
; deleted and a new one takes the name
(defglobal ?*named-dup* = (pq-exec-to-instances ?*wconn*
  "SELECT id FROM orders ORDER BY id" ORDERS (create$ n-dup n-dup n-dup)))
(expect "a repeated name answers a row apiece" 3 (length$ ?*named-dup*))
(expect "but leaves one instance holding the name" 1
        (length$ (find-all-instances ((?i ORDERS)) (eq (instance-name ?i) [n-dup]))))
(expect "and it is the last row's" 3 (send (nth$ 3 ?*named-dup*) get-id))

; a name held by an instance of another class loses that row and only that
; row: CLIPS refuses the build and halts, and the halt is undone so the row
; after it gets its own attempt
(make-instance [n-taken] of NAME-HOLDER)
(bind ?*w* (pq-exec-to-instances ?*wconn*
  "SELECT id FROM orders ORDER BY id" ORDERS (create$ n-taken n-after1 n-after2)))
(expect "a name another class holds loses its own row" 2 (length$ ?*w*))
(expect "and only its own row" [n-after1] (instance-name (nth$ 1 ?*w*)))
(expect "with the row after that intact too" [n-after2] (instance-name (nth$ 2 ?*w*)))
(expect "and the instance holding the name is untouched" NAME-HOLDER (class [n-taken]))

; a name that is not a lexeme is refused before any row is built
(bind ?*w* (pq-exec-to-instances ?*wconn*
  "SELECT id FROM orders" ORDERS (create$ n-bad1 7 n-bad3)))
(expect "a non-lexeme name refuses the call" FALSE ?*w*)
(expect "and builds nothing before it refuses" 0
        (length$ (find-all-instances ((?i ORDERS)) (eq (instance-name ?i) [n-bad1]))))

; the names cannot be given twice
(bind ?*w* (pq-exec-to-instances ?*wconn*
  "SELECT id FROM orders" (create$ n-x) (create$ n-y)))
(expect "the names given twice is refused" FALSE ?*w*)

; an instance's name is not a slot, so a column called "name" goes to _name,
; as it does for pq-row-to-instance
(defglobal ?*renamed* = (pq-exec-to-instances ?*wconn*
  "SELECT 'bolt' AS name, 42 AS v" ROWS-NAMED))
(expect "a column called name goes to the _name slot" "bolt"
        (send (nth$ 1 ?*renamed*) get-_name))
(expect "and the other columns are unaffected" 42 (send (nth$ 1 ?*renamed*) get-v))

; ----------------------------------------------------------------------
; The multifield form: one flat multifield of the values, row by row. The
; column names are opt-in, because prepending them would shift every index
; a caller computes.
; ----------------------------------------------------------------------

(defglobal ?*flat* = (pq-exec-to-multifields ?*wconn*
  "SELECT id, product, amount FROM orders ORDER BY id"))
(expect "three rows of three, and no names" 9 (length$ ?*flat*))
(expect "the first field is the first value" 1 (nth$ 1 ?*flat*))
(expect "in column order" "widget" (nth$ 2 ?*flat*))
(expect "and the row after it follows" 2 (nth$ 4 ?*flat*))
(expect "a NULL cell is nil here too" nil (nth$ 8 ?*flat*))

(defglobal ?*flat-false* = (pq-exec-to-multifields ?*wconn*
  "SELECT id, product, amount FROM orders ORDER BY id" FALSE))
(expect "FALSE is what leaving it out means" 9 (length$ ?*flat-false*))

(defglobal ?*flat-headed* = (pq-exec-to-multifields ?*wconn*
  "SELECT id, product, amount FROM orders ORDER BY id" TRUE))
(expect "TRUE adds one field per column in front" 12 (length$ ?*flat-headed*))
(expect "the first fields are the column names" "id" (nth$ 1 ?*flat-headed*))
(expect "in column order" "product" (nth$ 2 ?*flat-headed*))
(expect "all of them" "amount" (nth$ 3 ?*flat-headed*))
(expect "then the first row's values" 1 (nth$ 4 ?*flat-headed*))
(expect "shifted by exactly the column count" "widget" (nth$ 5 ?*flat-headed*))

; a flag that is neither TRUE nor FALSE is refused rather than read as truthy
(defglobal ?*maybe* = maybe)
(bind ?*w* (pq-exec-to-multifields ?*wconn* "SELECT id FROM orders" ?*maybe*))
(expect "a non-boolean headers flag is refused" FALSE ?*w*)

; a query answering no rows answers nothing at all, or its header alone
(defglobal ?*flat-empty* = (pq-exec-to-multifields ?*wconn*
  "SELECT id FROM orders WHERE FALSE"))
(expect "an empty result is empty" 0 (length$ ?*flat-empty*))

(defglobal ?*flat-empty-headed* = (pq-exec-to-multifields ?*wconn*
  "SELECT id FROM orders WHERE FALSE" TRUE))
(expect "and headed by its column name when asked" 1 (length$ ?*flat-empty-headed*))
(expect "which is the column's name" "id" (nth$ 1 ?*flat-empty-headed*))

; the cell conversion is the row mappers': integers, floats, TRUE/FALSE, nil
(defglobal ?*typed* = (pq-exec-to-multifields ?*wconn*
  "SELECT 1::int2 AS small, 6.25::numeric AS exact, true AS flag, NULL::text AS nothing"))
(expect-true "an integer really is an integer" (integerp (nth$ 1 ?*typed*)))
(expect-true "a numeric really is a float" (floatp (nth$ 2 ?*typed*)))
(expect "boolean becomes TRUE or FALSE" TRUE (nth$ 3 ?*typed*))
(expect "and SQL NULL becomes nil" nil (nth$ 4 ?*typed*))

; a command that answers no rows at all answers an empty multifield
(defglobal ?*no-rows* = (pq-exec-to-multifields ?*wconn* "CREATE TEMP TABLE scratch (i int)"))
(expect "a command with no rows answers an empty multifield" 0 (length$ ?*no-rows*))

; ----------------------------------------------------------------------
; The result-taking half. A result carries no connection to ask about its
; tables, so it names its shape; and a PGresult is read in place, so unlike
; a DuckDB result it is not drained by having been read.
; ----------------------------------------------------------------------

(defglobal ?*res* = (pq-exec ?*wconn* "SELECT id, product, amount FROM orders ORDER BY id"))

(defglobal ?*res-facts* = (pq-result-to-facts ?*res* orders))
(expect "a result converts row for row" 3 (length$ ?*res-facts*))
(expect-true "to the facts the exec form made" (eq (nth$ 1 ?*res-facts*) ?*fact-1*))

(defglobal ?*res-facts-again* = (pq-result-to-facts ?*res* orders))
(expect "and is not drained by having been read" 3 (length$ ?*res-facts-again*))

(defglobal ?*res-instances* = (pq-result-to-instances ?*res* ORDERS (create$ r-1 r-2)))
(expect "a result converts to instances" 3 (length$ ?*res-instances*))
(expect "named from the same positional list" [r-1] (instance-name (nth$ 1 ?*res-instances*)))
(expect "that runs off the end the same way" [r-2] (instance-name (nth$ 2 ?*res-instances*)))

(defglobal ?*res-flat* = (pq-result-to-multifields ?*res* TRUE))
(expect "a result converts to a multifield" 12 (length$ ?*res-flat*))
(expect "and takes the headers flag too" "id" (nth$ 1 ?*res-flat*))

(defglobal ?*res-plain* = (pq-result-to-multifields ?*res*))
(expect "or leaves the headers out" 9 (length$ ?*res-plain*))

; a string names a shape as well as a symbol does
(defglobal ?*res-string* = (pq-result-to-facts ?*res* "orders"))
(expect "a string names the deftemplate too" 3 (length$ ?*res-string*))

(pq-clear ?*res*)

(bind ?*w* (pq-result-to-facts ?*res* orders))
(expect "a cleared result is refused" FALSE ?*w*)

; ----------------------------------------------------------------------
; Refusals. Nothing is put into working memory by a refused call: the shape
; is checked before the first row is read.
; ----------------------------------------------------------------------

(bind ?*w* (pq-exec-to-facts ?*wconn* "SELECT 42 AS id"))
(expect "a query over no table cannot infer a name" FALSE ?*w*)

(bind ?*w* (pq-exec-to-facts ?*wconn*
  "SELECT a.id, b.id AS other FROM orders a JOIN plain b ON a.id = b.id"))
(expect "nor can one over two" FALSE ?*w*)

(bind ?*w* (pq-exec-to-facts ?*wconn* "SELECT id FROM orders" no-such-template))
(expect "an absent deftemplate is refused" FALSE ?*w*)

(bind ?*w* (pq-exec-to-instances ?*wconn* "SELECT id FROM orders" NO-SUCH-CLASS))
(expect "an absent defclass is refused" FALSE ?*w*)

(bind ?*w* (pq-exec-to-facts ?*wconn* "SELECT id FROM plain"))
(expect "an inferred name with no deftemplate behind it is refused" FALSE ?*w*)

; a command the server refuses is FALSE here, with the server's message,
; where pq-exec would answer a result whose status says so
(bind ?*w* (pq-exec-to-facts ?*wconn* "SELECT nonsense FROM"))
(expect "a command that will not parse is refused" FALSE ?*w*)

(bind ?*w* (pq-exec-to-multifields ?*wconn* "SELECT nonsense FROM"))
(expect "for the multifield form as well" FALSE ?*w*)

(expect "and the connection is still good" CONNECTION_OK (pq-status ?*wconn*))

; ----------------------------------------------------------------------
; A column with no slot to land in is passed over, not refused: the query
; decides what it selects and the shape decides what it holds. Which columns
; are skipped is decided once, before the first row.
; ----------------------------------------------------------------------

(defglobal ?*partial* = (pq-exec-to-facts ?*wconn*
  "SELECT id, product, amount FROM orders ORDER BY id" orders-id))
(expect "the rows still land when a column has no slot" 3 (length$ ?*partial*))
(expect "the column that does have one carries its value" 1
        (fact-slot-value (nth$ 1 ?*partial*) id))
(expect "and the last row's too" 3 (fact-slot-value (nth$ 3 ?*partial*) id))

(defglobal ?*partial-instances* = (pq-exec-to-instances ?*wconn*
  "SELECT id, product, amount FROM orders ORDER BY id" ORDERS-ID))
(expect "instances pass over an unmatched column too" 3 (length$ ?*partial-instances*))
(expect "keeping the slot they do have" 2 (send (nth$ 2 ?*partial-instances*) get-id))

; when no column matches, every row builds the same empty fact and CLIPS
; collapses the duplicates: the answer stays row-aligned, working memory
; gains one fact
(defglobal ?*none* = (pq-exec-to-facts ?*wconn*
  "SELECT id, product FROM orders" orders-unrelated))
(expect "no column matching still answers one entry per row" 3 (length$ ?*none*))
(expect "but the empty facts are all the same one" 1
        (length$ (find-all-facts ((?f orders-unrelated)) TRUE)))

; ----------------------------------------------------------------------
; A value the slot refuses. The slot exists -- that was checked before any
; row was read -- so this is the value: such a row is skipped rather than
; asserted half-filled, and the answer is the record of what was made.
; ----------------------------------------------------------------------

; two rows hold a string where the slot wants a symbol; the third holds
; NULL, and nil is a symbol
(bind ?*w* (pq-exec-to-facts ?*wconn* "SELECT id, product FROM orders ORDER BY id" orders-strict))
(expect "a row whose value the slot refuses is skipped" 1 (length$ ?*w*))
(expect "and the row the slot accepts is the one that lands" 3
        (fact-slot-value (nth$ 1 ?*w*) id))
(expect "leaving no half-filled fact behind" 1
        (length$ (find-all-facts ((?f orders-strict)) TRUE)))

; a refused row must not take the rows around it with it, nor leave anything
; of itself in the next one
(bind ?*w* (pq-exec-to-facts ?*wconn* "SELECT id FROM orders ORDER BY id" orders-ranged))
(expect "the rows either side of a refused one still land" 2 (length$ ?*w*))
(expect "the first of them keeps its own value" 1 (fact-slot-value (nth$ 1 ?*w*) id))
(expect "and so does the one after the refusal" 2 (fact-slot-value (nth$ 2 ?*w*) id))
(expect "and nothing else was asserted" 2
        (length$ (find-all-facts ((?f orders-ranged)) TRUE)))

(bind ?*w* (pq-exec-to-instances ?*wconn* "SELECT id FROM orders ORDER BY id" ORDERS-RANGED))
(expect "an instance builder survives a refused row too" 2 (length$ ?*w*))
(expect "with the row after it intact" 2 (send (nth$ 2 ?*w*) get-id))

; a row can also be lost at the build itself: an abstract class cannot be
; instantiated at all, so every row loses, and every row gets its own attempt
(bind ?*w* (pq-exec-to-instances ?*wconn* "SELECT id FROM orders" ORDERS-ABSTRACT))
(expect "an abstract class makes no instance for any row" 0 (length$ ?*w*))
(expect "leaving nothing behind" 0
        (length$ (find-all-instances ((?i ORDERS-ABSTRACT)) TRUE)))

; ----------------------------------------------------------------------
; A result wider than a few rows, so that a walk that stopped early or
; restarted would show
; ----------------------------------------------------------------------

(defglobal ?*big* = (pq-exec-to-facts ?*wconn*
  "SELECT i AS id FROM generate_series(0, 4999) AS s(i)" series))
(expect "every row of a large result" 5000 (length$ ?*big*))
(expect "the first row is the first row" 0 (fact-slot-value (nth$ 1 ?*big*) id))
(expect "and the last is the last" 4999 (fact-slot-value (nth$ 5000 ?*big*) id))

; ----------------------------------------------------------------------
; Arguments the whole-result forms refuse
; ----------------------------------------------------------------------

(defglobal ?*a-float* = 1.5)
(defglobal ?*an-integer* = 7)
(defglobal ?*res2* = (pq-exec ?*wconn* "SELECT id FROM orders ORDER BY id"))

(bind ?*w* (pq-result-to-multifields ?*res2* ?*maybe*))
(expect "pq-result-to-multifields refuses a non-boolean headers flag" FALSE ?*w*)

(bind ?*w* (pq-result-to-facts ?*res2* ?*an-integer*))
(expect "pq-result-to-facts refuses an integer where the deftemplate belongs" FALSE ?*w*)

(bind ?*w* (pq-result-to-instances ?*res2* ORDERS ?*a-float*))
(expect "pq-result-to-instances refuses a float where the instance names belong" FALSE ?*w*)

(bind ?*w* (pq-exec-to-facts ?*wconn* ?*an-integer*))
(expect "pq-exec-to-facts refuses an integer where the command belongs" FALSE ?*w*)

(bind ?*w* (pq-exec-to-facts ?*wconn* "SELECT id FROM orders" ?*an-integer*))
(expect "and an integer where the deftemplate belongs" FALSE ?*w*)

(bind ?*w* (pq-exec-to-instances ?*wconn* "SELECT id FROM orders" (create$ n-third 7)))
(expect "a non-lexeme in a multifield third argument refuses the call" FALSE ?*w*)

; An implied deftemplate has no slots, so the whole result is refused before
; the first row, as one row is by pq-row-to-fact.
(assert (ordered-rows 1 2))
(bind ?*w* (pq-result-to-facts ?*res2* ordered-rows))
(expect "an implied deftemplate is refused" FALSE ?*w*)

(pq-clear ?*res2*)

; ----------------------------------------------------------------------
; A name that cannot be inferred because the table is gone
;
; The name is read from pg_class after the command has run, on the same
; connection. A temporary table that drops itself when the command's
; transaction ends is gone by then: the columns still say which table they
; came from, and the catalogue no longer has it.
; ----------------------------------------------------------------------

(bind ?*w* (pq-exec-to-facts ?*wconn*
  "CREATE TEMP TABLE gone (id int) ON COMMIT DROP; INSERT INTO gone VALUES (1); SELECT id FROM gone"))
(expect "a table gone by the time its name is looked up cannot infer one" FALSE ?*w*)

; ----------------------------------------------------------------------
; A connection that will not run the command
;
; In pipeline mode libpq refuses the synchronous PQexec outright, with no
; result to read a status from: the one refusal here that carries libpq's
; message rather than the server's.
; ----------------------------------------------------------------------

(pq-enter-pipeline-mode ?*wconn*)
(bind ?*w* (pq-exec-to-facts ?*wconn* "SELECT id FROM orders" orders))
(expect "a connection in pipeline mode runs no synchronous command" FALSE ?*w*)
(pq-exit-pipeline-mode ?*wconn*)
(expect "and is still good afterwards" CONNECTION_OK (pq-status ?*wconn*))

; ----------------------------------------------------------------------
; A result mapped while CLIPS is pattern-matching
;
; CLIPS refuses every fact asserted while it is matching another, so a
; whole result mapped from a rule's LHS loses every row -- and answers an
; empty multifield rather than refusing, because each row was its own
; attempt, as it is everywhere else here.
; ----------------------------------------------------------------------

(defglobal ?*rows-during-match* = untried)
(defglobal ?*res3* =
  (pq-exec ?*wconn* "SELECT i AS id FROM generate_series(10000, 10002) AS s(i)"))

(defrule rows-during-match
  (map-the-rows)
  (test (eq 0 (length$ (pq-result-to-facts ?*res3* series))))
  =>
  (bind ?*rows-during-match* every-row-lost))

(assert (map-the-rows))
(run)
(expect "a result mapped from a rule's LHS loses every row"
        every-row-lost ?*rows-during-match*)
(expect "and asserted none of them" 0
        (length$ (find-all-facts ((?f series)) (>= ?f:id 10000))))
(pq-clear ?*res3*)

(pq-finish ?*wconn*)

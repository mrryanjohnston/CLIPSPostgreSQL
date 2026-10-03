; ------------------------------------------------------------
; Templates and classes the suites map result rows onto.
;
; pq-row-to-fact and pq-row-to-instance take the column names of the row as
; slot names, so every template here is named after the query that fills it
; rather than after anything in PostgreSQL. A column the shape has no slot
; for is a hard failure inside the builder, which is why these are kept next
; to the queries instead of being reused loosely.
; ------------------------------------------------------------

; SELECT 1 AS a, 2.5::float8 AS b, 'x' AS c
(deftemplate row-abc (slot a) (slot b) (slot c))
(defclass ROW-ABC (is-a USER) (role concrete) (slot a) (slot b) (slot c))

; One row holding every type the mappers convert, so the type mapping is
; asserted against a single shape: the integers, the floating-point types,
; boolean, text, and SQL NULL.
(deftemplate row-types
  (slot small) (slot medium) (slot large) (slot approx) (slot exact)
  (slot flag) (slot txt) (slot nothing))
(defclass ROW-TYPES (is-a USER) (role concrete)
  (slot small) (slot medium) (slot large) (slot approx) (slot exact)
  (slot flag) (slot txt) (slot nothing))

; ------------------------------------------------------------
; "name" is not an ordinary column for pq-row-to-instance: an instance's name
; is not a slot, so a column called "name" is written to a differently named
; slot -- "_name" unless the caller names another one. Both spellings get a
; class here so the default and the override can be told apart.
; ------------------------------------------------------------

; takes the default replacement
(defclass ROW-NAMED (is-a USER) (role concrete) (slot _name) (slot v))
; takes an explicit replacement passed as the fifth argument
(defclass ROW-NAMED-ALT (is-a USER) (role concrete) (slot nm) (slot v))

; A template with no slot for the row's columns: every mapper refuses rather
; than dropping the column on the floor.
(deftemplate row-unrelated (slot nothing-matches))
(defclass ROW-UNRELATED (is-a USER) (role concrete) (slot nothing-matches))

; ------------------------------------------------------------
; Whole results. pq-result-to-facts and the five beside it take every row
; of a result at once, and unlike the row mappers they pass over a column
; with no slot rather than refusing it: the query decides what it selects
; and the shape decides what it holds. The pq-exec-to-* forms can also infer
; the shape from the one table the columns come from, which is why the
; first pair here is named after the table the suite creates -- the
; deftemplate as it is, the defclass in capitals.
; ------------------------------------------------------------

; CREATE TEMP TABLE orders (id int, product text, amount float8)
(deftemplate orders (slot id) (slot product) (slot amount))
(defclass ORDERS (is-a USER) (role concrete) (slot id) (slot product) (slot amount))

; a slot for one of the three columns: the other two are passed over
(deftemplate orders-id (slot id))
(defclass ORDERS-ID (is-a USER) (role concrete) (slot id))

; no slot for any column: every row builds the same empty fact
(deftemplate orders-unrelated (slot nothing))

; slots that refuse what the rows hold, so a row is skipped at a value
; rather than at the shape: every row of the first, one row of the second
(deftemplate orders-strict (slot id (type INTEGER)) (slot product (type SYMBOL)))
(deftemplate orders-ranged (slot id (type INTEGER) (range 0 2)))
(defclass ORDERS-RANGED (is-a USER) (role concrete) (slot id (type INTEGER) (range 0 2)))

; a class no row can become an instance of
(defclass ORDERS-ABSTRACT (is-a USER) (role abstract) (slot id))

; holds an instance name a row is then asked to take
(defclass NAME-HOLDER (is-a USER) (role concrete) (slot id))

; SELECT 'bolt' AS name, 42 AS v -- the "name" column goes to _name
(defclass ROWS-NAMED (is-a USER) (role concrete) (slot _name) (slot v))

; SELECT i AS id FROM generate_series(...)
(deftemplate series (slot id))

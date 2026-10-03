; ======================================================================
; What a result says about its own columns.
; ======================================================================

(println crlf "metadata-test-suite")

(defglobal ?*mconn* = (connect))

(run-sql ?*mconn* "CREATE TEMP TABLE shapes (id int, label varchar(10), area float8)")
(run-sql ?*mconn* "INSERT INTO shapes VALUES (1, 'square', 4.0)")

(defglobal ?*shape* = (pq-exec ?*mconn* "SELECT id, label, area FROM shapes"))

; ----------------------------------------------------------------------
; Names, and finding a column by one
; ----------------------------------------------------------------------

(expect "columns are named as the query named them" "id" (pq-fname ?*shape* 0))
(expect "in order" "area" (pq-fname ?*shape* 2))
(expect "pq-fnumber finds a column by name" 1 (pq-fnumber ?*shape* "label"))
(expect "and answers -1 for a name the result does not have"
        -1 (pq-fnumber ?*shape* "no_such_column"))

(defglobal ?*name-past-end* = (pq-fname ?*shape* 3))
(expect "a column number past the last is refused" FALSE ?*name-past-end*)

; ----------------------------------------------------------------------
; Types, sizes and modifiers, which are what the server said the columns are
; ----------------------------------------------------------------------

(expect "an integer column has the int4 type OID" 23 (pq-ftype ?*shape* 0))
(expect "and is four bytes wide" 4 (pq-fsize ?*shape* 0))
(expect "a double precision column has the float8 OID" 701 (pq-ftype ?*shape* 2))
(expect "and is eight bytes wide" 8 (pq-fsize ?*shape* 2))

; A varchar is variable width, which libpq reports as a negative size, and
; carries its declared length in the type modifier: the declared 10 plus the
; four-byte header.
(expect-true "a varchar has no fixed width" (< (pq-fsize ?*shape* 1) 0))
(expect "and its length lives in the type modifier" 14 (pq-fmod ?*shape* 1))
(expect "a type with no modifier says so with -1" -1 (pq-fmod ?*shape* 0))

; ----------------------------------------------------------------------
; Where a column came from
; ----------------------------------------------------------------------

(expect-true "a column selected from a table names that table's OID"
             (> (pq-ftable ?*shape* 0) 0))
(expect "and its position in the table, counting from one"
        1 (pq-ftablecol ?*shape* 0))
(expect "the third column of the result is the third of the table"
        3 (pq-ftablecol ?*shape* 2))

(defglobal ?*computed* = (pq-exec ?*mconn* "SELECT 1 + 1 AS sum"))
(expect "a computed column belongs to no table"
        FALSE (pq-ftable ?*computed* 0))
(expect "and has no column number in one" FALSE (pq-ftablecol ?*computed* 0))
(pq-clear ?*computed*)

; ----------------------------------------------------------------------
; Format
; ----------------------------------------------------------------------

(expect "everything here is sent in text format" 0 (pq-fformat ?*shape* 0))
(expect "so the result is not a binary one" FALSE (pq-binary-tuples ?*shape*))

(pq-clear ?*shape*)

; ----------------------------------------------------------------------
; A result with no columns at all
; ----------------------------------------------------------------------

(defglobal ?*command* = (pq-exec ?*mconn* "UPDATE shapes SET area = 5.0 WHERE id = 1"))
(expect "a command that returns nothing has no columns" 0 (pq-nfields ?*command*))

(defglobal ?*no-columns* = (pq-fname ?*command* 0))
(expect "and asking for one is refused" FALSE ?*no-columns*)
(pq-clear ?*command*)

(pq-finish ?*mconn*)

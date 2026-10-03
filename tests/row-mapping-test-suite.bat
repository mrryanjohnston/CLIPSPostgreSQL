; ======================================================================
; Rows as CLIPS data.
;
; The three mappers are the only functions here with no counterpart in the C
; API, and the thing they add is the type mapping: a column comes across as
; the CLIPS type its PostgreSQL type calls for, not as the text libpq holds.
; ======================================================================

(println crlf "row-mapping-test-suite")

(defglobal ?*rconn* = (connect))

; ----------------------------------------------------------------------
; A multifield, which needs nothing declared in advance
; ----------------------------------------------------------------------

(defglobal ?*abc* = (pq-exec ?*rconn* "SELECT 1 AS a, 2.5::float8 AS b, 'x' AS c"))

(expect "a row becomes a multifield of converted values"
        (create$ 1 2.5 "x") (pq-row-to-multifield ?*abc* 0))

(defglobal ?*row-past-end* = (pq-row-to-multifield ?*abc* 1))
(expect "a row past the end of the result is refused" FALSE ?*row-past-end*)

; ----------------------------------------------------------------------
; The type mapping, all of it in one row
; ----------------------------------------------------------------------

(defglobal ?*types* = (pq-exec ?*rconn*
  "SELECT 1::int2 AS small, 2::int4 AS medium, 3::int8 AS large,
          4.5::float4 AS approx, 6.25::numeric AS exact,
          true AS flag, 'words' AS txt, NULL::text AS nothing"))

(defglobal ?*converted* = (pq-row-to-multifield ?*types* 0))

(expect "smallint becomes an integer" 1 (nth$ 1 ?*converted*))
(expect "integer becomes an integer" 2 (nth$ 2 ?*converted*))
(expect "bigint becomes an integer" 3 (nth$ 3 ?*converted*))
(expect "real becomes a float" 4.5 (nth$ 4 ?*converted*))
(expect "numeric becomes a float" 6.25 (nth$ 5 ?*converted*))
(expect "boolean becomes TRUE or FALSE" TRUE (nth$ 6 ?*converted*))
(expect "text stays text" "words" (nth$ 7 ?*converted*))
(expect "and SQL NULL becomes the symbol nil" nil (nth$ 8 ?*converted*))

(expect-true "the integers really are integers, not strings"
             (integerp (nth$ 2 ?*converted*)))
(expect-true "and the floats really are floats"
             (floatp (nth$ 5 ?*converted*)))

; A type with no CLIPS equivalent keeps the text PostgreSQL printed, which
; is the only conversion that loses nothing.
(defglobal ?*exotic* = (pq-exec ?*rconn*
  "SELECT '2026-08-26'::date AS d, '{1,2}'::int[] AS arr, '1 day'::interval AS i"))
(defglobal ?*exotic-row* = (pq-row-to-multifield ?*exotic* 0))
(expect "a date stays the text the server printed"
        "2026-08-26" (nth$ 1 ?*exotic-row*))
(expect "so does an array" "{1,2}" (nth$ 2 ?*exotic-row*))
(expect "and an interval" "1 day" (nth$ 3 ?*exotic-row*))
(pq-clear ?*exotic*)

; ----------------------------------------------------------------------
; Facts
; ----------------------------------------------------------------------

(defglobal ?*fact* = (pq-row-to-fact ?*abc* 0 row-abc))

(expect-true "a row becomes a fact" (neq FALSE ?*fact*))
(expect "whose slots are the column names" 1 (fact-slot-value ?*fact* a))
(expect "with the converted values in them" 2.5 (fact-slot-value ?*fact* b))
(expect "including the text" "x" (fact-slot-value ?*fact* c))

(defglobal ?*types-fact* = (pq-row-to-fact ?*types* 0 row-types))
(expect "the type mapping is the same one the multifield gets"
        6.25 (fact-slot-value ?*types-fact* exact))
(expect "and a NULL is nil in a slot too"
        nil (fact-slot-value ?*types-fact* nothing))

(defglobal ?*no-slot* = (pq-row-to-fact ?*abc* 0 row-unrelated))
(expect "a template with no slot for the row's columns is refused"
        FALSE ?*no-slot*)

(defglobal ?*no-template* = (pq-row-to-fact ?*abc* 0 no-such-template))
(expect "and so is a template that does not exist" FALSE ?*no-template*)

; ----------------------------------------------------------------------
; Instances
; ----------------------------------------------------------------------

(defglobal ?*instance* = (pq-row-to-instance ?*abc* 0 ROW-ABC))
(expect-true "a row becomes an instance" (neq FALSE ?*instance*))
(expect "with the converted values in its slots" 1 (send ?*instance* get-a))
(expect "all of them" "x" (send ?*instance* get-c))

(defglobal ?*named* = (pq-row-to-instance ?*abc* 0 ROW-ABC widget-1))
(expect "and it can be given a name" [widget-1] (instance-name ?*named*))

(defglobal ?*no-class* = (pq-row-to-instance ?*abc* 0 NO-SUCH-CLASS))
(expect "a class that does not exist is refused" FALSE ?*no-class*)

(defglobal ?*no-instance-slot* = (pq-row-to-instance ?*abc* 0 ROW-UNRELATED))
(expect "as is a class with no slot for the row's columns" FALSE ?*no-instance-slot*)

; An instance's name is not a slot, so a column called "name" has nowhere to
; go: it is written to _name, or to the slot named in the fifth argument.
(defglobal ?*named-column* =
  (pq-exec ?*rconn* "SELECT 'bolt' AS name, 42 AS v"))

(defglobal ?*renamed* = (pq-row-to-instance ?*named-column* 0 ROW-NAMED))
(expect "a column called name goes to the _name slot by default"
        "bolt" (send ?*renamed* get-_name))
(expect "and the other columns are unaffected" 42 (send ?*renamed* get-v))

(defglobal ?*renamed-alt* =
  (pq-row-to-instance ?*named-column* 0 ROW-NAMED-ALT nil nm))
(expect "or to a slot the caller names"
        "bolt" (send ?*renamed-alt* get-nm))

; The fourth argument is the instance name, and nil there asks for the one
; CLIPS makes up -- which is what a loop over rows wants.
(defglobal ?*unnamed* = (pq-row-to-instance ?*named-column* 0 ROW-NAMED nil))
(expect-true "nil for the instance name leaves CLIPS to make one up"
             (neq FALSE ?*unnamed*))

; ----------------------------------------------------------------------
; Arguments the mappers refuse
;
; The deftemplate, defclass, instance name and name-slot arguments are
; symbols, and a value of another type reaching one through a variable is
; refused by the wrapper, as everywhere else. A string is the one worth
; checking: it looks like a name, and is not one here.
; ----------------------------------------------------------------------

(defglobal ?*not-a-symbol* = "row-abc")
(defglobal ?*rm* = nothing)

(bind ?*rm* (pq-row-to-fact ?*abc* 0 ?*not-a-symbol*))
(expect "pq-row-to-fact refuses a string where the deftemplate name belongs" FALSE ?*rm*)

(bind ?*rm* (pq-row-to-instance ?*abc* 0 ?*not-a-symbol*))
(expect "pq-row-to-instance refuses a string where the defclass name belongs" FALSE ?*rm*)

(bind ?*rm* (pq-row-to-instance ?*abc* 0 ROW-ABC ?*not-a-symbol*))
(expect "and where the instance name belongs" FALSE ?*rm*)

(bind ?*rm* (pq-row-to-instance ?*abc* 0 ROW-ABC nil ?*not-a-symbol*))
(expect "and where the name slot belongs" FALSE ?*rm*)

; ----------------------------------------------------------------------
; Shapes a row cannot take
; ----------------------------------------------------------------------

; An ordered fact has an implied deftemplate with no slots to fill, so there
; is nowhere for a column to go before the first one is looked at.
(assert (ordered-row 1 2 3))
(bind ?*rm* (pq-row-to-fact ?*abc* 0 ordered-row))
(expect "an implied deftemplate is refused" FALSE ?*rm*)

; A slot that exists and will not take the value: the string in the product
; column, where the slot allows only a symbol.
(defglobal ?*id-product* = (pq-exec ?*rconn* "SELECT 1 AS id, 'widget' AS product"))
(bind ?*rm* (pq-row-to-fact ?*id-product* 0 orders-strict))
(expect "a slot whose type the value does not fit is refused" FALSE ?*rm*)
(expect "and nothing was asserted" 0 (length$ (find-all-facts ((?f orders-strict)) TRUE)))
(pq-clear ?*id-product*)

; An abstract class has instances of nothing, so the row has nowhere to go
; once every column has found its slot.
(defglobal ?*id-only* = (pq-exec ?*rconn* "SELECT 1 AS id"))
(bind ?*rm* (pq-row-to-instance ?*id-only* 0 ORDERS-ABSTRACT))
(expect "an abstract class is refused" FALSE ?*rm*)
(pq-clear ?*id-only*)

; And a NULL goes into an instance slot as nil, as it does into a fact.
(defglobal ?*types-instance* = (pq-row-to-instance ?*types* 0 ROW-TYPES))
(expect "a NULL is nil in an instance slot too"
        nil (send ?*types-instance* get-nothing))

; ----------------------------------------------------------------------
; A row mapped while CLIPS is pattern-matching
;
; CLIPS refuses to assert a fact while it is matching another one, and a
; wrapper called from a rule's LHS runs exactly then. The mapper reports it
; as the assertion it was: the fact was built, and CLIPS would not take it.
; ----------------------------------------------------------------------

(defglobal ?*during-match* = untried)

(defrule row-during-match
  (map-a-row)
  (test (eq FALSE (pq-row-to-fact ?*abc* 0 row-abc)))
  =>
  (bind ?*during-match* refused))

(assert (map-a-row))
(run)
(expect "a row mapped to a fact from a rule's LHS is refused, not asserted"
        refused ?*during-match*)

(pq-clear ?*named-column*)
(pq-clear ?*types*)
(pq-clear ?*abc*)
(pq-finish ?*rconn*)

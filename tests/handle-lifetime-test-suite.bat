; ======================================================================
; What handles are worth after the thing they point at is gone.
;
; pq-finish and pq-clear empty the CLIPS value they are given, so a handle
; that has been closed is a handle every other function refuses. Without
; that, the second call would be a second free of the same pointer, and the
; wrappers would be a way to crash CLIPS from a rule.
; ======================================================================

(println crlf "handle-lifetime-test-suite")

; ----------------------------------------------------------------------
; A result belongs to the caller, not to the connection
;
; libpq copies everything a result holds out of the connection before
; handing it over, so a result stays readable after the connection it came
; from is gone. It is also still the caller's to clear.
; ----------------------------------------------------------------------

(defglobal ?*hconn* = (connect))
(defglobal ?*outliving* = (pq-exec ?*hconn* "SELECT 'still here' AS note, 7 AS n"))

(expect "the result is readable while the connection is open"
        "still here" (pq-getvalue ?*outliving* 0 0))

(pq-finish ?*hconn*)

(expect "and after the connection has been finished"
        "still here" (pq-getvalue ?*outliving* 0 0))
(expect "including its metadata" "note" (pq-fname ?*outliving* 0))
(expect "and its shape" 2 (pq-nfields ?*outliving*))
(expect "and it is still the caller's to clear" TRUE (pq-clear ?*outliving*))

; ----------------------------------------------------------------------
; A cleared result
; ----------------------------------------------------------------------

(defglobal ?*cleared-again* = (pq-clear ?*outliving*))
(expect "clearing a result twice is refused" FALSE ?*cleared-again*)

(defglobal ?*read-cleared* = (pq-ntuples ?*outliving*))
(expect "reading one is refused" FALSE ?*read-cleared*)

(defglobal ?*status-cleared* = (pq-result-status ?*outliving*))
(expect "so is asking its status" FALSE ?*status-cleared*)

(defglobal ?*map-cleared* = (pq-row-to-multifield ?*outliving* 0))
(expect "and so is mapping a row out of it" FALSE ?*map-cleared*)

; ----------------------------------------------------------------------
; A finished connection
; ----------------------------------------------------------------------

(defglobal ?*use-finished* = (pq-exec ?*hconn* "SELECT 1"))
(expect "running a command on a finished connection is refused"
        FALSE ?*use-finished*)

(defglobal ?*reset-finished* = (pq-reset ?*hconn*))
(expect "and so is resetting it" FALSE ?*reset-finished*)

(defglobal ?*conninfo-finished* = (pq-conninfo ?*hconn*))
(expect "and reading what it was made from" FALSE ?*conninfo-finished*)

; ----------------------------------------------------------------------
; Results are independent of each other
; ----------------------------------------------------------------------

(defglobal ?*conn2* = (connect))
(defglobal ?*first* = (pq-exec ?*conn2* "SELECT 'first' AS which"))
(defglobal ?*second* = (pq-exec ?*conn2* "SELECT 'second' AS which"))

(expect "two results can be open at once" "first" (pq-getvalue ?*first* 0 0))
(expect "and each is its own" "second" (pq-getvalue ?*second* 0 0))

(pq-clear ?*first*)
(expect "clearing one leaves the other alone" "second" (pq-getvalue ?*second* 0 0))
(pq-clear ?*second*)

; ----------------------------------------------------------------------
; A result taken before a reset survives it
; ----------------------------------------------------------------------

(defglobal ?*before-reset* = (pq-exec ?*conn2* "SELECT 'before' AS which"))
(pq-reset ?*conn2*)
(expect "a result taken before a reset is still readable after it"
        "before" (pq-getvalue ?*before-reset* 0 0))
(pq-clear ?*before-reset*)

(expect "and the connection works again" "1" (scalar ?*conn2* "SELECT 1"))

(pq-finish ?*conn2*)

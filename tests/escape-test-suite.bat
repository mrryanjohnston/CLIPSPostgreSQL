; ======================================================================
; Escaping.
;
; Every one of these needs the connection, not just the string: what has to
; be escaped depends on the server's standard_conforming_strings setting and
; on the client encoding, and only the connection knows those.
; ======================================================================

(println crlf "escape-test-suite")

(defglobal ?*sconn* = (connect))

; ----------------------------------------------------------------------
; Literals, which come back with their quotes already on
; ----------------------------------------------------------------------

(expect "a quote in a literal is doubled, and the whole thing quoted"
        "'O''Brien'" (pq-escape-literal ?*sconn* "O'Brien"))
(expect "an ordinary string just gets its quotes"
        "'plain'" (pq-escape-literal ?*sconn* "plain"))
(expect "and the empty string is still a literal"
        "''" (pq-escape-literal ?*sconn* ""))

; The point of all this: the escaped literal goes into a command as it
; stands and comes back out as the value that went in.
(expect "an escaped literal survives the round trip through the server"
        "O'Brien"
        (scalar ?*sconn* (str-cat "SELECT " (pq-escape-literal ?*sconn* "O'Brien"))))

; ----------------------------------------------------------------------
; Identifiers, which are quoted differently from values
; ----------------------------------------------------------------------

(expect "an identifier is double-quoted"
        "\"weird column\"" (pq-escape-identifier ?*sconn* "weird column"))
(expect "and a double quote inside one is doubled"
        "\"say \"\"hello\"\"\"" (pq-escape-identifier ?*sconn* "say \"hello\""))

(run-sql ?*sconn* (str-cat "CREATE TEMP TABLE quoted ("
                           (pq-escape-identifier ?*sconn* "weird column") " int)"))
(expect "an escaped identifier names a real column"
        "weird column"
        (scalar ?*sconn* "SELECT attname FROM pg_attribute
                          WHERE attrelid = 'quoted'::regclass AND attnum > 0"))

; ----------------------------------------------------------------------
; The older string escaping, which leaves the quotes to the caller
; ----------------------------------------------------------------------

(expect "pq-escape-string-conn escapes without quoting"
        "O''Brien" (pq-escape-string-conn ?*sconn* "O'Brien"))

; ----------------------------------------------------------------------
; Binary data
;
; A bytea crosses as a multifield of byte values, so that a zero byte in the
; middle is a field like any other rather than the end of a string.
; ----------------------------------------------------------------------

(defglobal ?*bytes* = (create$ 0 1 39 92 127 255 65))
(defglobal ?*escaped-bytes* = (pq-escape-bytea-conn ?*sconn* ?*bytes*))

(expect-true "pq-escape-bytea-conn produces text" (stringp ?*escaped-bytes*))
(expect "which pq-unescape-bytea reads back as the same bytes"
        ?*bytes* (pq-unescape-bytea ?*escaped-bytes*))

; Unlike pq-escape-literal, this escapes the contents without quoting them,
; so the quotes around it are the caller's to add.
(expect "and which the server reads as the same bytes too"
        "7" (scalar ?*sconn*
              (str-cat "SELECT length('" ?*escaped-bytes* "'::bytea)")))

; The server prints a bytea in the hex format, which is the other direction
; through the same pair of functions.
(expect "a bytea from the server unescapes to its bytes"
        (create$ 222 173 190 239)
        (pq-unescape-bytea (scalar ?*sconn* "SELECT '\\xdeadbeef'::bytea")))

; A string is accepted where the bytes are text, which is the common case.
(expect "text can be escaped as a bytea too"
        (create$ 104 105) (pq-unescape-bytea (pq-escape-bytea-conn ?*sconn* "hi")))

(defglobal ?*not-bytes* = (pq-escape-bytea-conn ?*sconn* (create$ 1 999)))
(expect "a multifield field that is not a byte value is refused"
        FALSE ?*not-bytes*)

; Text with no escape sequences in it is its own bytes, which is what the
; escape format means: only the sequences are special.
(expect "text with nothing escaped in it unescapes to itself"
        (create$ 104 105) (pq-unescape-bytea "hi"))

; The hex format stops at the first pair that is not hex, which for a string
; that was never a bytea means nothing comes back at all.
(defglobal ?*not-bytea* = (pq-unescape-bytea "\\xZZ"))
(expect "text in the hex format that is not hex unescapes to no bytes"
        0 (length$ ?*not-bytea*))

; ----------------------------------------------------------------------
; Text the connection's encoding cannot read
;
; What has to be escaped depends on the client encoding, and a byte
; sequence that is not a character in it cannot be escaped at all. The one
; byte here is a whole character in LATIN1, which is how it is fetched, and
; half of one in UTF8, which is how it is then escaped.
; ----------------------------------------------------------------------

(pq-set-client-encoding ?*sconn* "LATIN1")
(defglobal ?*half-a-character* = (scalar ?*sconn* "SELECT chr(195)"))
(pq-set-client-encoding ?*sconn* "UTF8")
(expect "one LATIN1 character is one byte" 1 (str-length ?*half-a-character*))

(defglobal ?*unreadable* = (pq-escape-literal ?*sconn* ?*half-a-character*))
(expect "pq-escape-literal refuses text that is not valid in the client encoding"
        FALSE ?*unreadable*)

(bind ?*unreadable* (pq-escape-identifier ?*sconn* ?*half-a-character*))
(expect "so does pq-escape-identifier" FALSE ?*unreadable*)

(bind ?*unreadable* (pq-escape-string-conn ?*sconn* ?*half-a-character*))
(expect "and pq-escape-string-conn" FALSE ?*unreadable*)

(expect "and the connection is none the worse for it"
        "1" (scalar ?*sconn* "SELECT 1"))

(pq-finish ?*sconn*)

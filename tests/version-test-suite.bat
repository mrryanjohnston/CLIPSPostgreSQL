; ======================================================================
; What the library is, before anything is connected to.
; ======================================================================

(println crlf "version-test-suite")

; PQlibVersion is the version of the libpq this binary is linked against,
; spelled the way PostgreSQL numbers itself since 10: 180006 is 18.6. The
; binding needs 14 or later, and says so at compile time, so anything less
; here means the build found a different library than it was compiled for.
(expect-true "pq-lib-version is PostgreSQL 14 or later"
             (>= (pq-lib-version) 140000))

(expect "pq-lib-version has no arguments to refuse"
        (pq-lib-version) (pq-lib-version))

; pq-built-version is the libpq the wrappers were compiled against, which is
; what decides which of them exist. It is usually the same library that is
; loaded, and need not be: a binding built against 17 runs with an 18
; library under it, having bound the 17 set.
(expect-true "pq-built-version is PostgreSQL 14 or later"
             (>= (pq-built-version) 140000))
(expect-true "and no newer than the library actually loaded"
             (<= (div (pq-built-version) 10000) (div (pq-lib-version) 10000)))

; A thread-unsafe libpq is a build that went out of its way to be one; the
; assertion is that the question is answered, not that the answer is TRUE.
(defglobal ?*threadsafe* = (pq-isthreadsafe))
(expect-true "pq-isthreadsafe answers with a boolean"
             (or (eq ?*threadsafe* TRUE) (eq ?*threadsafe* FALSE)))

; pq-get-current-time-usec is tested in tests/pg17-test-suite.bat: it
; arrived in PostgreSQL 17, alongside pq-socket-poll, which is what it is
; for.

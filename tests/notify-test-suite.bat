; ======================================================================
; LISTEN and NOTIFY.
;
; A notification is the one thing the server sends that no command asked
; for. It arrives with whatever else is being read, which is why pq-notifies
; is a question asked after pq-consume-input rather than a call that waits.
; ======================================================================

(println crlf "notify-test-suite")

(defglobal ?*listener* = (connect))
(defglobal ?*notifier* = (connect))

(run-sql ?*listener* "LISTEN widgets_changed")

(expect "nothing has been sent, so there is nothing waiting"
        FALSE (pq-notifies ?*listener*))

; ----------------------------------------------------------------------
; A notification from another session
; ----------------------------------------------------------------------

(run-sql ?*notifier* "NOTIFY widgets_changed, 'bolt'")

; The notification arrives when the connection is read from, so the loop
; reads and asks until one is there. wait-for-input waits on the socket
; where this libpq can and asks for input where it cannot, which is why the
; loop counts attempts rather than watching a clock: there is no clock to
; watch before PostgreSQL 17.
(deffunction wait-for-notify (?conn ?attempts)
  (bind ?notification (pq-notifies ?conn))
  (while (and (not ?notification) (> ?attempts 0))
    (bind ?attempts (- ?attempts 1))
    (wait-for-input ?conn)
    (bind ?notification (pq-notifies ?conn)))
  ?notification)

(defglobal ?*notification* = (wait-for-notify ?*listener* 500))

(expect-true "the notification arrives" (neq FALSE ?*notification*))
(expect "it names the channel" widgets_changed (nth$ 1 ?*notification*))
(expect-true "the process that sent it"
             (eq (nth$ 2 ?*notification*) (pq-backend-pid ?*notifier*)))
(expect "and carries the payload" "bolt" (nth$ 3 ?*notification*))

(expect "and once taken it is gone" FALSE (pq-notifies ?*listener*))

; ----------------------------------------------------------------------
; A notification with no payload, which is the older form
; ----------------------------------------------------------------------

(run-sql ?*notifier* "NOTIFY widgets_changed")

(defglobal ?*bare* = (wait-for-notify ?*listener* 500))
(expect "a notification with no payload still arrives"
        widgets_changed (nth$ 1 ?*bare*))
(expect "with an empty one" "" (nth$ 3 ?*bare*))

; ----------------------------------------------------------------------
; A channel nobody is listening to
; ----------------------------------------------------------------------

(run-sql ?*notifier* "NOTIFY some_other_channel, 'ignored'")
(pq-consume-input ?*listener*)
(expect "a notification on a channel this connection did not LISTEN to never arrives"
        FALSE (pq-notifies ?*listener*))

(run-sql ?*listener* "UNLISTEN widgets_changed")
(run-sql ?*notifier* "NOTIFY widgets_changed, 'too late'")
(pq-consume-input ?*listener*)
(expect "nor does one sent after UNLISTEN" FALSE (pq-notifies ?*listener*))

(pq-finish ?*notifier*)
(pq-finish ?*listener*)

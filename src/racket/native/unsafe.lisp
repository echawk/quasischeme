; -*- Mode: Lisp; Syntax: Common-Lisp; Package: QUASISCHEME-RACKET -*-

;;;; The rest of #%unsafe and #%flfxnum, as Racket CS's (rumble/unsafe.ss,
;;;; rumble/place.ss, thread/os-thread.rkt, thread/unsafe.rkt,
;;;; io/unsafe/port.rkt and io/unsafe/schedule.rkt): the typed
;;;; vectors of ffi/vector, OS threads and semaphores, file descriptors
;;;; and sockets as ports, and the poller's wakeups.

(in-package "QUASISCHEME-RACKET")

(defun alias-native (name old &optional (instance "#%unsafe"))
  "Make NAME, in INSTANCE, the native procedure OLD is."
  (let ((n (or (gethash old *natives*) (error "no native ~A" old))))
    (setf (gethash name *natives*)
	  (make-native name (native-function n) :instance instance :leaf (native-leaf n)))))

(loop for (name old) in '(("unsafe-stencil-vector" "stencil-vector")
			  ("unsafe-stencil-vector-length" "stencil-vector-length")
			  ("unsafe-stencil-vector-mask" "stencil-vector-mask")
			  ("unsafe-stencil-vector-ref" "stencil-vector-ref")
			  ("unsafe-stencil-vector-set!" "stencil-vector-set!")
			  ("unsafe-stencil-vector-update" "stencil-vector-update")
			  ("unsafe-flreal-part" "flreal-part") ("unsafe-flimag-part" "flimag-part")
			  ("unsafe-make-flrectangular" "make-flrectangular")
			  ("unsafe-flsingle" "flsingle")
			  ;; the scheduler's: no dynamic-wind posts, no break check, here the same
			  ("unsafe-abort-current-continuation/no-wind" "abort-current-continuation")
			  ("unsafe-call-with-composable-continuation/no-wind" "call-with-composable-continuation"))
      do (alias-native name old))

(defnative "unsafe-flrandom" (g) (:instance "#%unsafe" :leaf t)
  (let ((*random-state* (prng-state g))) (random 1d0)))

;;; #%flfxnum: flbit-field checked; shared vectors are the plain ones,
;;; since places share one heap
(defnative "flbit-field" (x start end) (:instance "#%flfxnum" :leaf t)
  (unless (typep x 'double-float) (arg-error "flbit-field" "flonum?" x))
  (unless (typep start '(integer 0 64)) (arg-error "flbit-field" "(integer-in 0 64)" start))
  (unless (and (integerp end) (<= start end 64))
    (arg-error "flbit-field" "(integer-in start 64)" end))
  (funcall (native-function (gethash "unsafe-flbit-field" *natives*)) x start end))
(loop for (name old) in '(("shared-flvector" "flvector") ("make-shared-flvector" "make-flvector")
			  ("shared-fxvector" "fxvector") ("make-shared-fxvector" "make-fxvector"))
      do (alias-native name old "#%flfxnum"))

;;; ffi/vector's typed vectors: a struct whose first field is the cpointer
(macrolet ((def (kind rep size)
	     `(progn
		(defnative ,(format nil "unsafe-~Avector-ref" kind) (v k) (:instance "#%unsafe" :leaf t)
		  (read-rep ,rep (struct-field v 0) (* k ,size)))
		(defnative ,(format nil "unsafe-~Avector-set!" kind) (v k x) (:instance "#%unsafe" :leaf t)
		  (write-rep ,rep (struct-field v 0) (* k ,size) x)
		  *void*))))
  (def "s16" :integer-16 2) (def "u16" :unsigned-16 2)
  (def "f64" :double 8) (def "f80" :double 8))	; f80 as double, as Racket CS's

;;; Place-specific table
(defvar *place-specific-table* (make-place-local qs:false))
(defnative "unsafe-get-place-table" () (:instance "#%unsafe" :leaf t)
  (let ((ref (native-function (gethash "unsafe-place-local-ref" *natives*))))
    (with-atomic
      (let ((ht (funcall ref *place-specific-table*)))
	(if (truthy ht)
	    ht
	    (let ((ht (make-rhash :eq)))
	      (funcall (native-function (gethash "unsafe-place-local-set!" *natives*))
		       *place-specific-table* ht)
	      ht))))))

;;; Structs that refuse unsafe-undefined fields: no chaperone here, so V
(defvar *prop-chaperone-unsafe-undefined*
  (%make-struct-type-property (rsym "prop:chaperone-unsafe-undefined") nil '()))
(define-primitive "#%unsafe" "prop:chaperone-unsafe-undefined" *prop-chaperone-unsafe-undefined*)
(defnative "chaperone-struct-unsafe-undefined" (v) (:instance "#%unsafe" :leaf t) v)

;;; ------------------------------------------------------------------
;;; OS threads and semaphores (thread/os-thread.rkt)

(defnative "unsafe-os-thread-enabled?" () (:instance "#%unsafe" :leaf t) qs:true)

(defnative "unsafe-call-in-os-thread" (proc) (:instance "#%unsafe" :leaf t)
  (unless (functionp proc) (arg-error "unsafe-call-in-os-thread" "(procedure-arity-includes/c 0)" proc))
  ;; not a Racket thread: no current thread, as upstream's
  (let ((place *rplace*))
    (sb-thread:make-thread (lambda () (let ((*rplace* place)) (funcall proc)))
			   :name "os-thread"))
  *void*)

(defstruct (os-semaphore (:constructor make-os-semaphore ()))
  (count 0) (mutex (sb-thread:make-mutex)) (cv (sb-thread:make-waitqueue)))

(defnative "unsafe-make-os-semaphore" () (:instance "#%unsafe" :leaf t) (make-os-semaphore))
(defnative "unsafe-os-semaphore-post" (s) (:instance "#%unsafe" :leaf t)
  (unless (os-semaphore-p s) (arg-error "unsafe-os-semaphore-post" "os-semaphore?" s))
  (sb-thread:with-mutex ((os-semaphore-mutex s))
    (incf (os-semaphore-count s))
    (sb-thread:condition-notify (os-semaphore-cv s)))
  *void*)
(defnative "unsafe-os-semaphore-wait" (s) (:instance "#%unsafe" :leaf t)
  (unless (os-semaphore-p s) (arg-error "unsafe-os-semaphore-wait" "os-semaphore?" s))
  (sb-thread:with-mutex ((os-semaphore-mutex s))
    (loop while (zerop (os-semaphore-count s))
	  do (sb-thread:condition-wait (os-semaphore-cv s) (os-semaphore-mutex s)))
    (decf (os-semaphore-count s)))
  *void*)

;;; ------------------------------------------------------------------
;;; File descriptors and sockets (io/unsafe/port.rkt)

(defnative "unsafe-file-descriptor->port" (fd name mode) (:instance "#%unsafe" :leaf t)
  (declare (ignore name))
  (unless (integerp fd) (arg-error "unsafe-file-descriptor->port" "exact-integer?" fd))
  (let* ((read? (member "read" mode :test #'symbol-named-p*))
	 (write? (member "write" mode :test #'symbol-named-p*))
	 ;; both ends: each its own descriptor, so closing one leaves the other
	 (i (and read? (fd-port (if write? (sb-posix:dup fd) fd) :input)))
	 (o (and write? (fd-port fd :output))))
    (if (and i o) (values i o) (or i o))))

(defun symbol-named-p* (name x) (symbol-named-p x name))

(defun port-fd (p)
  "The descriptor of port P, or NIL."
  (setq p (unwrap-out (unwrap-in p)))
  (cond ((and (routport-p p) (eq (routport-kind p) :file)) (file-stream-fd p))
	((gethash p *tcp-ports*) (tcp-conn-fd (gethash p *tcp-ports*)))
	((and (streamp p) (host-fd-stream p)) (sb-sys:fd-stream-fd (host-fd-stream p)))))

(defnative "unsafe-port->file-descriptor" (p) (:instance "#%unsafe" :leaf t)
  (or (port-fd p) qs:false))
(defnative "unsafe-port->socket" (p) (:instance "#%unsafe" :leaf t)
  (let ((conn (gethash (unwrap-out (unwrap-in p)) *tcp-ports*)))
    (or (and conn (tcp-conn-fd conn)) qs:false)))
(defnative "unsafe-socket->port" (fd name mode) (:instance "#%unsafe" :leaf t)
  (declare (ignore mode))
  (unless (integerp fd) (arg-error "unsafe-socket->port" "exact-integer?" fd))
  (open-tcp-ports fd (rsym (map 'string #'code-char name))))

(defun fd-mode-events (mode)
  (flet ((is (&rest names) (some (lambda (n) (symbol-named-p mode n)) names)))
    (cond ((is "read" "check-read") 1)
	  ((is "write" "check-write") 4))))

(defnative "unsafe-poll-fd" (fd mode &optional socket?) (:instance "#%unsafe" :leaf t)
  (declare (ignore socket?))
  (let ((events (fd-mode-events mode)))
    (bool (and events (net-ready-p fd events)))))

(defun fd-semaphore (fd mode)
  "A semaphore posted once FD is ready for MODE: a host thread waits for
it, as rktio's long-term poll set does for the scheduler."
  (let ((events (fd-mode-events mode)))
    (if (null events)
	qs:false
	(let ((s (make-rsemaphore 0)))
	  (sb-thread:make-thread
	   (lambda ()
	     (loop until (ignore-errors (net-ready-p fd events 1000)))
	     (loop for old = (rsemaphore-count s)
		   until (eql (sb-ext:compare-and-swap (rsemaphore-count s) old (1+ old)) old)))
	   :name "fd-semaphore")
	  s))))

(defnative "unsafe-file-descriptor->semaphore" (fd mode) (:instance "#%unsafe" :leaf t)
  (fd-semaphore fd mode))
(defnative "unsafe-socket->semaphore" (fd mode) (:instance "#%unsafe" :leaf t)
  (fd-semaphore fd mode))

;;; ------------------------------------------------------------------
;;; The poller's wakeups, signals, sleeping (io/unsafe/schedule.rkt):
;;; the scheduler polls instead, so there's nothing to register

(defnative "unsafe-poll-ctx-fd-wakeup" (ctx fd mode) (:instance "#%unsafe" :leaf t)
  (declare (ignore ctx fd mode)) *void*)
(defnative "unsafe-poll-ctx-eventmask-wakeup" (ctx mask) (:instance "#%unsafe" :leaf t)
  (declare (ignore ctx mask)) *void*)
(defnative "unsafe-poll-ctx-milliseconds-wakeup" (ctx msecs) (:instance "#%unsafe" :leaf t)
  (declare (ignore ctx msecs)) *void*)
(defnative "unsafe-signal-received" () (:instance "#%unsafe" :leaf t) *void*)
(defnative "unsafe-make-signal-received" () (:instance "#%unsafe" :leaf t)
  (lambda () *void*))
(defnative "unsafe-set-sleep-in-thread!" (do-sleep woke-fd) (:instance "#%unsafe" :leaf t)
  (declare (ignore do-sleep woke-fd)) *void*)

(defvar *atomic-timeout-callback* qs:false)
(defnative "unsafe-set-on-atomic-timeout!" (proc) (:instance "#%unsafe" :leaf t)
  ;; the previous callback, as thread/atomic.rkt's; atomic regions aren't timed here
  (shiftf *atomic-timeout-callback* proc))

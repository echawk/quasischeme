; -*- Mode: Lisp; Syntax: Common-Lisp; Package: QUASISCHEME-RACKET -*-

;;;; Control, natively: continuation marks, prompts with tags, raise and
;;;; exception handlers, parameters and parameterizations (#%paramz).
;;;;
;;;; Marks are the Chez mode's (src/chez/host.lisp): a mark belongs to a
;;;; frame, and one set in tail position replaces its frame's mark of the
;;;; same key; with-continuation-mark compiles to CALL-WITH-MARK.
;;;; Prompts are the host's (src/continuations.lisp), whose handler gets
;;;; the composable continuation and the values; Racket's gets the
;;;; values.
;;;;
;;;; Exceptions, as in Racket CS's rumble: raise calls the handler that
;;;; the innermost exception-handler-key mark holds, with the marks
;;;; outside that one current, so that a raise inside it goes to the
;;;; next handler out.  With none, the uncaught-exception handler runs.
;;;; Not yet: marks delimited by a prompt tag, composable continuations
;;;; (call-with-composable-continuation), barriers, breaks.

(in-package "QUASISCHEME-RACKET")

;;; ------------------------------------------------------------------
;;; Places (threads.lisp): each one's own state, as Racket CS's place
;;; registers.  The place an SBCL thread runs in is *RPLACE*, which each
;;; new thread inherits (*THREAD-SPECIALS*); the variables that name its
;;; parts are symbol macros, so that a SETQ of one sets the place's.

(defstruct (rplace (:constructor make-rplace (parent)) (:copier nil))
  parent
  (lock (sb-thread:make-mutex :name "racket place"))
  (cv (sb-thread:make-waitqueue))
  ;; the scheduler and its roots (threads.lisp)
  sched-lock holder (threads '()) (thread-ids 0) ticker parallel-active atomic-lock
  scheduler-started main-thread root-custodian root-thread-group
  root-parameterization
  (parameter-cells nil)			; parameter data -> cell, in a place but the first
  (locals nil)				; place-local -> value, in a place but the first
  rktio rktio-std-fds (saved-errno 0)	; rktio.lisp, foreign.lisp
  (object nil))				; the place as a Racket value, for place-channel-get

(defvar *initial-rplace* (make-rplace nil))
(defvar *rplace* *initial-rplace* "The place this SBCL thread runs in.")

(defmacro define-place-variable (name accessor)
  `(define-symbol-macro ,name (,accessor *rplace*)))

(define-place-variable *root-parameterization* rplace-root-parameterization)


;;; ------------------------------------------------------------------
;;; Continuation marks

(defvar *exception-handler-key* (make-symbol "exception-handler-key"))
(defvar *parameterization-key* (make-symbol "parameterization-key"))
(defvar *break-enabled-key* (make-symbol "break-enabled-key"))

(define-primitive "#%paramz" "exception-handler-key" *exception-handler-key*)
(define-primitive "#%paramz" "parameterization-key" *parameterization-key*)
(define-primitive "#%paramz" "break-enabled-key" *break-enabled-key*)

(defun current-marks () qs-r6rs::*marks*)

(defun marks-of (set)
  (if (eq set qs:false) (current-marks) (qs-r6rs::mark-set-marks set)))

(defun first-mark (key &optional (marks (current-marks)) (none qs:false))
  (let ((m (find key marks :key #'cadr :test #'eq)))
    (if m (cddr m) none)))

(defnative "current-continuation-marks" (&optional prompt-tag) (:rumble "current-continuation-marks" :leaf t)
  (declare (ignore prompt-tag))
  (qs-r6rs::make-mark-set (current-marks)))

(defnative "continuation-mark-set?" (x) (:leaf t) (bool (qs-r6rs::mark-set-p x)))

(defnative "continuation-mark-set-first" (marks key &optional (none qs:false) prompt-tag)
    (:rumble "continuation-mark-set-first" :leaf t)
  (declare (ignore prompt-tag))
  ;; a thread's continuation starts with the root parameterization marked
  (first-mark key (marks-of marks)
	      (if (eq key *parameterization-key*) *root-parameterization* none)))

(defnative "continuation-mark-set->list" (marks key &optional prompt-tag) (:leaf t)
  (declare (ignore prompt-tag))
  (loop for m in (marks-of marks) when (eq (cadr m) key) collect (cddr m)))

(defnative "call-with-immediate-continuation-mark" (key proc &optional (default qs:false)) ()
  (qs-r6rs::call-with-immediate-mark key proc default))

;;; ------------------------------------------------------------------
;;; Prompts

(defstruct (prompt-tag (:constructor make-prompt-tag (name))) name)

(defmethod print-object ((x prompt-tag) stream)
  (format stream "#<continuation-prompt-tag~@[:~A~]>" (and (prompt-tag-name x) (rname (prompt-tag-name x)))))

(defvar *default-prompt-tag* (make-prompt-tag (rsym "default")))

(defnative "default-continuation-prompt-tag" () (:leaf t) *default-prompt-tag*)
(defnative "make-continuation-prompt-tag" (&optional (name nil)) (:leaf t)
  (make-prompt-tag (and name (truthy name) name)))
(defnative "continuation-prompt-tag?" (x) (:leaf t) (bool (prompt-tag-p x)))
(defnative "continuation-prompt-available?" (tag &optional k) (:leaf t)
  (declare (ignore k))
  (bool (qsx::find-prompt tag)))

(defun default-prompt-handler (tag)
  (if (eq tag *default-prompt-tag*)
      ;; the default tag's: call the thunk aborted with, under the prompt again
      (lambda (thunk) (call-with-continuation-prompt thunk tag nil))
      #'values))

(defvar *prompt-marks* '()
  "(tag . marks) for each prompt the current continuation has, innermost
first: the continuation marks outside it (CAPTURE-COMPOSABLE-CONTINUATION
keeps those inside).")

(defun call-with-continuation-prompt (proc tag handler &rest args)
  (let ((handler (or handler (default-prompt-handler tag))))
    (qsx::call-with-prompt tag
			   (lambda ()
			     (let ((*prompt-marks* (acons tag (current-marks) *prompt-marks*)))
			       (apply proc args)))
			   (lambda (k &rest values)
			     (declare (ignore k))
			     (apply handler values)))))

(defnative "call-with-continuation-prompt" (proc &optional (tag *default-prompt-tag*) (handler qs:false) &rest args)
    (:rumble "call-with-continuation-prompt")
  (apply #'call-with-continuation-prompt proc tag (and (truthy handler) handler) args))

(defnative "abort-current-continuation" (tag &rest vals) (:rumble "abort-current-continuation")
  (unless (qsx::find-prompt tag)
    (racket-error "abort-current-continuation" "continuation includes no prompt with the given tag~%  tag: ~A" tag))
  (apply #'qsx::abort-to-prompt tag vals))

;;; ------------------------------------------------------------------
;;; Raise

(defvar *future* nil
  "The future (RFUTURE, threads.lisp) this thread is running, if any:
current-future's value.")
(defvar *future-detached* nil
  "True while a future runs on a worker of its own, not yet touched: a
future-unsafe operation (atomic mode, a port, the scheduler, raise) then
blocks it until it is (FUTURE-BLOCK), as Racket CS's futures block.")

(defvar *uncaught-exception-handler* nil
  "The uncaught-exception-handler parameter's root value (exn.lisp sets it).")

(defun do-raise (v &optional (barrier t))
  "raise: the innermost handler, in the marks outside its own."
  (declare (ignore barrier))
  (when *future-detached* (future-block))
  (let* ((marks (current-marks))
	 (entry (find *exception-handler-key* marks :key #'cadr :test #'eq)))
    (when (and (null entry) *future*)
      ;; a future's own handlers are passed: touch raises it, in the
      ;; toucher's continuation, as a future's continuation is spliced
      ;; onto the toucher's in Racket CS
      (throw 'future-raise (list :raise v)))
    (if entry
	(let ((handler (cddr entry)))
	  (let ((qs-r6rs::*marks* (cdr (member entry marks :test #'eq))))
	    (funcall handler v))
	  ;; a handler that returns, for raise
	  (let ((qs-r6rs::*marks* (cdr (member entry marks :test #'eq))))
	    (do-raise (make-exn "exn:fail:contract"
				(format nil "exception handler returned~%  exception: ~A~@[~%  message: ~A~]"
					(with-output-to-string (s) (funcall (qsx:host-ref "write") v s))
					(ignore-errors (let ((m (exn-message v))) (and (stringp m) m))))))))
	(funcall *uncaught-exception-handler* v))))

(defnative "raise" (v &optional (barrier? qs:true)) (:rumble "raise")
  (do-raise v (truthy barrier?)))

;;; ------------------------------------------------------------------
;;; Parameters
;;;
;;; A parameter is a procedure (a closure, which *PARAMETERS* maps to its
;;; data): its value is in a cell, the current parameterization's for it
;;; (the innermost parameterization-key mark), else the parameter's own.

(defstruct (parameter-data (:constructor make-parameter-data (cell guard name &aux (initial (car cell)))))
  cell guard name
  initial)				; its value when made: a new place's (PARAMETER-CELL)
(defstruct (parameterization (:constructor make-parameterization (cells))) cells) ; alist: data -> cell

(defvar *parameters* (make-hash-table :test 'eq :weakness :key :synchronized t))

(setq *root-parameterization* (make-parameterization '()))

(defun current-parameterization ()
  (first-mark *parameterization-key* (current-marks) *root-parameterization*))

(defun parameter-cell (data)
  (or (cdr (assoc data (parameterization-cells (current-parameterization)) :test #'eq))
      (let ((cells (rplace-parameter-cells *rplace*)))
	(if cells
	    ;; a place but the first: its own cell, which starts with the
	    ;; parameter's first value, as a new place's thread cells do
	    (or (gethash data cells)
		(setf (gethash data cells) (list (parameter-data-initial data))))
	    (parameter-data-cell data)))))

(defun make-parameter* (value &optional guard name)
  (let* ((data (make-parameter-data (list value) guard name))
	 (p (lambda (&optional (new nil new-p))
	      (if new-p
		  (progn (setf (car (parameter-cell data))
			       (if (parameter-data-guard data) (funcall (parameter-data-guard data) new) new))
			 *void*)
		  (car (parameter-cell data))))))
    (setf (gethash p *parameters*) data)
    p))

(defnative "make-parameter" (&optional (value qs:false) (guard qs:false) (name qs:false) realm) ()
  (declare (ignore realm))
  (make-parameter* value (and (truthy guard) guard) name))

(defun parameter-data-of (p)
  "P's parameter data: P's own, or what P chaperones' (procedures.lisp)."
  (loop for x = p then (impersonation-of i)
	for data = (gethash x *parameters*)
	for i = (and (not data) (impersonation x))
	when data return data
	while i))

(defnative "parameter?" (x) (:leaf t) (bool (parameter-data-of x)))
(defnative "parameterization?" (x) (:leaf t) (bool (parameterization-p x)))
(defnative "current-parameterization" () (:leaf t) (current-parameterization))

;;; The extension parameterization (#%paramz): PARAMZ with each parameter
;;; given a fresh cell holding its value (after its guard)
(defnative "extend-parameterization" (paramz &rest params-and-values)
    (:instance "#%paramz" :rumble "extend-parameterization")
  (let ((cells (parameterization-cells paramz)))
    (loop for (p v) on params-and-values by #'cddr
	  do (let ((data (or (parameter-data-of p)
			     (racket-error "parameterize" "contract violation~%  expected: parameter?~%  given: ~S" p))))
	       (push (cons data (list (if (parameter-data-guard data) (funcall (parameter-data-guard data) v) v)))
		     cells)))
    (make-parameterization cells)))

(defnative "call-with-parameterization" (paramz thunk) ()
  (qs-r6rs::call-with-mark *parameterization-key* paramz thunk))

;;; The port parameters.  Until a program sets or parameterizes one,
;;; its value is the host's (*standard-output* and so on).  Our natives
;;; that take an optional port ask them (CURRENT-PORT); the host's own
;;; procedures don't.

(defun make-port-parameter (variable name predicate)
  "The parameter NAME, over the host variable VARIABLE; it holds only
ports (PREDICATE, the name of the native that says which values are)."
  (let* ((check (lambda (v)
		  (unless (truthy (funcall (native-function (gethash predicate *natives*)) v))
		    (contract-error name predicate v))
		  v))
	 (data (make-parameter-data (list nil) check (rsym name)))
	 (p (lambda (&optional (new nil new-p))
	      (if new-p
		  (progn (setf (car (parameter-cell data)) (funcall check new)) *void*)
		  (or (car (parameter-cell data)) (symbol-value variable))))))
    (setf (gethash p *parameters*) data)
    (define-primitive "#%kernel" name p)
    p))

(defvar *current-output-port* (make-port-parameter '*standard-output* "current-output-port" "output-port?"))
(defvar *current-input-port* (make-port-parameter '*standard-input* "current-input-port" "input-port?"))
(defvar *current-error-port* (make-port-parameter '*error-output* "current-error-port" "output-port?"))

(defun current-port (which)
  "The current :OUTPUT, :INPUT or :ERROR port (the port itself, if the
parameter holds a struct with prop:output-port or prop:input-port)."
  (let ((p (funcall (ecase which
		      (:output *current-output-port*)
		      (:input *current-input-port*)
		      (:error *current-error-port*)))))
    (if (eq which :input) (unwrap-in p) (unwrap-out p))))

;;; ------------------------------------------------------------------
;;; Thread cells.  The cell holds its initial value (and whether it's
;;; preserved: copied to new threads); each thread's own values, once it
;;; sets them, are the thread layer's (threads.lisp).

(defstruct (thread-cell (:constructor make-thread-cell* (value preserved))) value preserved)

(defnative "call-with-continuation-barrier" (thunk) () (funcall thunk))
(defnative "call-with-escape-continuation" (proc) ()
  (funcall (qsx:host-ref "call-with-current-continuation") proc))
(defnative "unsafe-root-continuation-prompt-tag" () (:instance "#%unsafe" :leaf t) *default-prompt-tag*)
(defnative "reparameterize" (paramz) (:instance "#%paramz" :leaf t) paramz)

;;; ------------------------------------------------------------------
;;; The thread layer's structures (threads.lisp has the rest): semaphores
;;; (a count, and a queue of the waits that wait for it), and threads

(defstruct (rsemaphore (:constructor make-rsemaphore (count))) (count 0) (waiters '()))

(defstruct (rthread (:constructor make-rthread (name)))
  name
  (id 0)
  (lisp nil)				; its SBCL thread
  (state :runnable)			; :running :runnable :blocked :done
  (cv (sb-thread:make-waitqueue))	; where it waits for the baton
  (wait nil)				; what it waits for, while blocked
  (cells nil)				; its values of thread cells
  (mailbox '())
  (dead nil)
  (zombie nil)				; killed, and still to unwind
  (suspended nil)
  (suspend-to-kill nil)
  (custodians '())			; the records that custodians manage it by
  (group nil)
  (pending-break nil)			; NIL, :break, :hang-up or :terminate
  (atomic 0)				; depth of atomic sections: no preemption
  (preempt-queued nil))

(define-place-variable *main-thread* rplace-main-thread)
(setq *main-thread* (make-rthread (rsym "main")))
(defvar *self* *main-thread*
  "The Racket thread the current SBCL thread runs (bound in each new one).")

(defstruct (plumber (:constructor make-plumber* ())) (flushes '()))
(defvar *current-plumber* (make-parameter* (make-plumber*)))
(define-primitive "#%kernel" "current-plumber" *current-plumber*)
(defnative "make-plumber" () (:leaf t) (make-plumber*))
;; plumber?, flush handles and plumber-flush-all: threads.lisp

(defstruct (logger (:constructor make-logger* (name parent))) name parent)
(defvar *current-logger* (make-parameter* (make-logger* qs:false nil)))
(define-primitive "#%kernel" "current-logger" *current-logger*)
(defnative "make-logger" (&optional (name qs:false) parent &rest more) (:leaf t)
  (declare (ignore more))
  (make-logger* name (and parent (truthy parent) parent)))
(defnative "logger?" (x) (:leaf t) (bool (logger-p x)))
(defnative "logger-name" (l) (:leaf t) (logger-name l))
;; no log receivers yet: nothing is ever logged
(defnative "log-level?" (l level &optional topic) (:leaf t) (declare (ignore l level topic)) qs:false)
(defnative "log-max-level" (l &optional topic) (:leaf t) (declare (ignore l topic)) qs:false)
(defnative "log-message" (l level &rest more) (:leaf t) (declare (ignore l level more)) *void*)

;;; Events (threads.lisp has sync and the combinators): a REVT is a
;;; primitive event of a KIND, with a TARGET; the kinds are polled
;;; (:always :never :peek :thunk :log-receiver :poll) or made by the
;;; thread layer (:put :alarm :dead :suspend :resume :receive :idle :choice
;;; :wrap :replace :guard :nack-guard :poll-guard).
(defstruct (revt (:constructor make-revt (kind &optional target))) kind target)
(defvar *always-evt* (make-revt :always))
(defvar *never-evt* (make-revt :never))
(define-primitive "#%kernel" "always-evt" *always-evt*)
(define-primitive "#%kernel" "never-evt" *never-evt*)

;;; Continuation mark keys: any value is a key; these are unique ones
(defstruct (mark-key (:constructor make-mark-key (name))) name)
(defnative "make-continuation-mark-key" (&optional (name nil)) (:leaf t) (make-mark-key name))
(defnative "continuation-mark-key?" (x) (:leaf t) (bool (mark-key-p x)))
(defnative "continuation-mark-set->list*" (marks keys &optional (none qs:false) prompt-tag) (:leaf t)
  (declare (ignore prompt-tag))
  ;; per frame with any of KEYS: a vector of their values (NONE if absent)
  (let ((keys (coerce keys 'list)))
    (loop for (nil . entries) in (qs-r6rs::mark-frames (marks-of marks))
	  when (some (lambda (k) (assoc k entries :test #'eq)) keys)
	    collect (coerce (mapcar (lambda (k) (let ((e (assoc k entries :test #'eq))) (if e (cdr e) none))) keys)
			    'simple-vector))))

; -*- Mode: Lisp; Syntax: Common-Lisp; Package: SB-VM -*-

;;;; Faster code from SBCL for what the translator emits: the optional
;;;; layer of docs/optimizations.md ("VOPs"), loaded by bin/quasischeme's
;;;; build (system quasischeme/fast) after everything else, so that it
;;;; changes only the code compiled at run time -- programs, libraries,
;;;; --racket's linklets -- never the runtime's own or a bootstrap's.
;;;; QUASISCHEME_FAST=0 turns it off for a process.  Code compiled with
;;;; and without it is as correct, and goes together.
;;;;
;;;; For SBCL 2.6.9 on arm64 (sbcl/sbcl at tag sbcl-2.6.9), whose
;;;; internals it uses; elsewhere it does nothing.
;;;;
;;;; A small stack vector, inline.  A frame (src/continuations.lisp,
;;;; %SITE) is (vector ...) declared DYNAMIC-EXTENT, which SBCL compiles
;;;; on arm64 to a call of the assembly routine ALLOCATE-VECTOR-ON-STACK
;;;; (src/assembly/arm64/array.lisp), whatever the length; with a
;;;; constant length of at most 60 words (in one page, so the guard page
;;;; catches an overflow, as MAKE-VECTOR-CHECK-OVERFLOW-P reasons) it is
;;;; the same instructions inline: the stack pointer bumped, the header
;;;; and length stored and the elements zeroed (as the routine does,
;;;; before they are stored), without the call or the loop.  Lattice in
;;;; Racket mode spent an eighth of its time in the routine.

(in-package #+sbcl "SB-VM" #-sbcl "CL-USER")

#+(and sbcl arm64)
(eval-when (:compile-toplevel :load-toplevel :execute)
  (when (string= (lisp-implementation-version) "2.6.9")
    (pushnew :quasischeme-sbcl-vops *features*)))

(defvar cl-user::*quasischeme-fast* :unknown
  "Whether this layer is on: QUASISCHEME_FAST=0 turns it off.  Read once
per process.")

#+sbcl (pushnew (lambda () (setq cl-user::*quasischeme-fast* :unknown)) sb-ext:*init-hooks*)

(defun quasischeme-fast-p ()
  (when (eq cl-user::*quasischeme-fast* :unknown)
    (setq cl-user::*quasischeme-fast* (not (equal (uiop:getenv "QUASISCHEME_FAST") "0"))))
  cl-user::*quasischeme-fast*)

#+quasischeme-sbcl-vops
(progn
  (sb-ext:unlock-package "SB-VM")
  (sb-ext:unlock-package "SB-C")

  (defun qs-elements-stored-p (vop length)
    "Whether the VOPs after VOP, which makes a simple vector of LENGTH, in
its block store each of its elements, by a constant index, before
anything else uses it (but moves of it): (VECTOR A B ...)'s stores."
    (let ((tns (list (sb-c::tn-ref-tn (sb-c::vop-results vop))))
	  (stored (make-array length :element-type 'bit :initial-element 0)))
      (flet ((uses-p (v)
	       (loop for r = (sb-c::vop-args v) then (sb-c::tn-ref-across r)
		     while r thereis (member (sb-c::tn-ref-tn r) tns))))
	(do ((v (sb-c::vop-next vop) (sb-c::vop-next v)))
	    ((null v) nil)
	  (let* ((name (sb-c::vop-name v))
		 (args (sb-c::vop-args v))
		 (index (and args (sb-c::tn-ref-across args)
			     (sb-c::tn-ref-tn (sb-c::tn-ref-across args)))))
	    (cond ((and (eq name 'data-vector-set/simple-vector)
			(member (sb-c::tn-ref-tn args) tns)
			index (eq (sb-c::tn-kind index) :constant)
			(typep (sb-c::tn-value index) `(integer 0 (,length)))
			(not (member (sb-c::tn-ref-tn (sb-c::tn-ref-across (sb-c::tn-ref-across args))) tns)))
		   (setf (sbit stored (sb-c::tn-value index)) 1)
		   (when (every #'plusp stored) (return t)))
		  ((and (eq name 'move) (uses-p v))
		   (push (sb-c::tn-ref-tn (sb-c::vop-results v)) tns))
		  ((uses-p v) (return nil))))))))

  ;; A small vector of constant length on the stack.  Its words aren't
  ;; zeroed when the VOPs that follow store them all, as (VECTOR A B ...)'s
  ;; do (a capture site's frame): the control stack is scanned
  ;; conservatively, so a word not yet stored is no harm to the GC
  ;; (SBCL's own stack vectors are words on the stack before they are
  ;; zeroed, too)
  (define-vop (qs-allocate-small-vector-on-stack)
    (:info type length words)
    (:arg-types (:constant fixnum) (:constant fixnum) (:constant fixnum))
    (:results (result :scs (descriptor-reg)))
    (:temporary (:sc non-descriptor-reg) header)
    (:temporary (:sc any-reg) len)
    (:vop-var vop)
    (:generator 2
      (let ((bytes (logandc2 (+ (* (+ words vector-data-offset) n-word-bytes) lowtag-mask) lowtag-mask)))
	(allocation nil bytes other-pointer-lowtag result :stack-allocate-p t)
	(load-immediate-word header type)
	(load-immediate-word len (fixnumize length))
	(inst stp header len (@ tmp-tn))
	(unless (and (= type simple-vector-widetag) (= length words)
		     (qs-elements-stored-p vop length))
	  (loop for off from (* 2 n-word-bytes) below bytes by (* 2 n-word-bytes)
		do (inst stp zr-tn zr-tn (@ tmp-tn off)))))))

;; Capture sites whose frames are SBCL's own (src/continuations.lisp,
  ;; "Stack sites"): after a site's call, QS-SITE-MARK-n emits no code but
  ;; a branch over a block of data, which a capture finds from the call's
  ;; return address: a magic word, the site, the machine's parameter
  ;; count, how many values follow, and where each value is while the
  ;; call runs (QS-SITE-LOCATION: a slot of the machine's frame, a
  ;; constant of its code, or an immediate).
  ;; The values are the machine, its capture cache and the site's live
  ;; variables, copied to the stack before the call (QS-STACK-COPY-n).
  (defconstant +qs-site-magic+ #x5153534954454d4b)

  (defconstant +qs-site-mark-arity+ 20
    "The most values a site's mark can take: QS-SITE-MARK-n has n.  A site
with more keeps a portable frame (SBCL fails to pack QS-STACK-COPY-32).")

  (eval-when (:compile-toplevel :load-toplevel :execute)
    (defun qs-site-mark-name (n)
      (intern (format nil "QS-SITE-MARK-~D" n) "SB-VM"))
    nil)

  (defun qs-site-location (tn &optional (depth 0))
    "Where TN's value is while the call before the mark runs, as two
words, a kind and what it says: 4, a control-stack slot's byte offset
from the frame pointer; 0, an sc+offset (another stack slot, or the
slot its register is saved in); 1, the index of a constant in the code
object; 2, an immediate's tagged word; 3, nowhere known.  A copy made
after the call (a fixnum variable kept untagged, tagged for the mark) is
where its source is."
    (let* ((kind (sb-c::sb-kind (sb-c::sc-sb (sb-c::tn-sc tn))))
	   (loc (case kind
		  (:unbounded tn)
		  (:finite (sb-c::tn-save-tn tn)))))
      (cond ((and loc (= (sb-c::sc-number (sb-c::tn-sc loc)) control-stack-sc-number))
	     ;; 4: a control-stack slot, as its byte offset from the frame
	     ;; pointer (STACK-FRAME-VALUE's fast case, decoded here)
	     (values 4 (* n-word-bytes (sb-c::tn-offset loc))))
	    (loc
	     (values 0 (sb-c:make-sc+offset (sb-c::sc-number (sb-c::tn-sc loc)) (sb-c::tn-offset loc))))
	    ((sb-c::constant-p (sb-c::tn-leaf tn))
	     (let ((value (sb-c::constant-value (sb-c::tn-leaf tn))))
	       (cond ((typep value '(or fixnum character single-float))
		      (values 2 (sb-kernel:get-lisp-obj-address value)))
		     ((and (eq (sb-c::sc-name (sb-c::tn-sc tn)) 'constant) (sb-c::tn-offset tn))
		      (values 1 (sb-c::tn-offset tn)))
		     ((or (eq value nil) (eq value t))
		      (values 2 (sb-kernel:get-lisp-obj-address value)))
		     (t (values 3 0)))))
	    ((let* ((write (sb-c::tn-writes tn))
		    (vop (and write (null (sb-c::tn-ref-next write)) (sb-c::tn-ref-vop write)))
		    (info (and vop (sb-c::vop-info vop))))
	       (and (< depth 3) info
		    (let ((name (symbol-name (sb-c::vop-info-name info))))
		      (or (string= name "MOVE") (eql 0 (search "MOVE-" name))))
		    (sb-c::vop-args vop) (null (sb-c::tn-ref-across (sb-c::vop-args vop)))
		    (multiple-value-bind (k p) (qs-site-location (sb-c::tn-ref-tn (sb-c::vop-args vop)) (1+ depth))
		      (and (/= k 3) (return-from qs-site-location (values k p)))))))
	    (t (values 3 0)))))

  (defun qs-emit-site-mark (vop site nparams)
    (let ((over (gen-label))
	  (locs (loop for r = (sb-c::vop-args vop) then (sb-c::tn-ref-across r)
		      while r collect (multiple-value-list (qs-site-location (sb-c::tn-ref-tn r))))))
      (inst b over)
      (inst dword +qs-site-magic+)
      (inst dword site)
      (inst dword nparams)
      (inst dword (length locs))
      (loop for (kind payload) in locs
	    do (inst dword kind)
	       (inst dword (ldb (byte 64 0) payload)))
      (emit-label over)))

  ;; any SC, boxed or not, so that nothing is moved for the mark
  (macrolet ((def (n)
	       (let ((name (qs-site-mark-name n))
		     (args (loop for i below n collect (intern (format nil "A~D" i) "SB-VM"))))
		 `(progn
		    (eval-when (:compile-toplevel :load-toplevel :execute)
		      (sb-c:defknown ,name (fixnum fixnum ,@(make-list n :initial-element t)) (values) ()
			:overwrite-fndb-silently t))
		    (define-vop (,name)
		      (:translate ,name)
		      (:policy :fast-safe)
		      (:args ,@(loop for a in args
				     collect `(,a :load-if nil
						  :scs (any-reg descriptor-reg control-stack signed-reg unsigned-reg
							signed-stack unsigned-stack character-reg character-stack
							sap-reg sap-stack single-reg single-stack double-reg double-stack
							complex-single-reg complex-single-stack complex-double-reg
							complex-double-stack))))
		      (:arg-types (:constant fixnum) (:constant fixnum) ,@(make-list n :initial-element '*))
		      (:info site nparams)
		      (:ignore ,@args)
		      (:vop-var vop)
		      (:generator 0 (qs-emit-site-mark vop site nparams))))))
	     (defs ()
	       `(progn ,@(loop for n from 2 to +qs-site-mark-arity+ collect `(def ,n)))))
    (defs))

  ;; QS-STACK-COPY-n: its n arguments, copied to TNs of their own (its
  ;; results) before a site's call.  Whatever SBCL does with a value
  ;; across the call (keeps it in a register it doesn't save, as an
  ;; environment TN; reads it again from a closure or a value cell), the
  ;; mark after the call refers to the copies, which SBCL saves on the
  ;; stack across the call as it saves any value live across one.  A move
  ;; and a store a value.
  (macrolet ((def (n)
	       (let ((name (intern (format nil "QS-STACK-COPY-~D" n) "SB-VM"))
		     (args (loop for i below n collect (intern (format nil "A~D" i) "SB-VM")))
		     (results (loop for i below n collect (intern (format nil "R~D" i) "SB-VM"))))
		 `(progn
		    (eval-when (:compile-toplevel :load-toplevel :execute)
		      (sb-c:defknown ,name ,(make-list n :initial-element t) (values ,@(make-list n :initial-element t)) ()
			:overwrite-fndb-silently t))
		    (define-vop (,name)
		      (:translate ,name)
		      (:policy :fast-safe)
		      (:args ,@(loop for a in args
				     collect `(,a :scs (descriptor-reg any-reg control-stack)
						  :load-if (not (sc-is ,a control-stack)))))
		      ;; on the stack past the registers; live from the start, so
		      ;; that no result shares an argument's register (the moves
		      ;; are one by one: a result written over a later argument
		      ;; would copy the result)
		      (:results ,@(loop for r in results
					collect `(,r :scs (descriptor-reg any-reg control-stack) :load-if nil
						     :from :load)))
		      (:temporary (:sc descriptor-reg) temp)
		      (:generator 1
			,@(loop for a in args for r in results
				collect `(sc-case ,r
					   (control-stack
					    (sc-case ,a
					      (control-stack (load-stack-tn temp ,a) (store-stack-tn ,r temp))
					      (t (store-stack-tn ,r ,a))))
					   (t (sc-case ,a
						(control-stack (load-stack-tn ,r ,a))
						(t (move ,r ,a)))))))))))
	     (defs ()
	       `(progn ,@(loop for n from 2 to +qs-site-mark-arity+ collect `(def ,n)))))
    (defs))

  (defvar cl-user::*quasischeme-fixnum-vops* :unknown)
  (pushnew (lambda () (setq cl-user::*quasischeme-fixnum-vops* :unknown)) sb-ext:*init-hooks*)
  (defun qs-fixnum-vops-p ()
    (when (eq cl-user::*quasischeme-fixnum-vops* :unknown)
      (setq cl-user::*quasischeme-fixnum-vops*
	    (not (equal (uiop:getenv "QUASISCHEME_FIXNUM_VOPS") "0"))))
    (and cl-user::*quasischeme-fixnum-vops* (quasischeme-fast-p)))

  (macrolet ((overflow-bignum ()
	       ;; LOW, the untagged result, as a one-digit bignum in R
	       ;; (WITH-FIXED-ALLOCATION and STOREW-PAIR aren't in a built
	       ;; SBCL): two words, the header and the digit
	       `(progn
		  (inst mov header (logior (ash 1 n-widetag-bits) bignum-widetag))
		  (pseudo-atomic (lr :sync nil)
		    (allocation nil (* 2 n-word-bytes) other-pointer-lowtag r :flag-tn lr)
		    (inst stp header low (@ tmp-tn)))))
	     (def-c (name op)
	       `(define-vop (,name)
		  (:translate ,op)
		  (:policy :fast-safe)
		  (:guard (qs-fixnum-vops-p))
		  (:args (x :scs (any-reg) :target r))
		  (:info c)
		  (:vop-var vop)
		  (:arg-types tagged-num (:constant (integer -1023 1023)))
		  (:temporary (:sc signed-reg) low)
		  (:temporary (:sc unsigned-reg) header)
		  (:temporary (:scs (non-descriptor-reg) :offset lr-offset) lr)
		  (:results (r :scs (descriptor-reg any-reg)))
		  (:result-types t)
		  (:generator 3
		    (let ((c (if (eq ',op '+) c (- c))))
		      (if (minusp c)
			  (inst subs r x (fixnumize (- c)))
			  (inst adds r x (fixnumize c)))
		      (inst b :vc done)
		      (if (= (abs c) 1)
			  ;; one value overflows: the bignum is a constant
			  ;; (as SBCL's MOVE-FROM-FIXNUM+1), not code in the loop
			  (load-constant vop (emit-constant (if (plusp c)
								(1+ most-positive-fixnum)
								(1- most-negative-fixnum)))
					 r)
			  (progn
			    ;; R may be X: X is R less the constant, exactly (mod 2^64)
			    (if (minusp c)
				(inst add low r (fixnumize (- c)))
				(inst sub low r (fixnumize c)))
			    (inst asr low low n-fixnum-tag-bits)
			    (if (minusp c)
				(inst sub low low (- c))
				(inst add low low c))
			    (overflow-bignum))))
		    done)))
	     (def-2 (name op)
	       `(define-vop (,name)
		  (:translate ,op)
		  (:policy :fast-safe)
		  (:guard (qs-fixnum-vops-p))
		  ;; to :SAVE: to (:RESULT 0), R may share X's register, and the
		  ;; overflow path would untag the wrapped sum
		  (:args (x :scs (any-reg) :to :save)
			 (y :scs (any-reg) :to :save))
		  (:arg-types tagged-num tagged-num)
		  (:temporary (:sc signed-reg) low)
		  (:temporary (:sc signed-reg) high)
		  (:temporary (:sc unsigned-reg) header)
		  (:temporary (:scs (non-descriptor-reg) :offset lr-offset) lr)
		  (:results (r :scs (descriptor-reg any-reg)))
		  (:result-types t)
		  (:generator 4
		    (inst ,(if (eq op '+) 'adds 'subs) r x y)
		    (inst b :vc done)
		    (inst asr low x n-fixnum-tag-bits)
		    (inst asr high y n-fixnum-tag-bits)
		    (inst ,(if (eq op '+) 'add 'sub) low low high)
		    (overflow-bignum)
		    done))))
    ;; A fixnum plus or minus a fixnum or a small constant, an integer: on
    ;; the tagged words, ADDS or SUBS and a branch if it overflowed, where
    ;; SBCL's +/signed=>integer untags, adds and tags again (ASR, ADD,
    ;; ADDS): (+ a b) and (- n 1) in 2 instructions, not 4.  An overflow
    ;; makes the one-digit bignum.  QUASISCHEME_FIXNUM_VOPS=0 turns them
    ;; off.
    (def-c qs-fixnum+c=>integer +)
    (def-c qs-fixnum-c=>integer -)
    (def-2 qs-fixnum+fixnum=>integer +)
    (def-2 qs-fixnum-fixnum=>integer -))

  ;; ALLOCATE-VECTOR's LTN-ANNOTATE optimizer chooses its VOP: this one
  ;; for a small constant vector on the stack, else SBCL's
  (let ((info (sb-c::fun-info-or-lose 'allocate-vector)))
    (unless (get 'allocate-vector 'qs-original-ltn-annotate)
      (setf (get 'allocate-vector 'qs-original-ltn-annotate) (sb-c::fun-info-ltn-annotate info)))
    (let ((original (get 'allocate-vector 'qs-original-ltn-annotate)))
      (setf (sb-c::fun-info-ltn-annotate info)
	    (lambda (call)
	      (let ((args (sb-c::basic-combination-args call)))
		(if (and (quasischeme-fast-p)
			 (sb-c::node-stack-allocate-p call)
			 (= (length args) 3)
			 (every #'sb-c::constant-lvar-p args)
			 (every (lambda (a) (typep (sb-c::lvar-value a) 'fixnum)) args)
			 (<= (sb-c::lvar-value (third args)) 60)
			 (not (sb-c::msan-unpoison sb-c::*compilation*)))
		    (sb-c::vectorish-ltn-annotate-helper
		     call 'qs-allocate-small-vector-on-stack 'allocate-vector-on-heap)
		    (funcall original call)))))))

  ;; so that its elements are stored without GC card marks, as those of
  ;; SBCL's stack vectors are (STACK-CONSED-P knows its VOP by name)
  (unless (get 'stack-consed-p 'qs-original)
    (setf (get 'stack-consed-p 'qs-original) #'stack-consed-p))
  (sb-ext:without-package-locks
    (handler-bind ((warning #'muffle-warning))
      (let ((original (get 'stack-consed-p 'qs-original)))
	(setf (fdefinition 'stack-consed-p)
	      (lambda (object)
		(or (funcall original object)
		    (let ((write (sb-c::tn-writes (remove-moves object))))
		      (and write (not (sb-c::tn-ref-next write)) (sb-c::tn-ref-vop write)
			   (eq (sb-c::vop-name (sb-c::tn-ref-vop write)) 'qs-allocate-small-vector-on-stack)))))))))

  ;; Recursion without the processor's stack of return addresses.  RET
  ;; is predicted by that stack, which is a few dozen deep: a recursion
  ;; deeper than that mispredicts every return past it (on an M4, 20
  ;; cycles a return: a list recursion 500 deep took 3.3 times the cycles
  ;; of one 10 deep, in C as in SBCL; Chez Scheme, whose code returns by
  ;; a jump to the frame's return address, doesn't).  So in a function
  ;; that calls itself in exactly one place that isn't a tail call (a
  ;; recursion down a list or a tree's spine, ack's inner call), that
  ;; call is ADR LR, #8 and B, which push nothing on the stack of return
  ;; addresses, in place of BL; and each return of the function compares
  ;; its return address with that call's and, if they're the same, goes
  ;; there by a direct branch, else returns by RET to its caller, which
  ;; the stack, not disturbed by the recursion, predicts:
  ;;
  ;;       ADR TMP, back       ; back: just after the call of itself
  ;;       SUB TMP, LR, TMP
  ;;       CBNZ TMP, ret
  ;;       B back
  ;; ret:  RET LR
  ;;
  ;; The function must make no tail call of another (but the generic
  ;; arithmetic's, a slow path): that function's RET to the call's return
  ;; address, never pushed, would mispredict, and every return after it
  ;; (sboyer's REWRITE-ARGS, which ends in a tail call of SCONS, took a
  ;; third more cycles before that was seen).  ack takes 0.43 of the
  ;; cycles, divrec 0.53, primes 0.63.  (Choosing BL while the recursion
  ;; is shallow, by the return addresses of the frames 1, 4 and 16 calls
  ;; up, saved nothing measurable.  Every return of such a function by
  ;; BR LR, predicted by the indirect-branch predictor, did as well on
  ;; ack, but took nboyer 25% more cycles.)  Out of ADR's reach from a
  ;; return (a function of over a megabyte), the four instructions are
  ;; NOPs.  QUASISCHEME_SELF_CALLS=0 turns it off.
  (defvar cl-user::*quasischeme-self-calls* :unknown)
  (pushnew (lambda () (setq cl-user::*quasischeme-self-calls* :unknown)) sb-ext:*init-hooks*)

  (defun qs-self-calls-p ()
    (when (eq cl-user::*quasischeme-self-calls* :unknown)
      (setq cl-user::*quasischeme-self-calls*
	    (not (equal (uiop:getenv "QUASISCHEME_SELF_CALLS") "0"))))
    (and cl-user::*quasischeme-self-calls* (quasischeme-fast-p)))

  (defun qs-tail-calls-another-p (lambda)
    "Whether LAMBDA makes a tail call of another function, which would
return to LAMBDA's caller by RET."
    (let ((component (sb-c::lambda-component lambda)))
      (loop for block = (sb-c::block-next (sb-c::component-head component))
	      then (sb-c::block-next block)
	    until (or (null block) (eq block (sb-c::component-tail component)))
	      thereis (loop for ctran = (sb-c::block-start block) then (sb-c::node-next node)
			    for node = (and ctran (sb-c::ctran-next ctran))
			    while node
			      thereis (and (sb-c::basic-combination-p node)
					   (sb-c::node-tail-p node)
					   (eq (sb-c::node-home-lambda node) lambda)
					   (not (and (sb-c::combination-p node)
						     (eq (sb-c::basic-combination-kind node) :local)
						     (eq (sb-c::combination-lambda node) lambda)))
					   (or (eq (sb-c::basic-combination-kind node) :local)
					       (sb-c::mv-combination-p node)
					       (and (or (eq (sb-c::basic-combination-kind node) :full)
							(eq (sb-c::basic-combination-info node) :full))
						    (not (qs-slow-path-call-p node)))))))))

  (defun qs-slow-path-call-p (node)
    "Whether NODE calls one of the runtime's generic arithmetic procedures,
which inline arithmetic calls only when its operands aren't fixnums (ack's
(+ n 1) in tail position, a bignum's)."
    (let ((name (ignore-errors (sb-c::lvar-fun-name (sb-c::basic-combination-fun node))))
	  (package (find-package "QS")))
      (and name (symbolp name) package (eq (symbol-package name) package)
	   (member (symbol-name name) '("GENERIC+" "GENERIC-" "GENERIC*" "COMPARE2")
		   :test #'string=))))

  ;; lambda -> whether QS-ONE-SELF-CALL-P
  (defvar *qs-one-self-call* (make-hash-table :test 'eq :weakness :key :synchronized t))

  (defun qs-one-self-call-p (lambda)
    "Whether LAMBDA calls itself in exactly one place, not a tail call, and
makes no tail call of another function (whose RET to a deep call's return
address, not on the stack of return addresses, would mispredict, and every
return after it)."
    (multiple-value-bind (answer known) (gethash lambda *qs-one-self-call*)
      (if known
	  answer
	  (setf (gethash lambda *qs-one-self-call*)
		(let ((n 0))
		  (dolist (ref (sb-c::leaf-refs lambda))
		    (let* ((lvar (sb-c::node-lvar ref))
			   (dest (and lvar (sb-c::lvar-dest lvar))))
		      (when (and (sb-c::combination-p dest)
				 (eq (sb-c::basic-combination-fun dest) lvar)
				 (eq (sb-c::node-home-lambda dest) lambda)
				 (not (sb-c::node-tail-p dest)))
			(incf n))))
		  (and (= n 1) (not (qs-tail-calls-another-p lambda))))))))

  (defun qs-emit-word (segment word)
    "Emit the instruction WORD (little-endian)."
    (dotimes (i 4) (sb-assem:emit-byte segment (ldb (byte 8 (* 8 i)) word))))

  (defun qs-current-node ()
    (let ((vop (and (boundp 'sb-assem::*current-vop*) sb-assem::*current-vop*)))
      (and (sb-c::vop-p vop) (sb-c::vop-node vop))))

  ;; segment -> lambda -> (label . emitted): the deep-back of the
  ;; lambda's call of itself, in the code being assembled in the segment
  (defvar *qs-self-call-returns* (make-hash-table :test 'eq :weakness :key :synchronized t))

  (defun qs-self-call-return (segment lambda)
    (let ((table (or (gethash segment *qs-self-call-returns*)
		     (setf (gethash segment *qs-self-call-returns*) (make-hash-table :test 'eq)))))
      (or (gethash lambda table)
	  (setf (gethash lambda table) (cons (sb-assem:gen-label) nil)))))

  ;; The frame pointer, after a local call, from the stack pointer, not
  ;; from memory.  A function returns by loading its caller's frame
  ;; pointer from its frame (LDP CFP, LR, [CFP]), and everything the
  ;; caller does next with its frame (its variables live across the call
  ;; are there) waits on that load: SBCL's tak took 2.2 times the cycles
  ;; of C's for the same instructions.  The callee's frame starts at the
  ;; caller's stack pointer, which, in a function with nothing on the
  ;; stack above its frame, is the frame pointer plus the frame's size
  ;; (one size for all of a component's functions); after the return the
  ;; stack pointer is the callee's frame pointer again (or, with several
  ;; values, OCFP is).  So after the call:
  ;;
  ;;       SUB CFP, CSP, #size                ; KNOWN-CALL-LOCAL
  ;;       CSEL TMP, OCFP, CSP, EQ            ; CALL-LOCAL: OCFP if several
  ;;       SUB CFP, TMP, #size                ;   values (Z set), else CSP
  ;;
  ;; the same value the callee loaded, from registers the processor has.
  ;; Only in a function none of whose code leaves anything on the stack
  ;; above its frame: no stack allocation (a dynamic-extent vector, list,
  ;; closure or instance), no &more arguments, no values kept on the
  ;; stack (multiple-value-call, VALUES-LIST, unknown values received),
  ;; no unwind-protect or catch entry, in the calling function's own code
  ;; (QS-DIRTY-LAMBDAS).  tak
  ;; in SBCL took 0.59 of the cycles.  QUASISCHEME_FRAME_POINTER=0 turns
  ;; it off.
  (defvar cl-user::*quasischeme-frame-pointer* :unknown)
  (pushnew (lambda () (setq cl-user::*quasischeme-frame-pointer* :unknown)) sb-ext:*init-hooks*)

  (defparameter *qs-stack-vops*
    '("%%NIP-VALUES" "%MORE-ARG-VALUES-SKIP" "%MORE-ARG-VALUES" "%MORE-ARG-CONTEXT"
      "%LISTIFY-REST-ARGS" "ALLOCATE-DIRECT-MV-CALL-FRAME" "COPY-MORE-ARG" "NLX-ENTRY-MULTIPLE"
      "NLX-ENTRY" "PUSH-VALUES" "RESET-STACK-POINTER" "VALUES-LIST" "REVERSE-VALUES-LIST"
      "UNWIND-TO-FRAME-AND-CALL" "UWP-ENTRY-BLOCK" "MULTIPLE-CALL-LOCAL" "MULTIPLE-CALL"
      "MULTIPLE-CALL-NAMED" "MULTIPLE-CALL-VARIABLE" "CURRENT-STACK-POINTER"
      "ALLOCATE-VECTOR-ON-STACK" "QS-ALLOCATE-SMALL-VECTOR-ON-STACK" "MAKE-UNWIND-BLOCK"
      "MAKE-CATCH-BLOCK" "SET-UNWIND-PROTECT" "%CATCH-BLOCK" "%UNWIND-PROTECT")
    "VOPs that leave something on the stack above a frame.")

  (defparameter *qs-maybe-stack-vops* '("LIST" "LIST*" "CONS" "ACONS" "MAKE-CLOSURE" "FIXED-ALLOC" "VAR-ALLOC")
    "VOPs that do when they allocate on the stack.")

  (defun qs-stack-vop-p (v)
    (let ((name (symbol-name (sb-c::vop-name v))))
      (or (member name *qs-stack-vops* :test #'string=)
	  (search "ON-STACK" name)
	  (search "STACK-ALLOC" name)
	  (and (member name *qs-maybe-stack-vops* :test #'string=)
	       (or (member t (sb-c::vop-codegen-info v))
		   (let ((node (sb-c::vop-node v)))
		     (and node (sb-c::valued-node-p node)
			  (sb-c::node-stack-allocate-p node))))))))

  (defun qs-dirty-lambdas (component)
    "The functions of COMPONENT whose code may leave something on the stack
above their frame: those a stack-moving VOP is in (by its block)."
    (let ((dirty (make-hash-table :test 'eq)))
      (loop for b = (sb-c::block-info (sb-c::component-head component)) then (sb-c::ir2-block-next b)
	    while b
	    do (loop for v = (sb-c::ir2-block-start-vop b) then (sb-c::vop-next v)
		     while v
		     when (qs-stack-vop-p v)
		       do (let ((block (sb-c::ir2-block-block b)))
			    (setf (gethash (and block (sb-c::block-home-lambda block)) dirty) t))
		     ;; an entry with &REST or &MORE arguments leaves them above
		     ;; the frame and goes on, in the same frame, into functions
		     ;; of its own (a machine's body), by tail calls: below
		     when (member (symbol-name (sb-c::vop-name v))
				  '("COPY-MORE-ARG" "%MORE-ARG-CONTEXT" "%LISTIFY-REST-ARGS")
				  :test #'string=)
		       do (let ((block (sb-c::ir2-block-block b)))
			    (setf (gethash (and block (sb-c::block-home-lambda block)) dirty) t))))
      ;; A function a dirty one calls in tail position runs in its frame,
      ;; with what it left above: dirty too.  (Before, any &more entry
      ;; made the whole component dirty, and a Racket linklet always has
      ;; one: fib in the benchmark's linklet took 36% longer than alone.)
      (let ((tail-calls '()))
	(loop for block = (sb-c::block-next (sb-c::component-head component)) then (sb-c::block-next block)
	      until (or (null block) (eq block (sb-c::component-tail component)))
	      when (sb-c::block-start block)
	      do (loop for node = (sb-c::ctran-next (sb-c::block-start block))
			 then (let ((next (sb-c::node-next node))) (and next (sb-c::ctran-next next)))
		       while node
		       do (when (and (sb-c::combination-p node)
				     (eq (sb-c::basic-combination-kind node) :local)
				     (sb-c::node-tail-p node))
			    (push (cons (sb-c::node-home-lambda node) (sb-c::combination-lambda node))
				  tail-calls))))
	(loop with changed = t
	      while changed
	      do (setq changed nil)
		 (dolist (c tail-calls)
		   (when (and (gethash (car c) dirty) (not (gethash (cdr c) dirty)))
		     (setf (gethash (cdr c) dirty) t changed t)))))
      dirty))

  ;; component -> its QS-DIRTY-LAMBDAS
  (defvar *qs-dirty-lambdas* (make-hash-table :test 'eq :weakness :key :synchronized t))

  (defun qs-emit-frame-pointer-restore (segment)
    (let* ((vop (and (boundp 'sb-assem::*current-vop*) sb-assem::*current-vop*))
	   (name (and (sb-c::vop-p vop) (symbol-name (sb-c::vop-name vop)))))
      (when (and (member name '("KNOWN-CALL-LOCAL" "CALL-LOCAL") :test #'string=)
		 (progn (when (eq cl-user::*quasischeme-frame-pointer* :unknown)
			  (setq cl-user::*quasischeme-frame-pointer*
				(not (equal (uiop:getenv "QUASISCHEME_FRAME_POINTER") "0"))))
			cl-user::*quasischeme-frame-pointer*)
		 (quasischeme-fast-p))
	(let* ((component (sb-c::block-component (sb-c::ir2-block-block (sb-c::vop-block vop))))
	       (bytes (* n-word-bytes (sb-c::sb-allocated-size 'control-stack))))
	  (when (and (< 0 bytes 4096)
		     (let ((dirty (or (gethash component *qs-dirty-lambdas*)
				      (setf (gethash component *qs-dirty-lambdas*)
					    (qs-dirty-lambdas component))))
			   (block (sb-c::ir2-block-block (sb-c::vop-block vop))))
		       (not (or (gethash nil dirty)
				(gethash (sb-c::block-home-lambda block) dirty)))))
	    (flet ((sub-imm (rd rn) (logior #xD1000000 (ash bytes 10) (ash rn 5) rd)))
	      (if (string= name "KNOWN-CALL-LOCAL")
		  (qs-emit-word segment (sub-imm cfp-offset csp-offset))
		  (progn
		    ;; CSEL TMP, OCFP, CSP, EQ
		    (qs-emit-word segment (logior #x9A800000 (ash csp-offset 16) (ash 0 12)
						  (ash ocfp-offset 5) tmp-offset))
		    (qs-emit-word segment (sub-imm cfp-offset tmp-offset))))))))))

  (macrolet ((adr (rd offset)		; OFFSET from this instruction
	       `(logior #x10000000 (ash (ldb (byte 2 0) ,offset) 29) (ash (ldb (byte 19 2) ,offset) 5) ,rd))
	     (sub (rd rn rm) `(logior #xCB000000 (ash ,rm 16) (ash ,rn 5) ,rd))
	     (b (words) `(logior #x14000000 (ldb (byte 26 0) ,words))))

    (flet ((original (name)
	     (or (get name 'qs-original)
		 (setf (get name 'qs-original) (gethash name sb-assem::*inst-encoder*)))))
      (let ((bl (original 'sb-arm64-asm::bl))
	    (ret (original 'sb-arm64-asm::ret)))
	(setf (gethash 'sb-arm64-asm::bl sb-assem::*inst-encoder*)
	      (lambda (segment target)
		(let* ((node (qs-current-node))
		       (lambda (and node (sb-c::node-home-lambda node))))
		  (if (and (sb-assem::label-p target)
			   (sb-c::combination-p node)
			   (eq (sb-c::basic-combination-kind node) :local)
			   (eq (sb-c::combination-lambda node) lambda)
			   (qs-self-calls-p)
			   (qs-one-self-call-p lambda))
		      (let ((back (qs-self-call-return segment lambda)))
			;; ADR LR, #8: the instruction after the B
			(qs-emit-word segment (adr lr-offset 8))
			(funcall (gethash 'sb-arm64-asm::b sb-assem::*inst-encoder*) segment target)
			(sb-assem::%emit-label segment (and (boundp 'sb-assem::*current-vop*) sb-assem::*current-vop*)
					       (car back))
			(setf (cdr back) t)
			(qs-emit-frame-pointer-restore segment))
		      (progn (funcall bl segment target)
			     (qs-emit-frame-pointer-restore segment))))))
	(setf (gethash 'sb-arm64-asm::ret sb-assem::*inst-encoder*)
	      (lambda (segment &optional (register lr-tn))
		(let* ((node (qs-current-node))
		       (lambda (and node (sb-c::node-home-lambda node))))
		  (when (and lambda (qs-self-calls-p) (qs-one-self-call-p lambda))
		    (let ((back (qs-self-call-return segment lambda))
			  (lr (sb-arm64-asm::gpr-offset register)))
		      (sb-assem:emit-back-patch
		       segment 16
		       (lambda (segment posn)
			 (let ((offset (and (cdr back) (- (sb-assem::label-position (car back)) posn))))
			   (dolist (word (if (and offset (typep offset '(signed-byte 21)))
					     (list (adr tmp-offset offset)
						   (sub tmp-offset lr tmp-offset)
						   ;; CBNZ TMP, #8: to the RET
						   (logior #xB5000000 (ash 2 5) tmp-offset)
						   (b (ash (- offset 12) -2)))
					     (make-list 4 :initial-element #xD503201F))) ; NOP
			     (qs-emit-word segment word))))))))
		(funcall ret segment register))))))

  (sb-ext:lock-package "SB-C")
  (sb-ext:lock-package "SB-VM"))

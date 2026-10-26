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

  (define-vop (qs-allocate-small-vector-on-stack)
    (:info type length words)
    (:arg-types (:constant fixnum) (:constant fixnum) (:constant fixnum))
    (:results (result :scs (descriptor-reg)))
    (:temporary (:sc non-descriptor-reg) header)
    (:temporary (:sc any-reg) len)
    (:generator 2
      (let ((bytes (logandc2 (+ (* (+ words vector-data-offset) n-word-bytes) lowtag-mask) lowtag-mask)))
	(allocation nil bytes other-pointer-lowtag result :stack-allocate-p t)
	(load-immediate-word header type)
	(load-immediate-word len (fixnumize length))
	(inst stp header len (@ tmp-tn))
	(loop for off from (* 2 n-word-bytes) below bytes by (* 2 n-word-bytes)
	      do (inst stp zr-tn zr-tn (@ tmp-tn off))))))

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

  (defparameter *qs-maybe-stack-vops* '("LIST" "MAKE-CLOSURE" "FIXED-ALLOC" "VAR-ALLOC")
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
			    (setf (gethash (and block (sb-c::block-home-lambda block)) dirty) t))))
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

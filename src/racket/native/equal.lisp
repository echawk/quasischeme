; -*- Mode: Lisp; Syntax: Common-Lisp; Package: QUASISCHEME-RACKET -*-

;;;; Racket's equal? and equal-hash-code, natively, and the hash tables'
;;;; equal?-based test (hash.lisp's RACKET-EQUAL).
;;;;
;;;; equal? is eqv?, or recursive on pairs, mutable pairs, vectors,
;;;; strings, byte strings, boxes, hash tables and paths; a struct is
;;;; compared by its type's prop:equal+hash, else field by field when its
;;;; type is transparent or prefab, else by identity.  The hash agrees:
;;;; prop:equal+hash's hash procedure, or the fields of a transparent
;;;; struct.  Cyclic and widely shared data take union-find (EQUAL*); a
;;;; chaperoned box or hash table is compared through
;;;; its chaperone, a chaperoned struct by its fields underneath.

(in-package "QUASISCHEME-RACKET")

(defvar *prop-equal+hash* (%make-struct-type-property (rsym "prop:equal+hash") nil '()))
(define-primitive "#%kernel" "prop:equal+hash" *prop-equal+hash*)

(defun equal+hash-procedures (x)
  "X's prop:equal+hash: its equal procedure, hash procedure and secondary
hash procedure, and whether they take Racket's newer protocol's last
argument (a list of two procedures: now?, false for equal-always?), or NIL."
  (multiple-value-bind (v found) (property-value x *prop-equal+hash*)
    (when found
      (cond ((and (consp v) (null (cddr v))) (values (first v) (second v) nil t))
	    ((consp v) (values (first v) (second v) (third v) nil))
	    ((simple-vector-p v) (values (svref v 0) (svref v 1) (and (> (length v) 2) (svref v 2)) nil))
	    (t nil)))))

(defvar *equal-bounded* nil
  "While EQUAL-WITH-CYCLES first recurs plainly: the catch tag that
abandons it for union-find.")
(defvar *custom-equal-depth* 0
  "How many prop:equal+hash equal procedures are running, each a stack of
Racket frames: past a few, a cyclic value may exhaust the stack before
the budget ends, so the plain recursion is abandoned.")

(defvar *secondary-hash* nil "Whether structs hash by their prop:equal+hash's secondary procedure.")

(defun call-equal-procedure (eqp new a b recur always)
  "EQP, a prop:equal+hash equal procedure, on A and B (NEW: of the newer
protocol; ALWAYS: for equal-always?)."
  (let ((*custom-equal-depth* (1+ *custom-equal-depth*)))
    (when (and *equal-bounded* (> *custom-equal-depth* 64))
      (throw *equal-bounded* nil))
    (truthy (if new (funcall eqp a b recur (bool (not always))) (funcall eqp a b recur)))))

(defun call-hash-procedure (hashp new x recur always)
  "HASHP, a prop:equal+hash hash procedure, on X: an exact integer."
  (let ((h (if new (funcall hashp x recur (bool (not always))) (funcall hashp x recur))))
    (unless (integerp h)
      (error 'racket-error :who "equal-hash-code" :type "exn:fail:contract"
			   :message (format nil "hash procedure returned a value other than an exact integer~%  result: ~A"
					    (printed-quoted h))))
    (logand h most-positive-fixnum)))

(defun equal-step* (a b recur)
  "One step of EQUAL*: A and B compared, their parts by RECUR."
  (cond ((eq a b) t)
	;; symbols, fixnums and characters are equal? only when eq?/eqv?:
	;; the common keys, answered before the other types are tried
	((or (symbolp a) (symbolp b)) nil)
	((typep a 'fixnum) (eql a b))
	((consp a) (and (consp b) (funcall recur (car a) (car b)) (funcall recur (cdr a) (cdr b))))
	((numberp a) (racket-eqv a b))
	((characterp a) (eql a b))
	((stringp a) (and (stringp b) (string= a b)))
	((typep a '(simple-array (unsigned-byte 8) (*)))
	 (and (typep b '(simple-array (unsigned-byte 8) (*))) (equalp a b)))
	((simple-vector-p a)
	 (and (simple-vector-p b) (= (length a) (length b)) (every recur a b)))
	((rbox-p a) (and (rbox-p b) (funcall recur (box-ref* a) (box-ref* b))))
	((mpair-p a) (and (mpair-p b) (funcall recur (mpair-car a) (mpair-car b)) (funcall recur (mpair-cdr a) (mpair-cdr b))))
	((rpath-p a) (and (rpath-p b) (string= (rpath-string a) (rpath-string b))))
	((hash-table-p* a) (hash-equal a b))
	;; fxvectors and flvectors (more.lisp): flonums as eqv?
	((typep a '(simple-array double-float (*)))
	 (and (typep b '(simple-array double-float (*))) (= (length a) (length b))
	      (every #'racket-eqv a b)))
	((typep a 'fxvector)
	 (and (typep b 'fxvector) (equalp (fxvector-items a) (fxvector-items b))))
	;; a stencil vector (data.lisp)
	((typep a 'stencil)
	 (and (typep b 'stencil) (= (stencil-mask a) (stencil-mask b))
	      (every recur (stencil-items a) (stencil-items b))))
	((struct-instance-p a)
	 (and (struct-instance-p b)
	      (eq (struct-of-type a) (struct-of-type b))
	      (multiple-value-bind (eqp hashp hash2p new) (equal+hash-procedures a)
		(declare (ignore hashp hash2p))
		(cond (eqp (call-equal-procedure eqp new a b (lambda (x y) (bool (funcall recur x y))) nil))
		      ((transparent-p (struct-of-type a))
		       (let ((n (struct-field-count a))) (and (= n (struct-field-count b)) (loop for i below n always (funcall recur (struct-field a i) (struct-field b i))))))
		      (t nil)))))
	(t nil)))

;; Plain recursion first; past *EQUAL-BUDGET* nodes (src/core.lisp) it
;; starts again with union-find, as Racket CS's equal? does (Adams and
;; Dybvig, ICFP 2008): two compound objects already in one class are
;; equal, and comparing two others merges their classes.  Shared
;; substructure takes linear time, and cyclic data ends.

(declaim (inline equal-with-cycles))
(defun equal-with-cycles (a b step)
  "Whether A and B are equal by STEP (a b recur), recursion first, then
union-find past the budget."
  (when (eq a b) (return-from equal-with-cycles t))
  (let ((budget qs::*equal-budget*))
    (declare (fixnum budget))
    (block bounded
      (labels ((walk (a b)
		 (when (minusp (decf budget)) (return-from bounded nil))
		 (funcall step a b #'walk)))
	(let* ((tag (list nil))
	       (*equal-bounded* tag))
	  (catch tag
	    (return-from equal-with-cycles (walk a b))))))
    (let ((parents (make-hash-table :test 'eq))
	  (*equal-bounded* nil)
	  (*custom-equal-depth* 0))
      (labels ((class-root (x)
		 (let ((p (gethash x parents)))
		   (if (null p)
		       x
		       (setf (gethash x parents) (class-root p)))))
	       (compound-p (x)
		 (or (consp x) (simple-vector-p x) (mpair-p x) (rbox-p x)
		     (struct-instance-p x)))
	       (walk (a b)
		 (if (and (compound-p a) (compound-p b))
		     (let ((ra (class-root a)) (rb (class-root b)))
		       (or (eq ra rb)
			   (progn (setf (gethash ra parents) rb)
				  (funcall step a b #'walk))))
		     (funcall step a b #'walk))))
	(walk a b)))))

(defun equal* (a b)
  (equal-with-cycles a b #'equal-step*))

(defun hash-equal (a b)
  (and (hash-table-p* b)
       (eq (hash-kind a) (hash-kind b))
       (eq (hash-immutable-p a) (hash-immutable-p b))
       (= (length (entries a)) (length (entries b)))
       (loop for (k . v) across (entries a)
	     always (multiple-value-bind (w found) (lookup* b k)
		      (and found (equal* v w))))))

(defun equal-hash* (x &optional (depth 0))
  (cond ((> depth 16) 0)
	((consp x) (mix (equal-hash* (car x) (1+ depth)) (equal-hash* (cdr x) (1+ depth))))
	((stringp x) (logand (sxhash (coerce x 'simple-string)) most-positive-fixnum))
	((simple-vector-p x)
	 (let ((h (length x)))
	   (loop for e across x for i below 8 do (setq h (mix h (equal-hash* e (1+ depth)))))
	   h))
	((typep x '(simple-array (unsigned-byte 8) (*)))
	 (let ((h (length x)))
	   (loop for b across x for i below 64 do (setq h (mix h b)))
	   h))
	((rbox-p x) (mix 7 (equal-hash* (box-ref* x) (1+ depth))))
	((typep x 'stencil)
	 (let ((h (mix 17 (stencil-mask x))))
	   (loop for e across (stencil-items x) for i below 8 do (setq h (mix h (equal-hash* e (1+ depth)))))
	   h))
	((typep x 'fxvector)
	 (let ((h (mix 19 (length (fxvector-items x)))))
	   (loop for e across (fxvector-items x) for i below 8 do (setq h (mix h (eqv-hash e))))
	   h))
	((typep x '(simple-array double-float (*)))
	 (let ((h (mix 23 (length x))))
	   (loop for e across x for i below 8 do (setq h (mix h (eqv-hash e))))
	   h))
	((mpair-p x) (mix (equal-hash* (mpair-car x) (1+ depth)) (equal-hash* (mpair-cdr x) (1+ depth))))
	((rpath-p x) (mix 11 (logand (sxhash (rpath-string x)) most-positive-fixnum)))
	((hash-table-p* x) (mix 13 (length (entries x))))
	((struct-instance-p x)
	 (multiple-value-bind (eqp hashp hash2p new) (equal+hash-procedures x)
	   (declare (ignore hash2p))
	   (cond (eqp (call-hash-procedure hashp new x (lambda (y) (equal-hash* y (1+ depth))) nil))
		 ((transparent-p (struct-of-type x))
		  (let ((h (eq-hash (struct-of-type x))))
		    (loop for i below (min 8 (struct-field-count x))
			  do (setq h (mix h (equal-hash* (struct-field x i) (1+ depth)))))
		    h))
		 (t (eq-hash x)))))
	(t (eqv-hash x))))

(defnative "equal?" (a b) () (bool (equal* a b)))
(defnative "equal-always?" (a b) () (bool (equal* a b)))
(defnative "equal?/recur" (a b recur) ()
  (declare (ignore recur))
  (bool (equal* a b)))

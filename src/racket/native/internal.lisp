; -*- Mode: Lisp; Syntax: Common-Lisp; Package: QUASISCHEME-RACKET -*-

;;;; #%internal, as Racket CS's (cs/primitive/internal.ss): what
;;;; schemify's output calls that Racket code can't, so that linklets
;;;; schemify made run here too.  Its struct definitions are Chez
;;;; records' (schemify/struct-convert.rkt): make-record-type-descriptor
;;;; with (field-count . mutable-mask), the properties installed after
;;;; (make-struct-type-install-properties), then record-constructor,
;;;; record-predicate and record-accessor; here those make and use this
;;;; mode's struct types (structs.lisp), as make-struct-type does.

(in-package "QUASISCHEME-RACKET")

;;; ------------------------------------------------------------------
;;; Struct types as records (rumble/struct.ss)

(defstruct (prefab-uid (:constructor make-prefab-uid (type))) type)

(defun mask-immutables (n mask)
  "The fields of N, as indexes, whose bit isn't in MASK (the mutable ones')."
  (loop for i below n unless (logbitp i mask) collect i))

(defnatives "#%internal"
  ("make-record-type-descriptor" (name parent uid sealed? opaque? fields)
   (declare (ignore sealed? opaque?))
   (if (prefab-uid-p uid)
       (prefab-uid-type uid)
       (let* ((parent (and (truthy parent) parent))
	      (n (if (consp fields) (car fields) (length fields)))
	      (immutables (if (consp fields)
			      (mask-immutables n (cdr fields))
			      (loop for f across fields for i from 0
				    when (symbol-named-p (if (consp f) (car f) f) "immutable") collect i))))
	 (%make-struct-type :name name :parent parent :field-count n
			    :init-field-count n :auto-field-count 0 :auto-value qs:false
			    :total (+ n (if parent (struct-type-total parent) 0))
			    :properties (if parent (struct-type-properties parent) '())
			    :immutables immutables :inspector (current-inspector*)))))
  ("make-record-constructor-descriptor" (rtd parent-rcd protocol)
   (declare (ignore parent-rcd protocol))
   rtd)
  ("structure-type-lookup-prefab-uid" (name parent init-count auto-count auto-v immutables)
   (make-prefab-uid (nth-value 0 (make-struct-type* name (or parent qs:false) init-count auto-count auto-v
						    '() (rsym "prefab") qs:false immutables))))
  ("#%nongenerative-uid" (name) name)
  ("make-struct-type-install-properties" (name init-count auto-count parent
					       &optional (props '()) (insp (current-inspector*))
					       (proc-spec qs:false) (immutables '()) (guard qs:false)
					       (constructor-name qs:false))
   (declare (ignore name init-count auto-count parent))
   ;; the finishing procedure, which gives an rtd its properties
   (lambda (type)
     (let ((index (if (integerp proc-spec) proc-spec (cdr (assoc *prop-procedure* props)))))
       (setf (struct-type-immutables type)
	     (union (struct-type-immutables type)
		    (if (and (integerp index) (not (member index immutables))) (cons index immutables) immutables))))
     (setf (struct-type-inspector type) (if (and (symbolp insp) (string= (rname insp) "current"))
					    (current-inspector*)
					    insp)
	   (struct-type-guard type) (and (truthy guard) guard)
	   (struct-type-constructor-name type) (and (truthy constructor-name) constructor-name)
	   (struct-type-proc-spec type) (and (truthy proc-spec) proc-spec))
     (multiple-value-bind (accessor mutator) (set-general-procedures type)
       (install-struct-properties type props accessor mutator))
     *void*))
  ("record-constructor" (rtd)
   (let ((f (constructor rtd)))
     (setf (gethash f *renamed-procedures*)
	   (if (struct-type-constructor-name rtd)
	       (struct-type-constructor-name rtd)
	       (rsym (rname (struct-type-name rtd)))))
     (note-struct-procedure f :constructor rtd)
     f))
  ("record-predicate" (rtd)
   (let ((f (lambda (x) (bool (and (struct-instance-p x) (subtype-p (struct-of-type x) rtd))))))
     (setf (gethash f *renamed-procedures*) (rsym (format nil "~A?" (rname (struct-type-name rtd)))))
     (note-struct-procedure f :predicate rtd)
     f))
  ("record-accessor" (rtd pos)
   (funcall (native-function (gethash "make-struct-field-accessor" *natives*))
	    (record-general rtd #'struct-type-accessor) pos))
  ("record-mutator" (rtd pos)
   (funcall (native-function (gethash "make-struct-field-mutator" *natives*))
	    (record-general rtd #'struct-type-mutator) pos))
  ("struct-type-constructor-add-guards" (ctr rtd name)
   ;; the constructor runs the guards itself
   (declare (ignore rtd name))
   ctr)
  ("#%struct-constructor" (p arity-mask) (declare (ignore arity-mask)) p)
  ("#%struct-predicate" (p) p)
  ("#%struct-field-accessor" (p rtd pos) (declare (ignore rtd pos)) p)
  ("#%struct-field-mutator" (p rtd pos) (declare (ignore rtd pos)) p)
  ("unsafe-struct?" (v rtd) (bool (and (struct-instance-p v) (subtype-p (struct-of-type v) rtd))))
  ("unsafe-sealed-struct?" (v rtd) (bool (and (struct-instance-p v) (eq (struct-of-type v) rtd))))
  ("unsafe-struct" (rtd &rest fields) (make-rstruct rtd (coerce fields 'simple-vector))))

(defun record-general (rtd get)
  "RTD's general accessor or mutator (GET), made if its properties
weren't installed."
  (or (funcall get rtd)
      (progn (set-general-procedures rtd) (funcall get rtd))))

(defun set-general-procedures (type)
  "Make TYPE's general accessor and mutator, noted as make-struct-type's are."
  (multiple-value-bind (accessor mutator) (general-field-procedures type)
    (setf (struct-type-accessor type) accessor (struct-type-mutator type) mutator)
    (note-struct-procedure accessor :accessor type)
    (note-struct-procedure mutator :mutator type)
    (values accessor mutator)))

;;; ------------------------------------------------------------------
;;; Impersonators: the accessors here see through them already

(defun impersonator-val (x)
  "What impersonator X wraps, one layer down."
  (cond ((impersonation x) (impersonation-of (impersonation x)))
	((chaperone-layer-p x) (layer-of x))
	((cbox-p x) (cbox-of x))
	(t x)))

(defnatives "#%internal"
  ("impersonator-val" (x) (impersonator-val x))
  ("impersonate-ref" (acc rtd pos orig &rest names)
   (declare (ignore rtd pos names))
   (funcall acc orig))
  ("impersonate-set!" (set rtd pos abs-pos orig v &rest names)
   (declare (ignore rtd pos abs-pos names))
   (funcall set orig v)))

;;; ------------------------------------------------------------------
;;; Boxes, strings, values and errors schemify's output uses

(defnatives "#%internal"
  ("#%call-with-values" (producer consumer)
   (multiple-value-call consumer (funcall producer)))
  ("unbox/check-undefined" (b name)
   (let ((v (rbox-value b)))
     (if (eq v *unsafe-undefined*)
	 (raise-variable-error name "cannot use before initialization")
	 v)))
  ("set-box!/check-undefined" (b v name)
   (when (eq (rbox-value b) *unsafe-undefined*)
     (racket-error (rname name) "assignment disallowed;~% cannot assign before initialization"))
   (setf (rbox-value b) v)
   *void*)
  ("apply-string-append" (pre-n strss) (apply-append "string-append" pre-n strss 'string))
  ("apply-string-append-immutable" (pre-n strss)
   (immutable! (apply-append "string-append-immutable" pre-n strss 'string)))
  ("apply-bytes-append" (pre-n bss) (apply-append "bytes-append" pre-n bss '(unsigned-byte 8)))
  ("raise-binding-result-arity-error" (expected args)
   (raise-result-arity-error-from "internal" qs:false *default-realm*
				  (if (integerp expected) expected (length expected))
				  (format nil "~%  in: local-binding form") args))
  ("raise-definition-result-arity-error" (expected args)
   (raise-result-arity-error-from "internal" (rsym "define-values") *primitive-realm* (length expected)
				  (if expected
				      (format nil "~%  in: definition of ~A ..." (rname (car expected)))
				      "")
				  args))
  ("call-with-module-prompt" (proc)
   (funcall (native-function (gethash "call-with-continuation-prompt" *natives*)) proc)))

(defun apply-append (who pre-n seqs element-type)
  "SEQS (a list, PRE-N of them given before apply's list) appended."
  (unless (listp (nthcdr pre-n seqs)) (arg-error "apply" "list?" (nthcdr pre-n seqs)))
  (dolist (s seqs)
    (unless (typep s (if (eq element-type 'string) 'string '(array (unsigned-byte 8) (*))))
      (arg-error who (if (eq element-type 'string) "string?" "bytes?") s)))
  (let ((out (make-array (reduce #'+ seqs :key #'length) :element-type (if (eq element-type 'string) 'character element-type)))
	(i 0))
    (dolist (s seqs out)
      (replace out s :start1 i)
      (incf i (length s)))))

;;; ------------------------------------------------------------------
;;; Threads, engines, locks: the host's (Chez's make-mutex and the rest)

(defnatives "#%internal"
  ("make-pthread-parameter" (v)
   (funcall (native-function (gethash "make-parameter" *natives*)) v))
  ("engine-block" () (native-call "sleep") *void*)
  ("assert-push-lock-level!" (level) (declare (ignore level)) *void*)
  ("assert-pop-lock-level!" (level) (declare (ignore level)) *void*)
  ("threaded?" () qs:true)
  ("make-mutex" (&optional name) (declare (ignore name)) (sb-thread:make-mutex :name "mutex"))
  ("make-condition" (&optional name) (declare (ignore name)) (sb-thread:make-waitqueue))
  ("mutex-acquire" (m &optional (block? qs:true))
   (if (truthy block?)
       (progn (sb-thread:grab-mutex m) *void*)
       (bool (sb-thread:grab-mutex m :waitp nil))))
  ("mutex-release" (m) (sb-thread:release-mutex m) *void*)
  ("condition-wait" (c m &optional timeout)
   (declare (ignore timeout))
   (sb-thread:condition-wait c m)
   qs:true)
  ("condition-signal" (c) (sb-thread:condition-notify c) *void*)
  ("condition-broadcast" (c) (sb-thread:condition-broadcast c) *void*))

;;; ------------------------------------------------------------------
;;; ptr-ref/TYPE and ptr-set!/TYPE (rumble/foreign.ss's fast ones): an
;;; offset in bytes when ABS? is true, else in elements

(macrolet ((def (kind rep size)
	     `(progn
		(defnative ,(format nil "ptr-ref/~A" kind) (p offset abs?) (:instance "#%internal" :leaf t)
		  (unless (fixnum-p offset) (arg-error "ptr-ref" "fixnum?" offset))
		  (read-rep ,rep p (if (truthy abs?) offset (* offset ,size))))
		(defnative ,(format nil "ptr-set!/~A" kind) (p offset abs? v) (:instance "#%internal" :leaf t)
		  (unless (fixnum-p offset) (arg-error "ptr-set!" "fixnum?" offset))
		  (write-rep ,rep p (if (truthy abs?) offset (* offset ,size)) v)
		  *void*))))
  (def "int8" :integer-8 1) (def "uint8" :unsigned-8 1)
  (def "int16" :integer-16 2) (def "uint16" :unsigned-16 2)
  (def "int32" :integer-32 4) (def "uint32" :unsigned-32 4)
  (def "int64" :integer-64 8) (def "uint64" :unsigned-64 8)
  (def "double" :double 8) (def "float" :float 4))

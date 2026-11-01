; -*- Mode: Lisp; Syntax: Common-Lisp; Package: CL-USER -*-

;;;; Tests of the workarounds for SBCL in src/sbcl-compiler.lisp.
;;;;
;;;; CLOSURE-INIT's card mark (arm64): a LABELS group's closures are made
;;;; one by one, a collection possibly between, and stored in each other
;;;; after; without the mark, a closure promoted meanwhile held siblings
;;;; the next collection freed (Guile's reader, after some 100,000
;;;; reads: heap_scavenge failure).  Checked twice: the code has the mark,
;;;; and groups made under frequent collections, with the collector
;;;; verifying the heap, stay intact.
;;;;
;;;; Usage:  sbcl --dynamic-space-size 4GB --control-stack-size 500MB --script tests/run-sbcl-tests.lisp

(require :asdf)

(let ((setup (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (when (probe-file setup) (load setup)))

(defun load-system (system)
  (if (find-package "QL")
      (uiop:symbol-call "QL" "QUICKLOAD" system :silent t)
      (asdf:load-system system)))

(let* ((here (make-pathname :name nil :type nil
			    :defaults (or *load-truename* *load-pathname*)))
       (root (merge-pathnames (make-pathname :directory '(:relative :up))
			       here)))
  (pushnew (truename root) asdf:*central-registry* :test #'equal))

(let ((*standard-output* (make-broadcast-stream))
      (*error-output* (make-broadcast-stream)))
  (handler-bind ((warning #'muffle-warning))
    (load-system :quasischeme/rts)))

(defvar *run* 0)
(defvar *passed* 0)

(defmacro check (name form)
  `(progn (incf *run*)
	  (if ,form
	      (incf *passed*)
	      (format t "~&FAIL ~A~%" ,name))))

;;; A group of closures that hold each other and many variables, as
;;; %read's do: the delayed CLOSURE-INITs store younger siblings.
(defun make-group (a b c d e f)
  (labels ((p (x) (if (eq x a) #'q (list b c d e f)))
	   (q (x) (if (eq x b) #'r (list a c d e f)))
	   (r (x) (if (eq x c) #'s (list a b d e f)))
	   (s (x) (if (eq x d) #'p (list a b c e f))))
    #'p))

#+(and sbcl arm64)
(check "closure-init marks the card"
       (let ((text (with-output-to-string (*standard-output*)
		     (disassemble (compile nil '(lambda (a b)
						 (labels ((f (x) (if (eq x a) #'g b))
							  (g (y) (if (eq y b) #'f a)))
						   (list #'f #'g))))))))
	 ;; a mark for each closure stored in a sibling (four), at least
	 (>= (loop for start = 0 then (1+ i)
		   for i = (search "CARDTABLE" text :start2 start)
		   while i count t)
	     4)))

#+sbcl
(check "closure groups survive collections between their closures"
       (let ((keep (make-array 1024 :initial-element nil))
	     (old (sb-ext:bytes-consed-between-gcs)))
	 (setf (sb-ext:bytes-consed-between-gcs) (* 256 1024))
	 (unwind-protect
	      (dotimes (i 400000)
		(let ((a (list i)) (b (list i)) (c (list i)) (d (list i)))
		  (setf (svref keep (mod i 1024))
			(list a b c d (make-group a b c d (make-string 2) (list i))))))
	   (setf (sb-ext:bytes-consed-between-gcs) old))
	 (sb-ext:gc :full t)
	 ;; without the mark, a sibling's slot comes to hold whatever reused
	 ;; its memory: a type error, or worse
	 (ignore-errors
	  (every (lambda (e)
		   (destructuring-bind (a b c d p) e
		     (let* ((q (funcall p a)) (r (funcall q b)) (s (funcall r c)))
		       (eq (funcall s d) p))))
		 keep))))

(format t "~&SBCL: ~D of ~D tests passed.~%" *passed* *run*)
(uiop:quit (if (= *passed* *run*) 0 1))

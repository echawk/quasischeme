; -*- Mode: Lisp; Syntax: Common-Lisp; Package: CL-USER -*-
;;;; Tests of the optimizer's passes (src/cp0.lisp and after): for now
;;;; cpcommonize (src/cpcommonize.lisp), which merges a letrec's
;;;; procedures that differ only in their variables' names.
;;;;
;;;; Usage:  sbcl --dynamic-space-size 4GB --control-stack-size 500MB --script tests/run-optimizer-tests.lisp

(require :asdf)
(let ((setup (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (when (probe-file setup) (load setup)))
(let* ((here (make-pathname :name nil :type nil
			    :defaults (or *load-truename* *load-pathname*)))
       (root (merge-pathnames (make-pathname :directory '(:relative :up)) here)))
  (pushnew (truename root) asdf:*central-registry* :test #'equal))
(let ((*standard-output* (make-broadcast-stream)) (*error-output* (make-broadcast-stream)))
  (handler-bind ((warning #'muffle-warning))
    (asdf:load-system :quasischeme/api)))

(quasischeme-api::ensure-psyntax)	; *HOST*, which analyze asks

(defvar *passed* 0)
(defvar *failed* 0)

(defun check (name ok)
  (if ok
      (incf *passed*)
      (progn (incf *failed*) (format t "~&FAIL ~A~%" name))))

(defun s (name) (qsx::sym name))

(defun core (tree)
  "TREE with its keywords and variables as the core's symbols: a symbol
named X becomes (sym \"x\")."
  (cond ((and (symbolp tree) tree) (s (string-downcase (symbol-name tree))))
	((consp tree) (cons (core (car tree)) (core (cdr tree))))
	(t tree)))

(defun commonize (tree)
  (let ((qsx::*cpcommonize-merges* 0))
    (values (qsx::cpcommonize (core tree)) qsx::*cpcommonize-merges*)))

(defun binders (letrec) (mapcar #'car (second letrec)))

;;; two procedures equal but for their variables' names: one binding
;;; left, and both calls go to it
(multiple-value-bind (out merges)
    (commonize '(letrec ((a (lambda (x) (car (cdr x))))
			 (b (lambda (y) (car (cdr y)))))
		  (list (a l) (b l))))
  (check "identical procedures merged" (= merges 1))
  (check "one binding kept" (equal (binders out) (list (s "a"))))
  (check "the dropped one's calls go to the kept one"
	 (equal (third out) (core '(list (a l) (a l))))))

;;; different bodies, or different free variables: nothing merged
(check "different bodies kept apart"
       (= 0 (nth-value 1 (commonize '(letrec ((a (lambda (x) (car x)))
					      (b (lambda (y) (cdr y))))
				       (list (a l) (b l)))))))
(check "different free variables kept apart"
       (= 0 (nth-value 1 (commonize '(letrec ((a (lambda (x) (p x)))
					      (b (lambda (y) (q y))))
				       (list (a l) (b l)))))))

;;; nested binders renamed in order: equal up to the inner names too
(check "nested lambdas compared up to their binders"
       (= 1 (nth-value 1 (commonize '(letrec ((a (lambda (x) ((lambda (u) (car u)) x)))
					      (b (lambda (y) ((lambda (v) (car v)) y))))
				       (list (a l) (b l)))))))

;;; a sibling's reference to the dropped procedure is rewritten too
(multiple-value-bind (out merges)
    (commonize '(letrec ((a (lambda (x) (car x)))
			 (b (lambda (y) (car y)))
			 (c (lambda (z) (b z))))
		  (c l)))
  (check "sibling's reference rewritten"
	 (and (= merges 1)
	      (equal (second (find (s "c") (second out) :key #'car))
		     (core '(lambda (z) (a z)))))))

;;; a letrec in an operator lambda, ((lambda ...) ...), is reached
(check "letrec inside an operator lambda merged"
       (= 1 (nth-value 1 (commonize '((lambda (k)
					(letrec ((a (lambda (x) (car x)))
						 (b (lambda (y) (car y))))
					  (list (a k) (b k))))
				      l)))))

;;; a procedure that assigns, or a variable assigned: left alone
(check "an assigning procedure not merged"
       (= 0 (nth-value 1 (commonize '(letrec ((a (lambda (x) (set! k x)))
					      (b (lambda (y) (set! k y))))
				       (list (a 1) (b 2)))))))

;;; a name bound twice: the form is left as it is
(let ((form '(letrec ((a (lambda (x) (car x)))
		      (b (lambda (x) (car x))))
	      (list (a l) (b l)))))
  (check "a name bound twice: unchanged"
	 (multiple-value-bind (out merges) (commonize form)
	   (and (= merges 0) (equal out (core form))))))

;;; end to end: a program with duplicate procedures runs as before
(check "a program's duplicates run the same"
       (equal (r7rs:eval "(import (scheme base))
			  (letrec ((f (lambda (l) (if (pair? l) (+ (car l) (f (cdr l))) 0)))
				   (g (lambda (l) (if (pair? l) (+ (car l) (f (cdr l))) 0))))
			    (list (f '(1 2 3)) (g '(4 5 6))))")
	      '(6 15)))

(format t "~&Optimizer: ~D of ~D tests passed.~%" *passed* (+ *passed* *failed*))
(uiop:quit (if (zerop *failed*) 0 1))

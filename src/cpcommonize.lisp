;;;; cpcommonize: merge letrec-bound procedures that are the same
;;;; procedure in everything but their variables' names.
;;;;
;;;; Two sources of the duplicates: a macro that expands to (define
;;;; (name a b) (op a b)) instantiated twice for the same op (Chez's
;;;; own example), and cp0's inlining of a procedure of several calls,
;;;; each copy of the body renamed separately.  After the merge the
;;;; bodies' code exists once, and every reference goes to one lambda:
;;;; less code for cpletrec and the translator to walk, one function
;;;; for the Lisp compiler.
;;;;
;;;; The comparison is by a canonical form: each lambda's bound
;;;; variables are renamed, depth first, to G$0, G$1, ... in order of
;;;; binding, so two lambdas that differ only in their binders' fresh
;;;; names get the same key, and free variables and constants are left
;;;; as they are.  (Plain EQUAL on the lambda won't do: psyntax renames
;;;; every binder.)  Where the keys match, the first variable is kept
;;;; and the others' bindings are deleted, their references (which may
;;;; be in sibling letrec lambdas) rewritten to the kept one.  The
;;;; procedures' eq?-identity changes, as it does in Chez's cpcommonize
;;;; and in cp0's own inlining; a program that distinguishes two
;;;; procedure values by eq? was never portable.
;;;;
;;;; A lambda whose name is marked (name-marker-p, a :procedure-name
;;;; marker for backtraces) keeps its name, so marked lambdas are never
;;;; merged.  A form is compared only when analyze holds for it (each
;;;; name bound exactly once form-wide, nothing assigned that the
;;;; canonical form would have to agree on), so the rewriting is
;;;; unambiguous.
;;;;
;;;; QUASISCHEME_CPCOMMONIZE=0 turns the pass off; the merges are
;;;; counted in *CPCOMMONIZE-MERGES*.

(in-package "QUASISCHEME-PSYNTAX")

(defvar *cpcommonize* (not (equal (uiop:getenv "QUASISCHEME_CPCOMMONIZE") "0"))
  "False to skip CPCOMMONIZE (optimize-core, src/cp0.lisp).")

(defparameter *cpcommonize-size-limit* 4000
  "The largest form, in conses, that cpcommonize analyzes.")

(defparameter *cpcommonize-depth-limit* 200
  "The deepest nesting the canonicalizer walks before giving up.")

;;; ------------------------------------------------------------------
;;; The canonical form: a lambda with its binders renamed in order

(defvar *canonical-renames* nil
  "During canonicalization, an alist of (original . canonical) of the
bound variables in scope.")

(defvar *canonical-count* 0
  "The next canonical index.")

(defvar *canonical-depth* 0)

(defun canonical-name (n) (sym (format nil "G$~D" n)))

(defun canonical-bind (vars)
  "Bind VARS, extending *CANONICAL-RENAMES*, and return their renamed
list.  A variable the form binds a second time shadows the first, as it
shadows in the form; analyze has already given up on such a form, so
each name is bound once."
  (let ((renamed '()))
    (dolist (v vars)
      (let ((canonical (canonical-name *canonical-count*)))
	(incf *canonical-count*)
	(push (cons v canonical) *canonical-renames*)
	(push canonical renamed)))
    (nreverse renamed)))

(defun canonicalize (e)
  "E with each bound variable renamed to the canonical name of its
binding position, depth first: two lambdas equal but for their binders'
names get equal canonical forms.  Free variables and constants are
unchanged.  Anything this pass doesn't model bails."
  (incf *canonical-depth*)
  (when (> *canonical-depth* *cpcommonize-depth-limit*) (cp-bail "cpcommonize"))
  (let ((result
	  (cond ((symbolp e)
		 (let ((rename (assoc e *canonical-renames*)))
		   (if rename (cdr rename) e)))
		((atom e) e)
		(t (case (cp-keyword (car e))
		     (:quote e)
		     (:lambda
		       (let* ((*canonical-renames* *canonical-renames*))
			 (list* (car e) (canonical-bind (formals-list (cadr e)))
				(mapcar #'canonicalize (cddr e)))))
		     ((:letrec :letrec*)
		       (let* ((*canonical-renames* *canonical-renames*))
			 (list* (car e)
				(mapcar (lambda (b)
					  (list (canonical-bind (list (car b)))
						(canonicalize (cadr b))))
					(cadr e))
				(mapcar #'canonicalize (cddr e)))))
		     ;; a keyword's form, or a call: its operator walked too
		     ;; (a variable, or a lambda)
		     (otherwise (if (cp-keyword (car e))
				    (cons (car e) (mapcar #'canonicalize (cdr e)))
				    (mapcar #'canonicalize e))))))))
    (decf *canonical-depth*)
    result))

(defun commonize-key (lambda)
  "LAMBDA's canonical form, or NIL if it can't be compared (it assigns
something, or its name is marked, or the walk gave up)."
  (when (and (cp-lambda-p lambda)
	     (proper-list-p (cadr lambda))	; a fixed parameter list
	     (not (assigned-lambda-p lambda))
	     (not (lambda-name-marker lambda)))
    (let ((*canonical-renames* '()) (*canonical-count* 0) (*canonical-depth* 0))
      (catch 'cp-bail
	(return-from commonize-key (canonicalize lambda)))
      nil)))

;;; ------------------------------------------------------------------
;;; The pass

(defun lambda-name-marker (e)
  "E's :procedure-name marker, if its body is just one."
  (let ((body (cddr e)))
    (and (= (length body) 1)
	 (consp (car body))
	 (eq (cp-keyword (car (car body))) :begin)
	 (= (length (car body)) 2)
	 (name-marker-p (cadr (car body)))
	 (cadr (car body)))))

(defun assigned-lambda-p (lambda)
  "Whether LAMBDA assigns any variable: its body's (set! ...) forms.
Merging two procedures whose bodies assign different variables is
harmless (each call still has its own), but the canonical form must
then treat assigned variables as free to be sound; unassigned is the
common case, and all cp0 merges now."
  (let ((found nil))
    (labels ((walk (x)
	       (cond ((atom x))
		     ((eq (cp-keyword (car x)) :quote))
		     ((eq (cp-keyword (car x)) :set!) (setq found t))
		     (t (loop for y on (cdr x) do (walk (car y)) while (consp (cdr y)))))))
      (mapc #'walk (cddr lambda))
      found)))

(defun comparable-binder-p (binder)
  "BINDER, (v (lambda ...)), one cpcommonize can compare: an unassigned
lambda variable whose lambda has a fixed parameter list, nothing
assigned in it, and no name marker, in a form whose variables are all
bound once (analyze held)."
  (and (consp binder) (consp (cdr binder)) (consp (cadr binder))
       (cp-lambda-p (cadr binder))
       (symbolp (car binder)) (proper-list-p (cadr (cadr binder)))
       (not (assigned-p (car binder)))
       (not (assigned-lambda-p (cadr binder)))
       (not (lambda-name-marker (cadr binder)))))

(defun cpcommonize-letrec (e)
  "E, a (letrec (binders...) body...), with the identical procedures'
bindings merged: the later ones deleted, their references rewritten to
the first variable.  Returns the letrec and the count of bindings
removed (two values)."
  (let* ((binders (cadr e))
	 (keep (make-hash-table :test #'equal))
	 (renames '()))
    (dolist (b binders)
      (when (comparable-binder-p b)
	(let ((key (commonize-key (cadr b))))
	  (when key
	    (let ((kept (gethash key keep)))
	      (if kept
		  (push (cons (car b) kept) renames)
		  (setf (gethash key keep) (car b))))))))
    (if (null renames)
	(values e 0)
	(let* ((renames (nreverse renames))
	       (drop-vars (mapcar #'car renames))
	       (new-binders
		 ;; the dropped bindings go; the kept lambdas' bodies may
		 ;; call a dropped sibling, so they're rewritten too
		 (loop for b in binders
		       unless (member (car b) drop-vars)
			 collect (if (cp-lambda-p (cadr b))
				     (list (car b)
					   (rename-references (cadr b) renames))
				     b)))
	       (body (mapcar (lambda (x) (rename-references x renames)) (cddr e))))
	  (values (list* (car e) new-binders body) (length drop-vars))))))

(defun rename-references (e renames)
  "E with its free references to RENAMES' keys replaced; a binder of E
shadows them."
  (if (null renames)
      e
      (flet ((shadowing (vars)
	       (remove-if (lambda (r) (member (car r) vars)) renames)))
	(cond ((symbolp e)
	       (let ((r (assoc e renames)))
		 (if r (cdr r) e)))
	      ((atom e) e)
	      (t (case (cp-keyword (car e))
		   (:quote e)
		   (:lambda
		     (let ((renames (shadowing (formals-list (cadr e)))))
		       (list* (car e) (cadr e)
			      (mapcar (lambda (x) (rename-references x renames))
				      (cddr e)))))
		   ((:letrec :letrec*)
		     (let ((renames (shadowing (mapcar #'car (cadr e)))))
		       (list* (car e)
			      (mapcar (lambda (b)
					(list (car b)
					      (rename-references (cadr b) renames)))
				      (cadr e))
			      (mapcar (lambda (x) (rename-references x renames))
				      (cddr e)))))
		   (otherwise (let ((rest (mapcar (lambda (x) (rename-references x renames)) (cdr e))))
				(if (cp-keyword (car e))
				    (cons (car e) rest)
				    (cons (rename-references (car e) renames) rest))))))))))

(defun cpcommonize-walk (e)
  "E with every letrec's duplicate procedure bindings merged; the
count is the second value."
  (cond ((atom e) (values e 0))
	(t (case (cp-keyword (car e))
	     (:quote (values e 0))
	     (:lambda
	       ;; only letrec binders are merged; a lambda's own letrecs
	       ;; are merged by walking its body
	       (multiple-value-bind (body n) (cpcommonize-walk-forms (cddr e))
		 (values (list* (car e) (cadr e) body) n)))
	     ((:letrec :letrec*)
	       (multiple-value-bind (binders n1) (cpcommonize-walk-binders (cadr e))
		 (multiple-value-bind (body n2) (cpcommonize-walk-forms (cddr e))
		   (multiple-value-bind (e2 n3)
		       (cpcommonize-letrec (list* (car e) binders body))
		     (values e2 (+ n1 n2 n3))))))
	     ;; a keyword's form, or a call: a lambda operator walked too
	     (otherwise (multiple-value-bind (all n)
			    (cpcommonize-walk-forms (if (cp-keyword (car e)) (cdr e) e))
			  (values (if (cp-keyword (car e)) (cons (car e) all) all) n)))))))

(defun cpcommonize-walk-forms (forms)
  "FORMS, each walked, and the total merged count."
  (let ((n 0))
    (values (mapcar (lambda (f)
		      (multiple-value-bind (f2 k) (cpcommonize-walk f)
			(incf n k) f2))
		    forms)
	    n)))

(defun cpcommonize-walk-binders (binders)
  "Each binder's init walked in place, and the total count."
  (let ((n 0))
    (values (mapcar (lambda (b)
		      (if (and (consp b) (consp (cdr b)))
			  (multiple-value-bind (x k) (cpcommonize-walk (cadr b))
			    (incf n k)
			    (list (car b) x))
			  b))
		    binders)
	    n)))

(defvar *cpcommonize-merges* 0
  "The bindings cpcommonize has merged, for the optimizer's stats.")

(defun cpcommonize (e)
  "The whole form, its identical letrec procedures merged.  Keeps the
unmerged form on a form too big to analyze, and when analyze gives up
on it (a variable bound twice, a form this pass doesn't model)."
  (unless (and *cpcommonize* (<= (tree-size e) *cpcommonize-size-limit*))
    (return-from cpcommonize e))
  (catch 'cp-bail
    (let ((out (analyze-and-walk e)))
      (when (> (cdr out) 0)
	(incf *cpcommonize-merges* (cdr out)))
      (return-from cpcommonize (car out))))
  e)

(defun analyze-and-walk (e)
  "FORM analyzed (cp0's), then walked; a cons of the walked form
and the merge count, bailing (CP-BAIL) where analyze does, or where a
name is bound twice."
  (let ((*vi* (make-hash-table :test 'eq)))
    (analyze e)
    (unless (unique-binders-p) (cp-bail "names not unique"))
    (multiple-value-bind (out n) (cpcommonize-walk e)
      (cons out n))))

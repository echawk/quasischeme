; -*- Mode: Lisp; Syntax: Common-Lisp; Package: SB-C -*-

;;;; SBCL's compiler, as it compiles big generated code.
;;;;
;;;; SB-C::SELECT-TAGGING (src/compiler/select-tagging.lisp, SBCL 2.6.9,
;;;; sbcl/sbcl at tag sbcl-2.6.9) and SB-C::MAP-ALL-DESTS (ir1util.lisp),
;;;; which it calls for every reference of every variable an argument
;;;; flows from, keep what they have seen in lists searched with MEMQ: a
;;;; function of a few thousand local functions (a macro's expansion,
;;;; INTERCAL's programs through Racket's intercal) took minutes there, 90%
;;;; of the time in MEMQ.  The same algorithms with sets that become hash
;;;; tables as they grow; nothing else changes.  Only where SBCL's
;;;; functions take the arguments the copies do and what they call is
;;;; there (2.6.9's source is what they follow).

#+sbcl
(in-package "SB-C")

;;; (SB-C is locked: unlocked while this file compiles and loads)
#+sbcl
(eval-when (:compile-toplevel :load-toplevel :execute)
  (sb-ext:unlock-package "SB-C"))

#+sbcl
(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; SBCL's macros these use, which its build has but its image doesn't
  ;; (src/compiler/macros.lisp): DO-BLOCKS without ENDS, DO-NODES without
  ;; RESTART-P, POSITION-OR-LOSE; and the mv-let functional kind's bit,
  ;; which FUNCTIONAL-KIND-EQ tests
  (defmacro qs-do-blocks ((block-var component) &body body)
    (let ((n-component (gensym)) (n-tail (gensym)))
      `(let* ((,n-component ,component)
	      (,n-tail (component-tail ,n-component)))
	 (do ((,block-var (block-next (component-head ,n-component)) (block-next ,block-var)))
	     ((eq ,block-var ,n-tail) nil)
	   ,@body))))
  (defmacro qs-do-nodes ((node-var block) &body body)
    (let ((n-block (gensym)) (n-start (gensym)))
      `(do* ((,n-block ,block)
	     (,n-start (block-start ,n-block))
	     (,node-var (ctran-next ,n-start)
			(let ((next (node-next ,node-var)))
			  (if next (ctran-next next) (return)))))
	    (nil)
	 ,@body)))
  (defmacro qs-position-or-lose (&rest args)
    `(or (position ,@args) (error "shouldn't happen?")))
  (defparameter *qs-tagging-limit* 2000
    "The most tagged-or-untagged choices SELECT-TAGGING analyses in a component.")
  (defparameter *qs-mv-let-kind*
    (loop for i below 32
	  when (equal (decode-functional-kind-attributes (ash 1 i)) '(mv-let))
	    return (ash 1 i))))

#+sbcl
(when (and *qs-mv-let-kind*
	   ;; the two functions as this file's copies follow them, and what
	   ;; the copies call, whatever the release
	   (equal (mapcar #'princ-to-string (sb-kernel:%fun-lambda-list #'map-all-dests))
		  '("FUNCTION" "NODE" "&OPTIONAL" "(NTH-VALUE 0)"))
	   (equal (mapcar #'princ-to-string (sb-kernel:%fun-lambda-list #'select-tagging))
		  '("COMPONENT"))
	   (every (lambda (name) (let ((s (find-symbol name "SB-C"))) (and s (fboundp s))))
		  '("ADD-EDGE" "COMBINATION-ARG-TEMPLATE-POSITION" "COMBINATION-INFO"
		    "FUNCTIONAL-KIND" "LAMBDA-VARS" "LEAF-REFS" "LVAR-DEST" "LVAR-FUN-IS"
		    "MAKE-NET" "MAP-ALL-USES" "MIN-CUT" "NET-TABLE" "NET-TO"
		    "TAGGED-TEMPLATE-ARG-P" "TAGGED-TEMPLATE-RESULTS-P" "VOP-INFO-P"
		    "VOP-INFO-RELATED-ARGS")))
  (sb-ext:without-package-locks
    (handler-bind ((warning #'muffle-warning))
      (macrolet ((with-seen-set ((member-p note) &body body)
		   ;; MEMBER-P and NOTE on a set of objects: a list, made a hash
		   ;; table past 32 members
		   (let ((list (gensym "LIST")) (table (gensym "TABLE")) (n (gensym "N")))
		     `(let ((,list '()) (,table nil) (,n 0))
			(declare (fixnum ,n))
			(flet ((,member-p (x)
				 (if ,table (gethash x ,table) (memq x ,list)))
			       (,note (x)
				 (cond (,table (setf (gethash x ,table) t))
				       ((< ,n 32) (push x ,list) (incf ,n))
				       (t (setf ,table (make-hash-table :test 'eq))
					  (dolist (y ,list) (setf (gethash y ,table) t))
					  (setf (gethash x ,table) t)))))
			  (declare (ignorable #',member-p #',note))
			  ,@body)))))

	(defun map-all-dests (function node &optional (nth-value 0))
	  (declare (dynamic-extent function))
	  (with-seen-set (seen-p note-seen)
	    (labels ((call (node lvar nth-value)
		       (let ((continue (funcall function node lvar nth-value)))
			 (when continue
			   (when (valued-node-p node)
			     (recurse node (if (eq continue t)
					       0
					       continue))))))
		     (recurse-node (node lvar nth-value)
		       (cond ((and (combination-p node)
				   ;; Only the first value is used
				   (and nth-value
					(> nth-value 0))))
			     ((and (basic-combination-p node)
				   (eq (basic-combination-kind node) :local)
				   (not (seen-p node)))
			      (note-seen node)
			      (let ((fun (combination-lambda node)))
				(flet ((map-var (var)
					 (loop for ref in (leaf-refs var)
					       do
					       (recurse ref 0))))
				  (if (logtest (functional-kind fun) *qs-mv-let-kind*)
				      (if nth-value
					  (map-var (or (nth nth-value (lambda-vars fun))
						       (return-from recurse-node)))
					  (mapc #'map-var (lambda-vars fun)))
				      (map-var
				       (nth (qs-position-or-lose lvar
							      (basic-combination-args node))
					    (lambda-vars fun)))))))
			     ((and (combination-p node)
				   (lvar-fun-is (combination-fun node) '(values)))
			      (let* ((next-lvar (node-lvar node))
				     (next-dest (and next-lvar
						     (lvar-dest next-lvar))))
				(when next-dest
				  (recurse-node next-dest next-lvar
						(position lvar (combination-args node))))))
			     (t
			      (call node lvar nth-value))))
		     (recurse (node nth-value)
		       (let ((lvar (node-lvar node)))
			 (when lvar
			   (let ((dest (lvar-dest lvar)))
			     (recurse-node dest lvar nth-value))))))
	      (recurse node nth-value))))

	(defun select-tagging (component)
	  ;; a component with more choices than *QS-TAGGING-LIMIT*: each the
	  ;; tagged VOP, as the min cut makes it for a node on the tagged
	  ;; side (the analysis walks each choice's variables' references,
	  ;; quadratic in the component's size)
	  (let ((choices '()))
	    (qs-do-blocks (block component)
	      (qs-do-nodes (node block)
		(when (and (combination-p node) (consp (combination-info node)))
		  (push node choices))))
	    (when (> (length choices) *qs-tagging-limit*)
	      (dolist (node choices)
		(setf (combination-info node) (first (combination-info node))))
	      (return-from select-tagging nil)))
	  (let ((net (make-net)))
	    (qs-do-blocks (block component)
	      (qs-do-nodes (node block)
		(when (and (combination-p node)
			   (consp (combination-info node)))
		  (with-seen-set (seen-var-p note-var)
		    (with-seen-set (seen-lvar-p note-lvar)
		      (flet ((add-lvar (lvar)
			       (add-edge net lvar node 10)
			       (add-edge net node lvar 10))
			     (read-costs (lvar node)
			       (cond ((constant-lvar-p lvar)
				      (values 0 0))
				     ((combination-p node)
				      (let ((template (combination-info node)))
					(cond ((atom template)
					       (if (vop-info-p template)
						   (tagged-template-arg-p (combination-arg-template-position lvar node)
									  (combination-info node))
						   (values 1 0)))
					      ((/= (vop-info-related-args (car template)) -1)
					       (let ((pos (combination-arg-template-position lvar node)))
						 (if (logbitp pos (vop-info-related-args (car template)))
						     (values 0 0)
						     (tagged-template-arg-p pos (car template)))))
					      (t
					       ;; Flexible VOP, no costs
					       (values 0 0)))))
				     (t
				      (values 1 0)))))
			(loop for related fixnum = (vop-info-related-args (car (combination-info node)))
			      then (ash related -1)
			      for arg in (combination-args node)
			      do
			      (unless (or (constant-lvar-p arg)
					  (not (logbitp 0 related)))
				(add-lvar arg)
				(note-lvar arg)
				(let ((tagged 0)
				      (untagged 0))
				  (declare (fixnum tagged untagged))
				  (map-all-uses (lambda (use)
						  (cond ((combination-p use)
							 (let ((template (combination-info use)))
							   (unless (consp template)
							     (if (and (vop-info-p template)
								      (not (tagged-template-results-p template)))
								 (incf untagged)
								 (incf tagged)))))
							(t
							 (incf tagged))))
						arg
						:var-home
						(lambda (var)
						  (unless (seen-var-p var)
						    (note-var var)
						    (loop for ref in (leaf-refs var)
							  for lvar = (node-lvar ref)
							  do (when (and lvar
									(not (constant-lvar-p lvar)))
							       (map-all-dests
								(lambda (dest lvar nth-value)
								  (declare (ignorable nth-value))
								  (unless (seen-lvar-p lvar)
								    (note-lvar lvar)
								    (multiple-value-bind (tag untag) (read-costs lvar dest)
								      (incf tagged tag)
								      (incf untagged untag))
								    nil))
								ref))))))
				  (when (> tagged 0)
				    (add-edge net :source arg (* tagged 10)))
				  (when (> untagged 0)
				    (add-edge net arg :sink (* untagged 10))))))
			(let ((tagged 0)
			      (untagged 0)
			      (result (node-lvar node)))
			  (declare (fixnum tagged untagged))
			  (add-lvar result)
			  (map-all-dests
			   (lambda (dest lvar nth-value)
			     (declare (ignorable lvar nth-value))
			     (multiple-value-bind (tag untag) (read-costs lvar dest)
			       (incf tagged tag)
			       (incf untagged untag))
			     nil)
			   node)
			  (when (> tagged 0)
			    (add-edge net :source result (* tagged 10)))
			  (when (> untagged 0)
			    (add-edge net result :sink (* untagged 10))))))))))
	    (when (> (length (net-to net)) 0)
	      (let ((tagged-p (min-cut net)))
		(loop for node being the hash-key of (net-table net)
		      do
		      (when (combination-p node)
			(let ((info (combination-info node)))
			  (aver (listp info))
			  (setf (combination-info node)
				(if (funcall tagged-p node)
				    (first info)
				    (second info))))))))))))))

#+sbcl
(eval-when (:compile-toplevel :load-toplevel :execute)
  (sb-ext:lock-package "SB-C"))

;;;; CLOSURE-INIT with a GC card mark, on arm64.
;;;;
;;;; IR2-CONVERT-ENCLOSE (sbcl/sbcl at tag sbcl-2.6.9,
;;;; src/compiler/ir2tran.lisp) makes every closure of a LABELS group,
;;;; each MAKE-CLOSURE an allocation a collection can follow, and only
;;;; then stores the closures in each other (the delayed CLOSURE-INITs).
;;;; arm64's CLOSURE-INIT (src/compiler/arm64/cell.lisp) stores without
;;;; the card mark that x86-64's makes: a closure promoted by a
;;;; collection between the allocations then holds younger closures the
;;;; next collection doesn't see, and frees.  Guile's reader, whose %read
;;;; makes a group of closures of 51 slots each call, corrupted the heap
;;;; after some 100,000 reads (heap_scavenge failure).  This is x86-64's
;;;; definition, on when the internals it uses are there.

#+(and sbcl arm64)
(eval-when (:compile-toplevel :load-toplevel :execute)
  (sb-ext:unlock-package "SB-VM")
  (when (and (find-symbol "EMIT-GENGC-BARRIER" "SB-VM")
	     (fboundp (find-symbol "EMIT-GENGC-BARRIER" "SB-VM"))
	     (find-symbol "CLOSURE-INIT" "SB-VM")
	     (ignore-errors (sb-c::template-or-lose (find-symbol "CLOSURE-INIT" "SB-VM"))))
    (pushnew :quasischeme-closure-init-barrier *features*)))

#+quasischeme-closure-init-barrier
(sb-ext:without-package-locks
  (handler-bind ((warning #'muffle-warning))
    (sb-vm::define-vop (sb-vm::closure-init)
      (:args (sb-vm::qs-closure :scs (sb-vm::descriptor-reg))
	     (sb-vm::qs-value :scs (sb-vm::descriptor-reg sb-vm::any-reg)))
      (:info sb-vm::qs-offset sb-vm::qs-dx)
      (:vop-var sb-vm::vop)
      (:generator 4
	(unless sb-vm::qs-dx
	  (sb-vm::emit-gengc-barrier sb-vm::qs-closure nil sb-vm::tmp-tn (sb-c::tn-ref-across (sb-c::vop-args sb-vm::vop))))
	(let ((disp (- (* (+ sb-vm:closure-info-offset sb-vm::qs-offset) sb-vm:n-word-bytes)
		       sb-vm:fun-pointer-lowtag)))
	  ;; STR's immediate offset is short, as STOREW knows: past it, in
	  ;; TMP-TN (which the barrier is done with)
	  (if (<= -256 disp 255)
	      (sb-assem:inst sb-vm::str sb-vm::qs-value (sb-vm::@ sb-vm::qs-closure disp))
	      (progn
		(sb-vm::load-immediate-word sb-vm::tmp-tn disp)
		(sb-assem:inst sb-vm::str sb-vm::qs-value (sb-vm::@ sb-vm::qs-closure sb-vm::tmp-tn)))))))))

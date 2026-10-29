;;;; Build bin/quasischeme: (load "build.lisp") from any Common Lisp
;;;; with ASDF.  contrib/cli/Makefile does this.

(require :asdf)

;; A build past QUASISCHEME_BUILD_TIME_LIMIT seconds (30 minutes) is
;; stopped with the main thread's backtrace, rather than left to run: a
;; compiler change that loops, or that leaves Guile's boot code to SBCL's
;; interpreter (QUASISCHEME_WARN_INTERPRETED, set here, names each such
;; form), shows where.  The watchdog stops before the image is saved.
#+sbcl
(let* ((limit (or (ignore-errors (parse-integer (uiop:getenv "QUASISCHEME_BUILD_TIME_LIMIT"))) 1800))
       (main sb-thread:*current-thread*)
       (watchdog (sb-thread:make-thread
		  (lambda ()
		    (sleep limit)
		    (format *error-output* "~&;; the build took more than ~D seconds (QUASISCHEME_BUILD_TIME_LIMIT), stopped~%" limit)
		    (finish-output *error-output*)
		    (sb-thread:interrupt-thread
		     main
		     (lambda ()
		       (sb-debug:print-backtrace :count 80 :stream *error-output*)
		       (finish-output *error-output*)
		       (sb-ext:exit :code 3 :abort t)))
		    ;; the compiler holds the world lock, which defers interrupts
		    (sleep 10)
		    (format *error-output* "~&;; (in the compiler: no backtrace)~%")
		    (finish-output *error-output*)
		    (sb-ext:exit :code 3 :abort t))
		  :name "build watchdog")))
  (labels ((stop ()
	     (setq sb-ext:*save-hooks* (remove #'stop sb-ext:*save-hooks*))
	     (sb-thread:terminate-thread watchdog)
	     (sb-thread:join-thread watchdog :default nil)))
    (push #'stop sb-ext:*save-hooks*))
  (setf (uiop:getenv "QUASISCHEME_WARN_INTERPRETED") "1"))

(let* ((here (make-pathname :name nil :type nil
			    :defaults (or *load-truename* *load-pathname*)))
       (root (merge-pathnames (make-pathname :directory '(:relative :up :up)) here)))
  (pushnew (truename root) asdf:*central-registry* :test #'equal)
  (pushnew (truename here) asdf:*central-registry* :test #'equal))

;; The dependencies (float-features, cl-unicode, ...) come from
;; Quicklisp when it's installed; QUICKLOAD fetches any that are missing.
(let ((setup (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (when (probe-file setup)
    (load setup)
    (uiop:symbol-call "QL" "QUICKLOAD" :quasischeme-cli :silent t)))

(handler-bind ((warning #'muffle-warning))
  (asdf:make :quasischeme-cli))

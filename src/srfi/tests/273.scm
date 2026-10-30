;;; SRFI 273 tests: the SRFI's test.scm (Artyom Bologov; MIT licence),
;;; its several test groups counted together, exiting 1 if one failed.
;;; Two of its definitions are in bodies with an expression after them:
;;; (test-error (define-values-checked ...)) is a body of a definition
;;; alone (an error in R7RS), and a program's failed top-level definition
;;; ends the program, where the test expects a REPL to go on.
(import (scheme base))
(import (scheme eval))
(import (scheme repl))
(import (srfi 64))
(import (srfi 253))
(import (srfi 273))
(import (scheme process-context))

(define-check email? string?)
(define-check positive-integer?
  (lambda (x) (and (integer? x) (positive? x))))

(define-syntax check-arg-true
  (syntax-rules ()
    ((_ pred val)
     (begin
       (check-arg pred val)
       #t))))

(test-begin "define-check")
(test-equal 3 3)
(test-assert (check-arg-true email? "srfi-273@srfi.schemers.org"))
(test-assert (check-arg-true positive-integer? 3))
(test-error (check-arg-true positive-integer? 0))
(test-error (check-arg-true positive-integer? -8))
;; Domain error
;; (test-error (define-check invalid 3))
(test-end "define-check")

(test-begin "define-values-checked")
(test-assert (begin
               (define-values-checked (quot rem) (integer? integer?)
                 (truncate/ 1 2))
               #t))
(test-assert (begin
               (define-values-checked (a) (real?) 3)
               #t))
(test-error (begin
              (define-values-checked (quot rem) (integer? string?)
                (truncate/ 1 2))
              #t))
(test-error (let () (define-values-checked (a) (string?) 3) #t))
;; Ensure that symbols are not bound on type mismatch: in a body, as a
;; program's failed top-level definition ends it
(test-error (let () (define-values-checked (x y) (integer? string?)
                      (truncate/ 1 2))
                    #t))
(test-error (eval 'x (interaction-environment)))
(test-error (eval 'y (interaction-environment)))
;; Test modifications, on implementations supporting that
;; (test-error (set! quot "not an integer"))
;; Syntax checks
;; (test-error (define-values-checked a (real?) 3))
;; (test-error (define-values-checked (a) real? 3))
;; (test-error (define-values-checked (a b) (real?) 3))
;; (test-error (define-values-checked (a) (real? integer?) 3 8))
(test-end "define-values-checked")

(define (hello x)
  (string-append "Hello, " x "!"))

(test-begin "declare-checked")
;; Post-declaration for standard symbols
(test-assert (begin
               (declare-checked (negative? (x real?)) => (boolean?))
               #t))
(test-assert (begin
               (declare-checked (call/cc (k procedure?)))
               #t))
;; Post-declaration for a new symbol.
;; Uncomment if supported
;; (test-assert (begin
;;                (declare-checked (hello (k string?)) => (string?))
;;                (hello "Stranger")))
;; (test-error (begin
;;                (declare-checked (hello (k string?)) => (integer?))
;;                (hello "Stranger")))
;; (test-error (begin
;;                (declare-checked (hello (k string?)) => (string?))
;;                (hello 5)))
(test-end "declare-checked")

(exit (if (zero? (test-runner-fail-count (test-runner-current))) 0 1))

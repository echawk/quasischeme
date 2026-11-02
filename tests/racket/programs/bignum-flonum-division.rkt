#lang racket/base
;; quotient, remainder and modulo of a bignum and a flonum are exact
;; divisions made inexact (converting the bignum first overflowed), and
;; set! of a module's constant is exn:fail:contract:variable.
(for ([op (list quotient remainder modulo)])
  (printf "~s\n" (list (op #e1e1000 1.0) (op #e1e1000 3.0) (op #e2e1000 3.0)
                       (op #e-1e1000 3.0) (op #e-2e1000 3.0) (op #e1e400 -7.0)
                       (op 7 2.0) (op -7 2.0))))
(parameterize ([current-namespace (make-base-namespace)])
  (eval '(module c racket/base (define f 1)))
  (eval '(require 'c))
  (with-handlers ([exn:fail:contract:variable? (lambda (e) (displayln (exn-message e)))])
    (parameterize ([current-namespace (module->namespace ''c)])
      (eval '(set! f 2)))))
(define (t f) (with-handlers ([(lambda (e) #t) (lambda (e) (list 'err (if (exn? e) (exn-message e) e)))]) (f)))
(for ([th (list (lambda () (make-polar 1/2 0)) (lambda () (make-polar 1.0 0)) (lambda () (make-polar +inf.0 0))
                (lambda () (string->number "1/2@0")) (lambda () (expt 0 -1)) (lambda () (expt 0 -1/2))
                (lambda () (expt 1/2 -2)) (lambda () (expt 2 0.5)))])
  (printf "~s\n" (t th)))
;; one argument: true of a number, as Racket's
(require racket/fixnum racket/flonum)
(define (t2 f) (with-handlers ([exn:fail? (lambda (e) 'err)]) (f)))
(list (< 100) (apply < '(1)) (= 1) (>= 2.5) (t2 (lambda () (apply < '(a)))) (fx< 1) (fl< 1.0) (apply max '(3)) (< 1 2 3) (< 1 3 2))

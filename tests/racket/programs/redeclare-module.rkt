#lang racket/base
;; A module declared again: allowed when compile-enforce-module-constants
;; is #f as its linklets are compiled (none of its definitions is then a
;; constant, as schemify decides), refused when it is #t.
(define ns (make-base-namespace))
(define (try enforce)
  (parameterize ([current-namespace (make-base-namespace)]
                 [compile-enforce-module-constants enforce])
    (with-handlers ([exn:fail? (lambda (e) (car (regexp-split #rx"\n" (exn-message e))))])
      (eval '(module m racket/base (define x 1) (provide x)))
      (eval '(require 'm))
      (eval '(module m racket/base (define x 2) (provide x)))
      (eval 'x))))
(displayln (try #f))
(displayln (try #t))

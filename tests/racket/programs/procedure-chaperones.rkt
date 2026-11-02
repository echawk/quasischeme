#lang racket/base
;; Procedure chaperones and arities as Racket's: an applicable struct's
;; chaperone is a struct of its type; a chaperoned accessor chaperones a
;; struct; required keywords make an arity incomplete through prop:procedure.
(struct wrap (v) #:property prop:procedure 0)
(define (f1+:a x #:a [a 0]) (list x a))
(displayln ((chaperone-procedure (wrap f1+:a) (make-keyword-procedure (lambda (kws kw-args . rest) (if (null? kws) (apply values rest) (apply values kw-args rest))))) 1 #:a 2))
(displayln ((chaperone-procedure (wrap (lambda (x) x)) (lambda (x) x)) 5))
(define-struct a (x [y #:mutable]) #:property prop:procedure 0)
(define a1 (make-a (lambda (x) (list x x)) 10))
(define get #f)
(define a2 (chaperone-struct a1 a-y (lambda (a v) (set! get v) v) set-a-y! (lambda (a v) v)))
(define pre #f)
(define a3 (chaperone-procedure a2 (lambda (z) (set! pre z) (values (lambda (r) r) z))))
(define a4 (chaperone-struct a3 a-y (lambda (a v) (set! get (list 'a4 v)) v) set-a-y! (lambda (a v) v)))
(list (a? a3) (procedure? a3) (a3 12) pre (a-y a3) get (a4 5) (a-y a4) get (chaperone-of? a3 a1))
(define (f1:a x #:a a) x)
(define (wrap-m f) (struct wrap-m () #:property prop:procedure f) (wrap-m))
(list (procedure-arity-includes? (wrap-m f1:a) 1) (procedure-arity-includes? (wrap-m f1:a) 1 #t))
(define p (wrap f1:a))
(call-with-values (lambda () (procedure-keywords p)) list)
(procedure-arity p)
(procedure-extract-target p)

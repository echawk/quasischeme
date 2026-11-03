#lang racket/base
(require (only-in '#%unsafe unsafe-impersonate-hash))
(define h (make-hash '((a . 1))))
(define f (unsafe-impersonate-hash #f h (lambda (h k) (values k (lambda (h k v) v))) (lambda (h k v) (values k v)) (lambda (h k) k) (lambda (h k) k)))
(displayln (hash-ref f 'a))
(hash-set! f 'b 2)
(displayln (hash-ref h 'b))

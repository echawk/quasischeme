#lang racket/base
;; A continuation re-entering a module body re-defines its variables:
;; one never set! is a constant, and Racket raises, as upstream does
;; ("define-values: assignment disallowed; cannot re-define a constant").
;; A native override of a core definition (map2) must not trip this.
(error-display-handler
 (lambda (msg e)
   ;; the module's name is its path: the file name only
   (displayln (regexp-replace #rx"in module:\"[^\"]*/" msg "in module:\""))))
(define k #f)
(define count 0)
(define v (+ 1 (call/cc (lambda (c) (set! k c) 1))))
(set! count (+ count 1))
(displayln (list v count (map (lambda (x y) (+ x y)) '(1 2) '(3 4))))
(when (< count 3) (k count))
(displayln 'end)

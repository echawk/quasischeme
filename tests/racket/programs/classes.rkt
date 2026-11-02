#lang racket
;; racket/class: methods, fields, overriding with super, inner, mixins.
;; A class's methods refer to its object through a gensym (class.rkt's
;; self), which compiled code quotes: compiled through a file, it lost
;; its identity ("self3327: unbound identifier" at super).
(define c% (class object% (super-new) (define/public (m x) (+ x 1)) (init-field [y 2]) (define/public (g) y)))
(define o (new c%))
(displayln (list (send o m 1) (send o g)))
(define d% (class c% (super-new) (define/override (m x) (* 10 (super m x)))))
(displayln (send (new d%) m 1))
(define a% (class object% (super-new) (define/pubment (h) (list 'a (inner 'none h)))))
(define b% (class a% (super-new) (define/augment (h) 'b)))
(displayln (send (new b%) h))
(define (mix %) (class % (super-new) (define/public (twice x) (* 2 (send this m x)))))
(displayln (send (new (mix d%)) twice 1))
(displayln (is-a? (new d%) c%))

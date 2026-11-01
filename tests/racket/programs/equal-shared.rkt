#lang racket/base
;; equal? on widely shared and on cyclic data ends, in linear time, as
;; Racket CS's does (union-find past a budget): this tree is 100 levels
;; of 100 references to one subtree, and walking it is 100^100 steps.
(define (make-list1 n x) (if (zero? n) '() (cons x (make-list1 (- n 1) x))))
(define (make-tree1 n) (if (zero? n) '() (make-list1 n (make-tree1 (- n 1)))))
(displayln (equal? (make-tree1 100) (make-tree1 100)))
(displayln (equal? (make-tree1 100) (make-list1 100 (make-tree1 98))))
(define (cycle v) (let ([b (box #f)]) (set-box! b (vector v b)) b))
(displayln (equal? (cycle 1) (cycle 1)))
(displayln (equal? (cycle 1) (cycle 2)))
(define (mcycle) (let ([p (mcons 1 #f)]) (set-mcdr! p (mcons 1 p)) p))
(displayln (equal? (mcycle) (mcycle)))

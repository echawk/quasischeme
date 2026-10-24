#lang racket/base
;; Futures (src/racket/native/threads.lisp): in parallel on lparallel's
;; workers, blocking at a future-unsafe operation until touched
(require racket/future)
(define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))
(printf "enabled ~a\n" (futures-enabled?))
(define fs (for/list ([i 4]) (future (lambda () (fib 25)))))
(printf "results ~a\n" (map touch fs))
;; output in a future happens at its touch, in order
(define g (future (lambda () (printf "in future\n") 42)))
(printf "before touch\n")
(printf "touched ~a\n" (touch g))
;; an exception surfaces at touch
(printf "caught ~a\n"
        (with-handlers ([exn:fail? (lambda (e) (exn-message e))])
          (touch (future (lambda () (car 5))))))
(define-values (a b) (touch (future (lambda () (values 1 2)))))
(printf "values ~a ~a\n" a b)
(printf "current ~a ~a\n" (current-future) (future? (touch (future (lambda () (current-future))))))
(printf "would-be ~a\n" (touch (would-be-future (lambda () 7))))
(printf "nested ~a\n" (touch (future (lambda () (touch (future (lambda () (fib 20))))))))
(define s (make-fsemaphore 0))
(define p (future (lambda () (fsemaphore-wait s) 'got)))
(fsemaphore-post s)
(printf "fsemaphore ~a ~a\n" (touch p) (fsemaphore-count s))
(define prm (make-parameter 1))
(printf "parameter ~a\n" (parameterize ([prm 9]) (touch (future (lambda () (prm))))))

#lang racket/base
;; Continuations as Racket's: escape ones are continuation?, call/cc's are
;; delimited by the nearest prompt of their tag (racket/control's shift and
;; abort/keep-prompt), and call-in-continuation calls in the continuation.
(require racket/control)
(define ks (list (call/cc values) (call/ec values) (let/ec k k) (let/cc k k)
                 (call-with-composable-continuation values)
                 (call-with-escape-continuation values)
                 (call-with-current-continuation (lambda (k) k) (default-continuation-prompt-tag))
                 (call-with-continuation-prompt (lambda () (call/cc values (default-continuation-prompt-tag))))
                 (call-with-continuation-prompt (lambda () (call-with-composable-continuation values)))))
(for ([k ks] [i (in-naturals)])
  (printf "~a ~a ~a ~a\n" i (continuation? k) (procedure? k)
          (with-handlers ([exn? (lambda (e) 'err)]) (continuation-mark-set? (continuation-marks k)))))
(displayln (+ 10 (reset (+ 2 (shift k (+ 100 (k (k 3))))))))
(displayln (* 10 (reset (* 2 (shift g (reset (* 5 (shift f (+ (f 1) 1)))))))))
(define tag (make-continuation-prompt-tag))
(displayln (call-with-continuation-prompt
            (lambda () (+ 1 (call-in-continuation
                             (call-with-continuation-prompt (lambda () (call/cc values tag)) tag)
                             (lambda () 41))))
            tag))
(displayln (call-with-continuation-prompt
            (lambda () (list 'in (call/cc (lambda (k) (k 'out)) tag)))
            tag))

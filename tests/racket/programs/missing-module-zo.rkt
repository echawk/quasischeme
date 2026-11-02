#lang racket/base
;; A missing module's file is exn:fail:filesystem:missing-module, as the
;; io layer raises it for open-input-file's 'module mode; and compiled
;; code quoting an fxvector or flvector writes and reads back.
(require racket/fixnum racket/flonum)
(with-handlers ([exn:fail:filesystem:missing-module?
                 (lambda (e) (displayln (car (regexp-split #rx"\n" (exn-message e)))))])
  (dynamic-require 'racket/base/no-such-module #f))
(define (round-trip e)
  (define o (open-output-bytes))
  (write (compile e) o)
  (parameterize ([read-accept-compiled #t])
    (eval (read (open-input-bytes (get-output-bytes o))))))
(current-namespace (make-base-namespace))
(displayln (round-trip `(quote ,(fxvector 1 2 3 -100))))
(displayln (round-trip `(quote ,(flvector 1.5 -2.0))))
(write (fxvector 1 2)) (newline)
(print (list (fxvector 3) (flvector 0.5))) (newline)

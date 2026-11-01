#lang racket/base
;; object-name and procedure-arity-mask as Racket CS gives them: a keyword
;; procedure by its own procedure, a primitive by its name, a primitive's
;; arity as its table says (not its lambda list's).
(define (kf a #:x [x 1]) (+ a x))
(define kf2 (lambda (#:y y) y))
(struct s (a) #:property prop:object-name 0)
(for ([p (list kf kf2 (s 'named) open-input-file with-output-to-file sort make-parameter
               (procedure-rename car 'kar))])
  (printf "~s\n" (object-name p)))
(for ([p (list string-copy make-parameter string->number car + vector-ref)])
  (printf "~a ~a\n" (object-name p) (procedure-arity-mask p)))

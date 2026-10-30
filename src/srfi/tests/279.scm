;;; SRFI 279 tests (the sample ships none): the properties the SRFI
;;; lists for a few types, as the sample implementation's generic.scm
;;; gives them, non-dotted alists, and inspect-property's two values.
(import (scheme base) (scheme write) (scheme process-context)
        (srfi 64) (srfi 279))

(test-begin "srfi-279")

(define (non-dotted-alist? x)
  (and (list? x) (every-entry? x)))
(define (every-entry? x)
  (or (null? x) (and (pair? (car x)) (pair? (cdar x)) (every-entry? (cdr x)))))

(test-assert "number" (non-dotted-alist? (inspect-properties 42)))
(test-assert "pair" (non-dotted-alist? (inspect-properties '(1 2 3))))
(test-assert "string" (non-dotted-alist? (inspect-properties "abc")))
(test-assert "symbol" (non-dotted-alist? (inspect-properties 'abc)))
(test-assert "vector" (non-dotted-alist? (inspect-properties (vector 1 2))))
(test-assert "procedure" (non-dotted-alist? (inspect-properties car)))

(let-values (((v found) (inspect-property 3/4 'numerator)))
  (test-equal "numerator" 3 v)
  (test-assert "numerator found" found))
(let-values (((v found) (inspect-property 3/4 'denominator)))
  (test-equal "denominator" 4 v))
(let-values (((v found) (inspect-property 255 'display-16)))
  (test-equal "display-16" "ff" v))
(let-values (((v found) (inspect-property "abc" 'string-length)))
  (test-equal "string-length" 3 v))
(let-values (((v found) (inspect-property '(1 2 3) 'car)))
  (test-equal "car" 1 v))
(let-values (((v found) (inspect-property 42 'no-such-property)))
  (test-assert "not found" (not found)))

(test-assert "describe"
  (let ((out (open-output-string)))
    (inspect-describe 3/4 out)
    (positive? (string-length (get-output-string out)))))

(let ((failures (test-runner-fail-count (test-runner-current))))
  (test-end "srfi-279")
  (exit (if (zero? failures) 0 1)))

;;; SRFI 278 tests: the sample implementation's tests/run.scm (Peter
;;; McGoron; MIT licence), unmodified.  It exits with the failures'
;;; count.
;;; SPDX-FileCopyrightText: 2026 Peter McGoron
;;; SPDX-License-Identifier: MIT

(import (except (scheme base) exact-integer? real? integer? rational?
                              rationalize)
        (prefix (only (scheme base) real?) r5rs:)
        (scheme write)
        (scheme process-context)
        (scheme complex)
        (rename (scheme inexact) (nan? r7rs:nan?))
        (srfi 278))

(cond-expand
  (chicken-6
   (import (rename (test)
                   (test test-equal))))
  ((library (srfi 64))
   (import (srfi 64)))
  (else (error "need a test suite")))

(cond-expand
  (chicken-6
   (current-test-epsilon 0.01)
   (define-syntax test-approximate
     (syntax-rules ()
       ((_ (something . rest) actual error)
        (let ((value (something . rest)))
          (test-equal value actual)))
       ((_ expected actual error)
        (test-equal expected actual))
       ((_ name (something . rest) actual error)
        (let ((value (something . rest)))
          (test-equal name value actual)))
       ((_ name expected actual error)
        (test-equal name expected actual))))
   (define-syntax skip-unless
     (syntax-rules ()
       ((_ test expr)
        (when test expr))))
   (define-syntax test-eqv
     (syntax-rules ()
       ((_ expected actual) (test-equal expected actual))
       ((_ name expected actual) (test-equal name expected actual))))
  )
  ((library (srfi 64))
   (define (test-exit)
     (exit (+ (test-runner-fail-count the-test-runner)
              (test-runner-xpass-count the-test-runner))))
   (define-syntax skip-unless
     (syntax-rules ()
       ((_ test expr)
        (begin
          (unless test (test-skip 1))
          expr)))))
  )

(define signed-imaginary-zero?
  ;; Some tests discriminate based on the sign of the imaginary
  ;; zero. This is used to skip those tests.
  ;;
  ;; NOTE: This test suite assumes that real inexact zero still has a
  ;; sign.
  (not (eqv? (make-rectangular 0.0 0.0)
             (make-rectangular 0.0 -0.0))))

(define exact-complex-numbers?
  (exact? 1+2i))

(define mixed-exactness-complex-numbers?
  (let ((z 1+2.0i))
    (and (exact? (real-part z))
         (inexact? (imag-part z)))))

(define signed-zero?
  (not (eqv? -0.0 +0.0)))

(define needs-strict-definition?
  (cond
    ((not (r5rs:real? 0.0+0.0i)) #f)    ; Already stricter definition
    (signed-imaginary-zero? #t)
    ((exact? (imag-part 0.0)) #t)
    (else #f)))

(test-begin "SRFI 278")

(test-group "real?"
  (test-assert (real? 1.0))
  (skip-unless (not (memq 'chicken (features)))
               (test-assert (real? 1.0+0i)))
  (skip-unless needs-strict-definition?
               (test-assert (not (real? 1.0+0.0i))))
  (skip-unless needs-strict-definition?
               (test-assert (not (real? 1.0-0.0i)))))

(test-group "rational?"
  (test-assert (rational? 1/2))
  (test-assert (rational? 1/2+0i))
  (test-assert (rational? 0.5))
  (skip-unless needs-strict-definition?
    (test-assert (not (rational? 0.5+0.0i))))
  (skip-unless needs-strict-definition?
    (test-assert (not (rational? 0.5-0.0i)))))

(test-group "integer?"
  (test-assert (integer? 1.0))
  (test-assert (integer? 1))
  (test-assert (integer? 1+0i))
  (test-assert (integer? 1-0i))
  (skip-unless needs-strict-definition?
    (test-assert (not (integer? 1+0.0i))))
  (skip-unless needs-strict-definition?
    (test-assert (not (integer? 1-0.0i)))))

(test-group "exact-integer?"
  (test-assert (exact-integer? 1))
  (test-assert (exact-integer? 0))
  (test-assert (not (exact-integer? 0.0)))
  (test-assert (not (exact-integer? "0.0"))))

(test-group "rationalize"
  (test-eqv 0 (rationalize 1 1))
  ;; From the Gauche test suite
  (test-eqv 1/3 (rationalize 3/10 1/10 1/10 #f #f))
  (test-eqv 2/3 (rationalize 24/35 4/35 4/35 #f #f))
  (test-eqv 1 (rationalize 1 1/2))
  (test-eqv 2 (rationalize 5 3))
  (test-eqv 0 (rationalize 1 3))
  (test-eqv -1 (rationalize -1 1/2))
  (test-eqv -2 (rationalize -5 3))
  (test-eqv 0 (rationalize -1 3))
  (test-assert (exact? (rationalize 1/2 1/3)))
  (test-assert (inexact? (rationalize 0.5 1/3)))
  (test-assert (inexact? (rationalize 1/2 0.1)))
  (test-assert (inexact? (rationalize 0.5 0.1)))
  (test-eqv 53/10 (rationalize 5967269506265907/1125899906842624
                               (expt 2 -51)
                               (expt 2 -51)
                               #f
                               #f)))

(test-group "nan?"
  (test-assert (nan? +nan.0))
  (test-assert (not (nan? +inf.0)))
  (test-assert (not (nan? "NaN"))))

(test-group "nonnegative?"
  (test-assert (nonnegative? 1))
  (test-assert (nonnegative? 0))
  (test-assert (nonnegative? -0.0))
  (test-assert (not (nonnegative? -1)))
  (test-assert (not (nonnegative? +nan.0))))

(test-group "nonpositive?"
  (test-assert (nonpositive? -1))
  (test-assert (nonpositive? 0))
  (test-assert (nonpositive? -0.0))
  (test-assert (not (nonpositive? +1)))
  (test-assert (not (nonpositive? +nan.0))))

(test-group "nonzero?"
  (test-assert (nonzero? -1))
  (test-assert (nonzero? 1))
  (test-assert (not (nonzero? 0)))
  (test-assert (not (nonzero? 0.0)))
  (test-assert (not (nonzero? -0.0)))
  (test-assert (not (nonzero? +nan.0))))

(test-group "sign-negative?"
  (skip-unless
   signed-zero?
   (test-assert (sign-negative? -0.0)))
  (test-assert (not (sign-negative? 0)))
  (test-assert (not (sign-negative? +0.0)))
  (test-assert (sign-negative? -inf.0))
  (test-assert (not (sign-negative? +inf.0)))
  (test-assert (sign-negative? -1))
  (test-assert (not (sign-negative? 1))))

(test-group "ordered? and unordered?"
  (test-assert (ordered? 0 1))
  (test-assert (not (unordered? 0 1)))
  (test-assert (unordered? +nan.0 0))
  (test-assert (not (ordered? +nan.0 0)))
  (test-assert (unordered? 0 +nan.0))
  (test-assert (not (ordered? 0 +nan.0))))

(test-group "!="
  (test-assert (!= 1 2))
  (skip-unless
   signed-zero?
   (test-assert (not (!= -0.0 +0.0))))
  (test-assert (not (!= 0 0)))
  (test-assert (!= 1 1 2))
  (test-assert (not (!= 0.0 -0.0 0.0 0 -0.0)))
  (test-assert (!= 0.0 -0.0 0.0 0 -0.0 1))
  (let ((nan +nan.0))
    (test-assert (not (!= nan nan)))))

(test-group "round-away"
  (test-eqv +inf.0 (round-away +inf.0))
  (test-eqv -inf.0 (round-away -inf.0))
  (test-assert (nan? (round-away +nan.0)))
  (test-approximate 4.0
                    (round-away 3.5)
                    1e-6)
  (test-approximate 3.0
                    (round-away 2.5)
                    1e-6)
  (test-approximate 3.0
                    (round-away 2.6)
                    1e-6)
  (test-approximate 2.0
                    (round-away 2.4)
                    1e-6)
  (test-eqv 3 (round-away 5/2))
  (test-approximate -4.0
                    (round-away -3.5)
                    1e-6)
  (test-approximate -3.0
                    (round-away -2.5)
                    1e-6))

(test-group "conjugate"
  (test-eqv 1 (conjugate 1))
  (test-eqv -1 (conjugate -1))
  (test-eqv 1-2i (conjugate 1+2i))
  (skip-unless signed-imaginary-zero?
    (test-eqv -0.0 (imag-part (conjugate 1.0+0.0i))))
  (test-eqv +i (conjugate -i)))

(test-group "sinh"
  (test-eqv "(sinh 0)" 0 (sinh 0))
  (test-eqv "(sinh 0.0)" 0.0 (sinh 0.0))
  (test-eqv "(sinh -0.0)" -0.0 (sinh -0.0))
  (test-eqv "(sinh +inf.0)" +inf.0 (sinh +inf.0))
  (test-eqv "(sinh -inf.0)" -inf.0 (sinh -inf.0))
  (test-eqv "(sinh 1e-30+1e-40i)"
            1e-30+1e-40i
            (sinh 1e-30+1e-40i))
  (test-approximate (/ (- (exp 1) (exp -1)) 2)
                    (sinh 1)
                    1e-6))

(test-group "cosh"
  (test-eqv "(cosh 0)" 1 (cosh 0))
  (test-eqv "(cosh +inf.0)" +inf.0 (cosh +inf.0))
  (test-eqv "(cosh -inf.0)" +inf.0 (cosh -inf.0))
  (let ((v (cosh +i)))
    (test-assert "(imag-part (cosh +i))" (= (imag-part v) 0))
    (test-approximate "(real-part (cosh +i))" .5403023058681398 (real-part v) 1e-6))
  (test-approximate "(cosh 1)"
                    (/ (+ (exp 1) (exp -1)) 2)
                    (cosh 1)
                    1e-6))

(test-group "tanh"
  (test-eqv 0 (tanh 0))
  (test-eqv "(tanh 0.0)" 0.0 (tanh 0.0))
  (test-eqv "(tanh -0.0)" -0.0 (tanh -0.0))
  (test-eqv "(tanh +inf.0)" 1.0 (tanh +inf.0))
  (test-eqv "(tanh -inf.0)" -1.0 (tanh -inf.0))
  (test-eqv "(tanh 1e-30+1e-40i)"
            1e-30+1e-40i
            (tanh 1e-30+1e-40i))
  (test-assert "(tanh 300+20i)" (nonzero? (imag-part (tanh 300+20i))))
  (test-assert (rational? (imag-part (tanh 266.42844752772896+1.3482698511467367e308i))))
  (test-approximate (/ (sinh 10) (cosh 10))
                    (tanh 10)
                    1e-6))

(define (naive-atanh z)
  (/ (- (log (+ 1 z)) (log (- 1 z)))
     2))

(define (test-approximate/special expect actual error)
  (cond
    ((and (not exact-complex-numbers?) (zero? expect))
     (test-assert (zero? actual)))
    ((eqv? expect +0.0)
     (test-assert (or (eqv? actual 0.0)
                      (eqv? actual 0))))
    ((eqv? expect -0.0)
     (test-assert (eqv? actual -0.0)))
    ((infinite? expect)
     (test-eqv expect actual))
    ((nan? expect)
     (test-assert (nan? actual)))
    (else (test-approximate expect actual error))))

(define (test-real-and-imag z-expect z-actual)
  (test-approximate/special (real-part z-expect)
                            (real-part z-actual)
                            1e-6)
  (test-approximate/special (imag-part z-expect)
                            (imag-part z-actual)
                            1e-6))

(test-group "atanh"
  ;; In Kahan’s version for unsigned zero, the returned value is the
  ;; value that is approached counter-clockwise.
  (test-eqv 0 (atanh 0))
  (test-group "(atanh 1.0+0.0i)"
    (test-real-and-imag (if signed-imaginary-zero?
                            +inf.0+.7853981633974483i
                            +inf.0-.7853981633974483i)
                        (atanh 1.0+0.0i)))
  (test-group "(atanh 1.0-0.0i)"
    (test-real-and-imag +inf.0-.7853981633974483i
                        (atanh 1.0-0.0i)))
  (test-group "(atanh -1.0+0.0i)"
    (test-real-and-imag -inf.0+.7853981633974483i
                        (atanh -1.0+0.0i)))
  (test-group "(atanh -1.0-0.0i)"
    (test-real-and-imag (if signed-imaginary-zero?
                            -inf.0-.7853981633974483i
                            -inf.0+.7853981633974483i)
                        (atanh -1.0-0.0i)))
  (test-group "(atanh 2.0+0.0i)"
    (test-real-and-imag (if signed-imaginary-zero?
                            .5493061443340549+1.5707963267948966i
                            .5493061443340549-1.5707963267948966i)
                        (atanh 2.0+0.0i)))
  (test-group "(atanh 2.0-0.0i)"
    (test-real-and-imag .5493061443340549-1.5707963267948966i
                        (atanh 2.0-0.0i)))
  (test-group "(atanh 0.0+1.0i)"
    (test-real-and-imag 0.0+0.7853981633974483i
                        (atanh 0.0+1.0i)))
  (test-group "(atanh 0.0-1.0i)"
    (test-real-and-imag 0.0-.7853981633974483i
                        (atanh 0.0-1.0i)))
  (test-approximate "(atanh 0.5)"
                    (naive-atanh 0.5)
                    (atanh 0.5)
                    1e-6)
  (test-approximate "(atanh 0.99)"
                    (naive-atanh 0.99)
                    (atanh 0.99)
                    1e-6)
  (let ((w (atanh 0-1.0i)))
    (skip-unless mixed-exactness-complex-numbers?
      (test-eqv 0 (real-part w)))
    (test-approximate -.7853981633974483
                      (imag-part w)
                      1e-6))
  (test-group "(atanh 2.0)"
    (test-real-and-imag (naive-atanh 2.0)
                        (atanh 2.0)))
  (test-group "(atanh 5+10i)"
    (test-real-and-imag .03976617365742184+1.490839765215787i
                        (atanh 5+10i))))

(test-group "acosh"
  (test-eqv 0 (acosh 1))
  (test-group "(acosh 1.0+0.0i)"
    (test-real-and-imag 0.0+0.0i
                        (acosh 1.0+0.0i)))
  (test-group "(acosh 1.0-0.0i)"
    (test-real-and-imag (if signed-imaginary-zero?
                            0.0-0.0i
                            0.0+0.0i)
                        (acosh 1.0-0.0i)))
  (test-group "(acosh 0.0+0.0i)"
    (test-real-and-imag 0.+1.5707963267948966i
                        (acosh 0.0+0.0i)))
  (test-group "(acosh 0.0-0.0i)"
    (test-real-and-imag (if signed-imaginary-zero?
                            0.-1.5707963267948966i
                            0.+1.5707963267948966i)
                        (acosh 0.0-0.0i)))
  (test-group "(acosh 1.0+inf.0i)"
    (test-real-and-imag +inf.0+1.5707963267948966i
                        (acosh 1.0+inf.0i)))
  (test-group "(acosh -inf.0+1.0i)"
    (test-real-and-imag +inf.0+3.141592653589793i
                        (acosh -inf.0+1.0i)))
  (test-group "(acosh +inf.0+1.0i)"
    (test-real-and-imag +inf.0+3.141592653589793i
                        (acosh -inf.0+1.0i)))
  (test-group "(acosh -1+0.0i)"
    (test-real-and-imag 0.0+3.141592653589793i
                        (acosh -1+0.0i)))
  (test-group "(acosh -1-0.0i)"
    (test-real-and-imag (if signed-imaginary-zero?
                            0.0-3.141592653589793i
                            0.0+3.141592653589793i)
                        (acosh -1-0.0i)))
  (test-group "(acosh 3+4i)"
    (test-real-and-imag 2.305509031243477+.9368124611557198i
                        (acosh 3+4i))))

(define (naive-asinh z)
  (log (+ z (sqrt (+ 1 (square z))))))

(test-group "asinh"
  (test-eqv 0 (asinh 0))
  (test-group "(asinh 0.0+2.0i)"
    (test-real-and-imag 1.3169578969248166+1.5707963267948966i
                        (asinh 0.0+2.0i)))
  (test-group "(asinh -0.0+2.0i)"
    (let ((input (make-rectangular -0.0 2.0)))
      (test-real-and-imag -1.3169578969248166+1.5707963267948966i
                          (asinh input))))
  (test-group "(asinh 0.0-2.0i)"
    (test-real-and-imag 1.3169578969248166-1.5707963267948966i
                        (asinh 0.0-2.0i)))
  (test-group "(asinh -0.0-2.0i)"
    (let ((input (make-rectangular -0.0 -2.0)))
      (test-real-and-imag -1.3169578969248166-1.5707963267948966i
                          (asinh input))))
  (test-group "(asinh +inf.0+2.0i)"
    (test-real-and-imag +inf.0+0.0i
                        (asinh +inf.0+2.0i)))
  (test-group "(asinh +inf.0+inf.0i)"
    (test-real-and-imag +inf.0+0.7853981633974483i
                        (asinh +inf.0+inf.0i)))
  (test-group "(asinh 2.0+nan.0i)"
    (test-real-and-imag (make-rectangular +nan.0 +nan.0)
                        (asinh (make-rectangular 2.0 +nan.0))))
  (test-group "(asinh +i)"
    (test-real-and-imag +1.5707963267948966i
                        (asinh +i)))
  (test-group "(asinh 5)"
    (test-approximate (naive-asinh 5)
                      (asinh 5)
                      1e-6))
  (test-group "(asinh 1+2i)"
    (test-real-and-imag (naive-asinh 1+2i)
                        (asinh 1+2i))))

(test-group "exact integer nth root"
  (let-values (((e i) (exact-integer-nth-root 40 3)))
    (test-equal 3 e)
    (let ((expected (- 40 27)))
      (test-equal expected i))))

(test-group "exact integer log"
  (let-values (((e i) (exact-integer-log 8 2)))
    (test-equal 3 e)
    (test-equal 0 i))
  (let-values (((e i) (exact-integer-log 11 2)))
    (test-equal 3 e)
    (test-equal 3 i)))

(cond-expand
  ((and (not chicken) (library (srfi 64)))
   (define the-test-runner (test-runner-get)))
  (else))
(test-end "SRFI 278")
(test-exit)

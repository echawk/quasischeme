;;; SPDX-FileCopyrightText: 2026 Peter McGoron
;;; SPDX-License-Identifier: MIT

(define fl-least-normal
         (do ((candidate fl-least (* 2.0 candidate)))
             ((flnormalized? candidate) candidate)))

(define signed-zero?
  (not (eqv? +0.0 -0.0)))

(define signed-imaginary-zero?
  ;; True only when the sign of *imaginary* zero is distinguished.
  ;; Gauche, CHICKEN, for example, don't, even when the distinguish
  ;; the sign of real zero.
  (not (eqv? (make-rectangular 0.0 0.0)
             (make-rectangular 0.0 -0.0))))

(define needs-strict-definition?
  (cond
    ((not (r5rs:real? 0.0+0.0i)) #f)    ; Already stricter definition
    (signed-imaginary-zero? #t)
    ((exact? (imag-part 0.0)) #t)
    (else #f)))

(define (imaginary? obj)
  (and (complex? obj)
       (eqv? 0 (real-part obj))))

(define real?
  (if needs-strict-definition?
      (lambda (obj)
        (and (complex? obj)
             (eqv? 0 (imag-part obj))))
      r5rs:real?))

(define rational?
  (if needs-strict-definition?
      (lambda (obj)
        (and (real? obj) (r5rs:real? obj)))
      r5rs:rational?))

(define integer?
  (if needs-strict-definition?
      (lambda (obj)
        (and (rational? obj)
             (eqv? 1 (denominator obj))))
      r5rs:integer?))

(define (nan? obj)
  (and (number? obj) (r7rs:nan? obj)))

(define (ordered? x y)
  (and (not (nan? x))
       (not (nan? y))))

(define (unordered? x y)
  (or (nan? x) (nan? y)))

(define (!= x y . rest)
  (let loop ((x x) (y y) (rest rest))
    (cond
      ((unordered? x y) #f)
      ;; If the two arguments are numerically equal, then
      ;; check if there are more arguments. If there are none, return
      ;; false. Otherwise, try to find an unequal argument.
      ((= x y) (and (pair? rest)
                    (loop y
                          (car rest)
                          (cdr rest))))
      (else #t))))

(define (sign-negative? x)
  (if (and signed-zero? (eqv? x -0.0))
      #t
      (negative? x)))

(define (nonnegative? x)
  (>= x 0))

(define (nonpositive? x)
  (<= x 0))

(define (nonzero? x)
  (!= x 0))

(define (exact-integer? obj)
  (and (integer? obj) (exact? obj)))

(define (conjugate z)
  ;; Return exact value given possibly exact arguments.
  ;; For implementations with only inexact complex numbers.
  (if (real? z)
      z
      (make-rectangular (real-part z)
                        (- (imag-part z)))))

(cond-expand
  ((or (library (srfi 144))
       (library (srfi 276)))
   (define (make-flonum* x k)
     (cond
       ((eqv? k +inf.0) +inf.0)
       ((eqv? k -inf.0) (* (sign x) 0.0))
       (else (make-flonum (flonum x) (exact k)))))
   (define (cssqs z)
     ;; NOTE: We don't have access to the overflow and underflow flags
     ;; here, so we cannot implement this part of Kahan's algorithm
     ;; verbatim. We need to do a trick.
     (let* ((x (real-part z))
            (y (imag-part z))
            (x^2 (square x))
            (y^2 (square y))
            (rho (+ x^2 y^2)))
       (if (and (or (nan? rho) (infinite? rho))
                (or (infinite? x) (infinite? y)))
           (values +inf.0 0)
           (let ((underflowed? (or (< x^2 fl-least-normal)
                                   (< y^2 fl-least-normal)))
                 (overflowed? (or (infinite? rho)
                                  (infinite? x^2)
                                  (infinite? y^2))))
             (if (or overflowed?
                     (and underflowed? (< rho (/ fl-least-normal
                                                 fl-epsilon))))
                 (let ((k (flexponent (flonum (max (abs x) (abs y))))))
                   ;; NOTE: This isn't scalb, this is ldexp
                   (values (+ (square (make-flonum* x (- k)))
                              (square (make-flonum* y (- k))))
                           k))
                 (values rho 0))))))
   ;; These are defined on all values, and work around a contradiction
   ;; in the R7RS-Small.
   (define (even*? k)
     (and (integer? k) (not (infinite? k)) (even? k)))
   (define (odd*? k)
     (and (integer? k) (not (infinite? k)) (odd? k)))
   (define (csqrt z)
     (let*-values (((x) (real-part z))
                   ((y) (imag-part z))
                   ((rho k) (cssqs z))
                   ((rho) (if (not (nan? x))
                              (+ (make-flonum* (abs x)
                                               (- k))
                                 (sqrt rho))
                              rho))
                   ((rho) (if (even*? k)
                              (+ rho rho)
                              rho))
                   ((k) (if (odd*? k)
                            (/ (- k 1) 2)
                            (- (/ k 2) 1)))
                   ((rho) (make-flonum* (sqrt rho) k))
                   ((zeta) rho)
                   ((eta) y)
                   ((eta) (cond
                            ((eqv? eta 0) 0)
                            ((and (not (zero? rho)) (not (infinite? eta)))
                             (/ eta rho 2.0))
                            (else eta))))
       (if (and (not (zero? rho)) (negative? x))
           (make-rectangular (abs eta) (* rho (sign y)))
           (make-rectangular zeta eta)))))
  (else (define csqrt sqrt)))

(define (sinh z)
  (cond
    ((eqv? z 0) 0)
    ((eqv? z +0.0) 0.0)
    ((eqv? z -0.0) -0.0)   ; Hack for CHICKEN
    ((real? z) (flsinh (flonum z)))
    (else
      (make-rectangular (* (sinh (real-part z))
                           (cos (imag-part z)))
                        (* (cosh (real-part z))
                           (sin (imag-part z)))))))

(define (cosh z)
  (cond
    ((eqv? z 0) 1)
    ((real? z) (flcosh (flonum z)))
    (else
      (let ((x (flonum (real-part z)))
            (y (imag-part z)))
        (make-rectangular (* (cosh x) (cos y))
                          (* (sinh x) (sin y)))))))

(cond-expand
  ((or (library (srfi 144))
       (library (srfi 276)))
   (define (casin z)
     (let ((x (real-part z))
           (y (imag-part z)))
       (if (eqv? x 0)
           (make-rectangular 0 (asinh (imag-part z)))  ; From gambit
           (let* ((s:1-z (csqrt (- 1 z)))
                  (s:1+z (csqrt (+ 1 z)))
                  (x (real-part z))    ; ??? Chibi bug???
                  (y (imag-part z))
                  (rpart
                   (if (and (infinite? x) (finite? y))
                       (flcopysign fl-pi/2 x)
                       (atan x (real-part (* s:1-z s:1+z)))))
                  (ipart
                   (asinh (imag-part (* (conjugate s:1-z)
                                        s:1+z)))))
             (make-rectangular rpart ipart))))))
  (else (define casin asin)))

;;; Kahan's algorithm can cope with all unsigned zeros, or all signed
;;; zeroes, but some Scheme implementations have signed real zeroes
;;; but unsigned imaginary zeroes. This implementation of asinh causes
;;; the *clockwise* direction to be chosen for any signed zero input,
;;; because of these multiplications by +i storing the signed zero in
;;; the imaginary part, removing the sign.
;;;
;;; Not only is that the opposite convention of the unsigned zero case,
;;; it also erases sign information from the real part! This hack fixes
;;; this.

(cond-expand
  ((or chicken gauche)
   (define (*-i z)
     (make-rectangular (imag-part z)
                       (- (real-part z))))
   (define (*+i z)
     (make-rectangular (- (imag-part z))
                       (real-part z))))
  (else (define (*-i z) (* -i z))
        (define (*+i z) (* +i z))))

(define asinh
  (if signed-imaginary-zero?
      (lambda (z)
        (cond
          ((eqv? z 0) 0)
          ((real? z) (flasinh (flonum z)))
          (else (*-i (casin (*+i z))))))
      (lambda (z)
        (cond
          ((eqv? z 0) 0)
          ((real? z) (flasinh (flonum z)))
          (else
           (let ((w (*-i (casin (*+i z))))
                 (x (real-part z))
                 (y (imag-part z)))
             (cond
               ((positive? y)                        ; First or second
                (make-rectangular (* (sign x)        ; quadrant. The CCW rule
                                     (real-part w))  ; was applied, meaning
                                  (imag-part w)))    ; that we should flip
                                                     ; the sign.
               ((zero? y) w)
               (else                                 ; Third or fourth
                (make-rectangular (* (sign x)        ; quadrant. We might
                                     -1              ; need to flip the sign,
                                     (real-part w))  ; but in the opposite
                                  (imag-part w)))    ; scenarios.
)))))))

(define (%acosh z)
  (let* ((x (real-part z))
         (y (imag-part z))
         (sqrt:z-1 (csqrt (- z 1)))
         (sqrt:z+1 (csqrt (+ z 1))))
    (make-rectangular (asinh (real-part (* (conjugate sqrt:z+1)
                                           sqrt:z-1)))
                      (* 2 (atan (imag-part sqrt:z-1)
                                 (real-part sqrt:z+1))))))

(define (acosh z)
  (if (eqv? z 1)
      0
      (%acosh z)))

(define (sign x)
  (cond
    ((and (exact? x) (zero? x)) 1)
    ((and (zero? x) (not (eqv? x 0.0))) -1)
    ((negative? x) -1)
    (else 1)))

(cond-expand
  ;; Work around a bug(?) in CHICKEN 6 where
  ;;   (* 1 +inf.0+1.0i) => +inf.0+nan.0i
  (chicken-6
   (define (c* x z)
     (make-rectangular (* x (real-part z))
                       (* x (imag-part z)))))
  (else (define c* *)))

;; These are constants defined in Kahan's paper.
;; They don't have better names, AFAIK.
(define theta (/ (sqrt fl-greatest) 4))
(define rho (/ theta))

(define (%atanh z)
  (let* ((z (c* (sign (real-part z)) (conjugate z)))
         (x (real-part z))
         (y (imag-part z)))
    (cond
      ((or (> x theta) (> (abs y) theta))
       (make-rectangular (real-part (/ z))
                         (* fl-pi/2 (sign y))))
      ((and (= x 1.0) (zero? y))
       (make-rectangular +inf.0
                         (* (sign y) fl-pi/4)))
      ((= x 1.0)
       (let ((absy (abs y)))
         (make-rectangular (log (/ (sqrt (sqrt (+ 4.0 (square y))))
                                   (sqrt absy)))
                           (* (/ (+ fl-pi/2
                                    (atan absy 2.0))
                                 2.0)
                              (sign y)))))
      (else
       (let ((y^2 (square y)))
         (make-rectangular (cond
                             ((eqv? x 0) 0)
                             (else
                              (/ (fllog1+ (/ (* 4.0 x)
                                             (+ (square (- 1.0 x))
                                                y^2)))
                                 4.0)))
                           (/ (angle (+ (* (- 1.0 x) (+ 1.0 x))
                                        (- y^2)
                                        (make-rectangular
                                         0.0
                                         (* 2.0 y))))
                              2.0)))))))

(define (atanh z)
  (cond
    ((eqv? z 0) 0)
    ((and (real? z) (eqv? (abs z) 1))
     (error 'atanh "atanh has a singularity at 1 and -1"))
    ((and (real? z) (< -1.0 z 1.0))
     (flatanh (flonum z)))
    (else (c* (sign (real-part z)) (conjugate (%atanh z))))))

(define tanh-overflow-treshold
  (/ (flasinh fl-greatest) 2))

(define tanh-overflow-low-treshold
  (/ (flasinh fl-greatest) 4))

(define (tanh z)
  (let* ((x (real-part z))
         (y (imag-part z))
         (ax (abs x)))
    (cond
      ((eqv? z 0) 0)
      ((eqv? z +0.0) +0.0)
      ((eqv? z -0.0) -0.0)
      ((> ax tanh-overflow-treshold)
       (if (real? z)
           (* 1.0 (sign x))
           (make-rectangular (* 1.0 (sign x))
                             (* 0.0 (sign y)))))
      ((> ax tanh-overflow-low-treshold)
       (if (real? z)
           (* 1.0 (sign x))
           (let ((y*2 (* y 2))
                 (cosh-x*2 (flcosh (* 2.0 x))))
             (cond
               ((finite? y*2)
                (make-rectangular (* 1.0 (sign x))
                                  (/ (sin y*2)
                                     cosh-x*2)))
               ((finite? y)
                (make-rectangular (* 1.0 (sign x))
                                  (/ (* 2.0 (sin y) (cos y))
                                     cosh-x*2)))
               (else (make-rectangular (* 1.0 (sign x))
                                       (* 0.0 (sign y))))))))
      (else
       (let* ((t (tan y))
              (beta (+ 1.0 (square t)))
              (s (if (eqv? x 0)
                     0.0              ; Avoid divide-by-exact-zero errors
                     (sinh x)))
              (rho (sqrt (+ 1.0 (square s)))))
         (if (infinite? t)
             (make-rectangular (/ rho s) (/ t))
             (let ((ret (if (real? z)
                            (* beta rho s)
                            (make-rectangular (* beta rho s)
                                              t))))
               (/ ret (+ 1.0 (* beta (square s)))))))))))

(define (round-away x)
  (cond
    ((or (infinite? x) (nan? x)) x)
    ((negative? x) (truncate (- x 1/2)))
    (else (truncate (+ x 1/2)))))

(define (rationalize* lower upper lower-inclusive? upper-inclusive?)
  (cond
    ((and (integer? lower) lower-inclusive?)
     lower)
    ((and (integer? upper) upper-inclusive?)
     upper)
    (else
      (let ((candidate (ceiling lower)))
        (if (<= candidate upper)         ; integer in interval?
            candidate                    ; return integer. Note that
                                         ; when the upper bound is +inf.0,
                                         ; the code below never runs.
            ;; Refine guess.
            (let* ((integer-part (floor lower))
                   (new-lower (/ (- upper integer-part)))
                   (new-upper (if (integer? lower)
                                  +inf.0 ; swap to inexact infinity
                                  (/ (- lower integer-part)))))
              (+ integer-part
                 (/ (rationalize* new-lower
                                  new-upper
                                  upper-inclusive?
                                  lower-inclusive?)))))))))

(define (rationalize-easy-cases lower
                                upper
                                lower-inclusive?
                                upper-inclusive?)
  (cond
    ((< lower 0 upper) 0)
    ((and lower-inclusive? (zero? lower)) 0)
    ((and upper-inclusive? (zero? upper)) 0)
    ((= lower upper) lower)
    ((not (positive? upper))
     (- (rationalize* (- upper)
                      (- lower)
                      lower-inclusive?
                      upper-inclusive?)))
    (else
     (rationalize* lower
                   upper
                   lower-inclusive?
                   upper-inclusive?))))

(define rationalize
  (case-lambda
    ((x y) (rationalize x y y #t #t))
    ((x dlower dupper) (rationalize x dlower dupper #t #t))
    ((x dlower dupper lower-inclusive? upper-inclusive?)
     (unless (and (real? x) (finite? x))
       (error "x must be a real, finite number" x))
     (unless (real? dlower)
       (error "delta must be a real number" dlower))
     (unless (real? dupper)
       (error "upper delta must be a real number" dupper))
     (when (= dlower dupper 0)
       (unless (and lower-inclusive? upper-inclusive?)
         (error "interval is empty" x dlower dupper
                                    lower-inclusive?
                                    upper-inclusive?)))
     ;; Don't check for boolean
     (let* ((lower (- x (abs dlower)))
            (upper (+ x (abs dupper)))
            (value (rationalize-easy-cases (exact lower)
                                           (exact upper)
                                           lower-inclusive?
                                           upper-inclusive?)))
       (if (or (inexact? x) (inexact? dlower) (inexact? dupper))
           (inexact value)
           value)))))

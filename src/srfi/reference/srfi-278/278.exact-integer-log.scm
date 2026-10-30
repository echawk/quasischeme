; SPDX-FileCopyrightText: 2026 Peter McGoron
;
; SPDX-License-Identifier: MIT

(define (exact-integer-log n b)
  ;; See Jeronimo Pellegrini's email:
  ;; https://srfi-email.schemers.org/srfi-278/msg/43517844/
  (unless (and (exact-integer? n)
               (positive? n)
               (exact-integer? b)
               (>= b 2))
    (error "invalid arguments" n b))
  ;; log_b n = log_2(n) / log_2(b)
  ;;
  ;; Find x, y such that
  ;; n = b^x + y and n < b^(x+1).
  ;;
  ;; n = b^(log_2(n)/log_2(b))
  ;;
  ;; Given that ilen(n), the number of bits needed to store n, is
  ;; ilen(n) = floor(log_2(n)) + 1
  ;; we have
  ;;
  ;; log_2(n) = ilen(n) - 1 + fraction(log_2(n))
  ;; etc. We can then approximate
  ;;
  ;; log_2(n)/log_2(b) ≈ (ilen(n)-1)/(ilen(b) - 1)
  ;; ;;;;;;;;;;;;;;;
  ;; floor(x/y) ≠ (floor x)/(floor y) in general, and there is no general
  ;; relation that we can use here. So we just have to adjust the guess
  ;; up and down until we get to the correct number.
  ;;
  ;; First we adjust until we possibly overshoot.
  ;; Following STKlos, this will first adjust by 1, then 3, then 5, ...
  (do ((guess (quotient (- (integer-length n) 1)
                        (- (integer-length b) 1))
              (- guess step))
       (step 1 (+ step 2)))
      ((>= n (expt b guess))
       ;; Now we may have overshot. This might be the case if we stepped
       ;; at all.
       ;;
       ;; If we have stepped, undo the step, and step by 1.
       ;; Then, return the values.
       (if (> step 1)
           (do ((guess (+ guess step -2)
                       (- guess 1)))
               ((>= n (expt b guess))
                (values guess (- n (expt b guess)))))
           (values guess (- n (expt b guess)))))))

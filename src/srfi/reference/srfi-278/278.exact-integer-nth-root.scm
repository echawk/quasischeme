;;; SPDX-FileCopyrightText: 2000-2007 Felix L. Winkelmann
;;; SPDX-FileCopyrightText: 2007-2022 The CHICKEN Team
;;; SPDX-FileCopyrightText: 2026 Peter McGoron
;;; SPDX-License-Identifier: BSD-3-Clause

(define (exact-integer-nth-root k n)
  (if (or (eq? 0 k) (eq? 1 k) (eq? 1 n)) ; Maybe call exact-integer-sqrt on n=2?
      (values k 0)
      (let ((len (integer-length k)))
        (if (< len n)          ; Idea from Gambit: 2^{len-1} <= k < 2^{len}
            (values 1 (- k 1)) ; Since x >= 2, we know x^{n} can't exist
            ;; Set initial guess to (at least) 2^ceil(ceil(log2(k))/n)
            (let* ((shift-amount (exact (ceiling (/ (+ len 1) n))))
                   (g0 (arithmetic-shift 1 shift-amount))
                   (n-1 (- n 1)))
              (let lp ((g0 g0)
                       (g1 (quotient
                            (+ (* n-1 g0)
                               (quotient k (expt g0 n-1)))
                            n)))
                (if (< g1 g0)
                    (lp g1 (quotient
                            (+ (* n-1 g1)
                               (quotient k (expt g1 n-1)))
                            n))
                    (values g0 (- k (expt g0 n))))))))))

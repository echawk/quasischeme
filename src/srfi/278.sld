;;; SRFI 278: supplemental numerics.  Peter McGoron's sample
;;; implementation: its 278.sld, its includes made reference/srfi-278/'s
;;; (278.scm and 278.exact-integer-log.scm, MIT; 278.exact-integer-nth-root.scm,
;;; from CHICKEN, BSD-3-Clause: both in reference/srfi-278/LICENSE).  It
;;; takes the generic branches: (srfi 151) and (srfi 144).
;;; SPDX-FileCopyrightText: 2026 Peter McGoron
;;; SPDX-License-Identifier: MIT

(define-library (srfi 278)
  (import (except (scheme base) exact-integer? real? rational? integer?
                  rationalize)
          (prefix (only (scheme base) real? rational? integer?)
                  r5rs:)
          (scheme write)
          (rename (scheme inexact)
                  (nan? r7rs:nan?))
          (scheme complex)
          (scheme case-lambda))
  (export nan? exact-integer?
          ordered? unordered?
          != sign-negative?
          nonnegative? nonpositive? nonzero?
          imaginary? real? rational? integer?
          sinh cosh tanh asinh acosh atanh
          conjugate rationalize round-away
          exact-integer-nth-root exact-integer-log)

  (cond-expand
    (chicken (import (chicken bitwise)))
    (else (import (srfi 151))))
  (cond-expand
    ((library (srfi 144))
     (import (only (srfi 144)
                   flonum
                   fl-greatest
                   fl-epsilon
                   fl-least
                   flnormalized?
                   flcopysign
                   fladjacent
                   fl-pi/2
                   fl-pi/4
                   make-flonum
                   flexponent
                   flasinh
                   flsinh
                   flcosh
                   flatanh
                   fllog1+)))
    ;; If you don't have SRFI 144, you have to define the following
    ;; here:
    ;;
    ;; flonum (which is probably just `inexact`)
    ;; fl-greatest
    ;; fl-least-normal (not fl-least; the smallest normal number)
    ;; fl-epsilon
    ;; fl-pi/2
    ;; fl-pi/4
    ;; make-flonum (aka ldexp)
    ;; flexponent (aka logb)
    ;; fllog1+
    ;; flasinh
    ;; flsinh
    ;; flcosh
    ;; flatanh
    ;;
    ;; If your inexact real type is a IEEE 754 format number, then you
    ;; can use the SRFI 144 sample implementation.
    ;;
    ;; The other imports are used to implement Kahan's complex number
    ;; versions of Scheme's built-in procedures, like sqrt, asin, etc.
    ;; If neither 276 or 144 are available, then the implementation will
    ;; fall back to the standard procedures. Note that if the
    ;; implementation's procedures are inaccurate, it will affect the
    ;; results of the procedures here.
    ;;
    ;; I would be very interested in any Schemes using non-standard
    ;; floating point formats.
)
  (cond-expand
    (chicken (import (only (chicken base) exact-integer-nth-root)))
    (else (include "reference/srfi-278/278.exact-integer-nth-root.scm")))
  ;; FIXME: STklos has this, so this should cond-expand and check for
  ;; STklos.
  (include "reference/srfi-278/278.exact-integer-log.scm")

  (include "reference/srfi-278/278.scm"))

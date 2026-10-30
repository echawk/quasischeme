;;; SRFI 273: extensions to data (type-)checking.  Artyom Bologov's
;;; sample implementation (reference/srfi-273/impl.scm, unmodified; MIT
;;; licence in reference/srfi-273/LICENSE), on SRFI 253, whose library its
;;; shipped 273.sld imports, as here.
(define-library (srfi 273)
  (export define-check
          define-values-checked
          declare-checked)
  (import (scheme base)
          (srfi 253))
  (include "reference/srfi-273/impl.scm"))

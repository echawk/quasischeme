;;; SRFI 279: in(tro)spection protocol.  Artyom Bologov's sample
;;; implementation, its portable branch (reference/srfi-279/generic.scm,
;;; unmodified; MIT licence in reference/srfi-279/LICENSE), with that
;;; branch's imports.  Its 279.sld picks a file per implementation by
;;; cond-expand; this is the one for every mode here (its guile.scm
;;; needs (ice-9 match) and the like, which only Guile mode has).  Its
;;; (srfi 160) import is (srfi 160 base), the one SRFI 160 names with the
;;; vector predicates; (scheme repl) is imported too, for its
;;; interaction-environment, and the three Chibi procedures generic.scm
;;; calls are defined: opcode?, opcode-name and procedure-name, and its
;;; write/ss is write-shared.  It uses
;;; and-let* too, which the generic branch doesn't import: SRFIs 2, 26
;;; and 151 are imported as the Chibi branch does.
(define-library (srfi 279)
  (export inspect-properties inspect-property inspect-describe)
  (import (scheme base)
          (scheme write)
          (scheme char)
          (scheme complex)
          (scheme file)
          (scheme eval)
          (scheme repl)
          (scheme case-lambda))
  (import (srfi 253))
  (import (srfi 1))   ;; List library
  (import (srfi 2))   ;; and-let*
  (import (srfi 14))  ;; Char sets
  (import (srfi 26))  ;; cut/cute
  (import (srfi 151)) ;; Integers as bits
  (import (srfi 69))  ;; Hash tables
  (import (srfi 160 base)) ;; Numeric vectors
  ;; what generic.scm calls of Chibi's: no opcodes here, nor procedure names
  (begin
    (define (opcode? x) #f)
    (define (opcode-name x) x)
    (define (procedure-name p) #f)
    (define write/ss write-shared))
  (include "reference/srfi-279/generic.scm"))

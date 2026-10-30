;;; From Daphne Preston-Kendal's extensible-match, which provides (srfi :262
;;; match), the pattern matcher of withdrawn SRFI 262 that SRFI 275 uses:
;;; https://codeberg.org/dpk/extensible-match, commit
;;; 2a5834639666790bac14a89b05389eaea66c4d55, dedicated to the public domain
;;; (CC0 1.0, COPYING).  QUASISCHEME: its libraries' names (extensible-match
;;; ...) are renamed (srfi :262 extensible-match ...).
(library (srfi :262 extensible-match helpers)
  (export match-ellipsis?)
  (import (rnrs (6)))

  (define (exact-integer? n)
    (and (integer? n) (exact? n)))

  (define (match-ellipsis? pat)
    (syntax-case pat ()
      (ell
       (and (identifier? #'ell)
            (free-identifier=? #'ell #'(... ...)))
       #t)
      ((ell n)
       (and (identifier? #'ell)
            (free-identifier=? #'ell #'(... ...))
            (exact-integer? (syntax->datum #'n)))
       #t)
      ((ell min #t)
       (and (identifier? #'ell)
            (free-identifier=? #'ell #'(... ...))
            (exact-integer? (syntax->datum #'min)))
       #t)
      ((ell min max)
       (and (identifier? #'ell)
            (free-identifier=? #'ell #'(... ...))
            (exact-integer? (syntax->datum #'min))
            (exact-integer? (syntax->datum #'max)))
       #t)
      ((ell . _)
       (and (identifier? #'ell)
            (free-identifier=? #'ell #'(... ...)))
       (syntax-violation 'match "incorrect use of ellipsis" pat))
      (_ #f))))

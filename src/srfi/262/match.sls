;;; From Daphne Preston-Kendal's extensible-match, which provides (srfi :262
;;; match), the pattern matcher of withdrawn SRFI 262 that SRFI 275 uses:
;;; https://codeberg.org/dpk/extensible-match, commit
;;; 2a5834639666790bac14a89b05389eaea66c4d55, dedicated to the public domain
;;; (CC0 1.0, COPYING).  QUASISCHEME: its libraries' names (extensible-match
;;; ...) are renamed (srfi :262 extensible-match ...).
(library (srfi :262 match)
  (export match
          match-lambda
          match-values
          match-let
          match-let*
          match-let-values
          match-let*-values
          match-define
          match-define-values
          match-letrec
          match-letrec*
          if-match

          define-pattern-syntax
          match-ellipsis?

          &match
          make-match-violation
          match-violation?

          and or not => ? quote
          seq seq* seq/unordered
          cons cons* lset list vector eof-object
          quasiquote unquote unquote-splicing)
  (import (srfi :262 extensible-match)))

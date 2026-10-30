;;; SRFI 275 tests: the sample implementation's tests/all.chezscheme.scm
;;; (https://github.com/scheme-requests-for-implementation/srfi-275, commit
;;; 33b4a8738fe17d267fb7b3806cb4a6788f60cb75; its test sections are in
;;; reference/srfi-275/tests), as one R6RS program: the internal
;;; libraries its last section imports, and Chez's format, which its
;;; sections use from Chez's REPL, are imported at the start, the
;;; sections are included from where they are here (test-setters.scm
;;; without the definitions it repeats, test-escaped.scm with a scheme's
;;; characters in Chez's order), an outer test group holds them,
;;; and the ending is the exit below.  Its encodings of every character
;;; a part of a URI can't hold take most of its two minutes.
;;; Timeout: 360
;; SPDX-FileCopyrightText: 2026 D. Guthrie <dguthrie@posteo.net>
;;;
;;; SPDX-License-Identifier: MIT
#!r6rs
(import (rnrs (6))
        (srfi :14 char-sets)
        (srfi :64 testing)
        (srfi :152 strings)
        (srfi :262 match)

        (srfi :275 iri)
        (srfi :275 uri)
        (srfi :275 normalize)
        (srfi :275 path)
        (srfi :275 utils)

        (only (srfi :275 internal resource-identifier)
              resource-identifier-raw-scheme
              resource-identifier-raw-user
              resource-identifier-raw-host
              resource-identifier-port
              resource-identifier-path
              resource-identifier-raw-query
              resource-identifier-raw-fragment
              relative-reference-raw-user
              relative-reference-raw-host
              relative-reference-port
              relative-reference-path
              relative-reference-raw-query
              relative-reference-raw-fragment)
        (only (srfi :275 internal iri)
              make-raw-relative-iri make-raw-iri)
        (only (srfi :275 internal uri)
              make-raw-relative-uri make-raw-uri)

        (only (chezscheme) include format))

(test-begin "srfi-275")

#| Inline internal utility procedures which aren't exported
   in the (srfi :275 xxx) namespace: |#

(define (flatten lists0)
    (let loop ([lists lists0] [rest '()])
      (match lists
        ['() rest]
        [(cons (list sg) tail)
         (cons sg (loop tail rest))]
        [(cons (cons a a*) tail)
         (cons a (loop (cons a* tail) rest))]
        [(cons head tail)
         (cons head (loop tail rest))]
        [_
         (error 'flatten "not a proper list" lists0)])))

(define (identity x) x)

(define (compose f . rest)
  (if (null? rest)
      f
      (let ([g (apply compose rest)])
	(lambda args
	  (call-with-values (lambda () (apply g args)) f)))))

(define uri-path-string (compose path->string uri-path))
(define iri-path-string (compose path->string iri-path))
(define uri-path-segments (compose path-segments uri-path))
(define iri-path-segments (compose path-segments iri-path))

(define (shift-percent-encoding k) (fx+ k 256))
(define (unshift-percent-encoding sk) (fx- sk 256))

(define (char->u8-list ch)
  (bytevector->u8-list
   (string->utf8 (string ch))))

(define (hex-digit n)
  (if (fx<? n 10)
      (fx+ 48 n)
      (fx+ 55 n)))

(define (percent-encoding->u8-list %enc)
  (call-with-values (lambda () (fxdiv-and-mod %enc 16))
    (lambda (char0 char1)
      (list #x25 (hex-digit char0) (hex-digit char1)))))

(define (percent-encoding->string %enc)
  (u8-list->string (percent-encoding->u8-list %enc)))

(define u8-list->string
  (compose utf8->string u8-list->bytevector))

#|
   The first six test suite sections are portable, and only depend on the
   exports defined in the (srfi :275 xxx) sub-libraries:
|#
(include "../reference/srfi-275/tests/test-misc.scm")
(include "../reference/srfi-275/tests/test-parse-segment.scm")
(include "../reference/srfi-275/tests/test-escaped.scm")
(include "../reference/srfi-275/tests/test-path.scm")
(include "../reference/srfi-275/tests/test-relative.scm")
(include "../reference/srfi-275/tests/test-setters.scm")
(include "../reference/srfi-275/tests/test-normalize.scm")

(let ((failures (test-runner-fail-count (test-runner-current))))
  (test-end "srfi-275")
  (exit (if (zero? failures) 0 1)))

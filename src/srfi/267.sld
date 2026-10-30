;;; SRFI 267: raw string syntax.  Peter McGoron's sample implementation
;;; (its lib/srfi/267.sld, unmodified below; MIT licence in
;;; reference/srfi-267/LICENSE).  The #"X"...""X" syntax itself is
;;; the reader's (src/read.scm), outside Racket mode, whose #"..." is a
;;; byte string.
;;; ; SPDX-FileCopyrightText: 2026 Peter McGoron, Alex Shinn
;;; ;
;;; ; SPDX-License-Identifier: MIT
(define-library (srfi 267)
  (import (scheme base) (scheme inexact) (scheme case-lambda)
          (srfi 117) (srfi 217))
  (export raw-string-read-error? raw-string-write-error?
          read-raw-string
          read-raw-string-after-prefix
          write-raw-string can-delimit?
          generate-delimiter)
  (begin
    (define-record-type <raw-string-read-error>
      (raw-string-read-error)
      raw-string-read-error?)
    (define-record-type <raw-string-write-error>
      (raw-string-write-error)
      raw-string-write-error?)
    (define read-raw-string-after-prefix
      (case-lambda
        (() (read-raw-string-after-prefix (current-input-port)))
        ((port)
         (define (read-char* location)
           (let ((ch (read-char port)))
             (if (eof-object? ch)
                 (raise (raw-string-read-error))
                 ch)))
         (define delimiter
           (do ((ch (read-char* 'delim) (read-char* 'delim))
                (acc '(#\") (cons ch acc)))
               ((char=? ch #\")
                (reverse (cons #\" acc)))))
         (call-with-port (open-output-string)
           (lambda (out)
             (define (read-delimiter n rest-of-delimiter)
               (if (null? rest-of-delimiter)
                   (get-output-string out)
                   (let ((ch (read-char* 'check)))
                     (if (char=? ch (car rest-of-delimiter))
                         (read-delimiter (+ n 1) (cdr rest-of-delimiter))
                         (do ((n n (- n 1))
                              (delimiter delimiter (cdr delimiter)))
                             ((zero? n) (read-raw ch))
                           (write-char (car delimiter) out))))))
             (define (read-raw ch)
               (if (char=? ch (car delimiter))
                   (read-delimiter 1 (cdr delimiter))
                   (begin (write-char ch out)
                          (read-raw (read-char* 'read)))))
             (read-raw (read-char* 'read)))))))
    (define read-raw-string
      (case-lambda
        (() (read-raw-string (current-input-port)))
        ((port)
         (unless (eqv? (peek-char port) #\#)
           (raise (raw-string-read-error)))
         (read-char port)
         (unless (eqv? (peek-char port) #\")
           (raise (raw-string-read-error)))
         (read-char port)
         (read-raw-string-after-prefix port))))
    (define (can-delimit? string delimiter)
      ;; This could be made significantly better.
      (call-with-port (open-input-string (string-append "#\""
                                                        delimiter
                                                        "\""
                                                        string
                                                        "\""
                                                        delimiter
                                                        "\""))
        (lambda (port)
          (equal? string (read-raw-string port)))))
    (define write-raw-string
      (case-lambda
        ((string delimiter) (write-raw-string string
                                              delimiter
                                              (current-output-port)))
        ((string delimiter port)
         (unless (can-delimit? string delimiter)
           (raise (raw-string-write-error)))
         (write-string "#\"" port)
         (write-string delimiter port)
         (write-string "\"" port)
         (write-string string port)
         (write-string "\"" port)
         (write-string delimiter port)
         (write-string "\"" port))))
    ;; generate-delimiter written by Alex Shinn, with some changes,
    ;; mostly to make it more imperative.
    ;;
    ;; The code assumes ASCII, Alex Shinn's original code
    ;; <https://srfi-email.schemers.org/srfi-267/msg/37898112/>
    ;; does not.
    (define (ascii-lower-case? ch)
      (let ((cp (char->integer ch)))
        (<= #x61 cp #x7A)))
    (define (ascii-upper-case? ch)
      (let ((cp (char->integer ch)))
        (<= #x41 cp #x5A)))
    (define (ascii-numeric? ch)
      (let ((cp (char->integer ch)))
        (<= #x30 cp #x39)))
    (define (char->base64-digit ch)
      ;; Returns #f if not an ASCII base64 digit.
      (let ((cp (char->integer ch)))
        (cond
          ((ascii-upper-case? ch)
           (- (char->integer ch) #x41))
          ((ascii-lower-case? ch)
           (+ (char->integer ch) 26 #x-61))
          ((ascii-numeric? ch)
           (+ (char->integer ch) 52 #x-30))
          ((char=? ch #\+) 62)
          ((char=? ch #\/) 63)
          (else #f))))
    (define (base64-digit->char i)
      (cond
        ((<= 0 i 25) (integer->char (+ #x41 i)))
        ((<= 26 i 51) (integer->char (+ #x61 (- i 26))))
        ((<= 52 i 61) (integer->char (+ #x61 (- i 52))))
        ((= i 62) #\+)
        ((= i 63) #\/)
        (else (error 'base64-digit->char "not base64" i))))
    ;; This uses SRFI 117 list queues instead of SRFI 134 immutable deques
    ;; because the latter have not yet been ported to CHICKEN 6.
    (define (find-non-substring str char->digit digit->char base)
      (let ((in (open-input-string str))
            (substring-len
             ;; This is to deal with the one-character string corner case
             (+ 1
                (exact (ceiling (/ (log (string-length str)) (log base)))))))
        (define (encode q)
          (do ((res 0 (+ (* res base) (car l)))
               (l (list-queue-list q) (cdr l)))
              ((null? l) res)))
        (define (decode n)
          (do ((n n (quotient n base))
               (i substring-len (- i 1))
               (port (open-output-string)))
              ((zero? i) (get-output-string port))
            (write-char (digit->char (modulo n base)) port)))
        ;; This loop reads through the string, collecting each base64
        ;; sequence that is exactly substring-len in length. It stores
        ;; the encoded value in an integer and stores it it in an integer
        ;; set.
        ;;
        ;; If it hits a non-base64 character, then the base64 sequence
        ;; that it was currently reading cannot be a base64 sequence that
        ;; will be generated by `decode`, so it discards it.
        (let lp ((seen (iset))
                 (q (list-queue))
                 (q-len 0))
          (let ((ch (read-char in)))
            (cond
              ((eof-object? ch)
               (decode (iset-min (iset-difference
                                  (make-range-iset 0 (expt base
                                                           substring-len))
                                  seen))))
              ((char->digit ch)
               => (lambda (i)
                    (list-queue-add-back! q i)
                    (let* ((full? (= substring-len q-len))
                           (seen (if full?
                                     (iset-adjoin seen (encode q))
                                     seen))
                           (q-len (if full?
                                      q-len
                                      (+ 1 q-len))))
                      (when full?
                        (list-queue-remove-front! q))
                      (lp seen q q-len))))
              (else
               (lp seen (list-queue) 0)))))))
    ;; Returns a sequence of base64 characters not found in str, choosing
    ;; the smallest length that can ensure such a sequence exists before
    ;; inspecting str.  Chooses the smallest unseen sequence within that
    ;; length, so likely to choose a base64-encoded 0 such as "A" or "AA".
    (define (generate-delimiter str)
      (if (zero? (string-length str))
          ""
          (find-non-substring str char->base64-digit base64-digit->char 64)))))
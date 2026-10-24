#lang racket/base
;; Places (src/racket/native/threads.lisp): each an SBCL thread with a
;; Racket instance of its own, messages copied between them
(require racket/place)
(define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))
(define (worker)
  (place ch (place-channel-put ch (fib (place-channel-get ch)))))
(define (run)
  (printf "enabled ~a\n" (place-enabled?))
  ;; several at once
  (define ps (for/list ([i 4]) (worker)))
  (for ([p ps] [n '(20 21 22 23)]) (place-channel-put p n))
  (printf "fibs ~a\n" (for/list ([p ps]) (place-channel-get p)))
  (printf "waits ~a\n" (map place-wait ps))
  ;; a message is copied: mutable parts made immutable
  (define echo (place ch (let ([v (place-channel-get ch)])
                           (place-channel-put ch (list v (immutable? (vector-ref v 1)))))))
  (place-channel-put echo (vector 'a (string #\b #\c) 3.5 '(1 . 2) #hash((k . v))))
  (printf "echo ~s\n" (place-channel-get echo))
  ;; a channel inside a message, and sync on one
  (define-values (a b) (place-channel))
  (define q (place ch (place-channel-put (place-channel-get ch) 'via-channel)))
  (place-channel-put q b)
  (printf "~a\n" (sync a))
  (place-wait q)
  ;; exit codes: an error's, exit's; place-kill; place-dead-evt
  (define e (parameterize ([current-error-port (open-output-string)]) (place ch (car 5))))
  (printf "error exit ~a\n" (place-wait e))
  (printf "exit ~a\n" (place-wait (place ch (exit 3))))
  (define k (place ch (let loop () (loop))))
  (place-kill k)
  (printf "killed ~a ~a\n" (place-wait k) (let ([d (place-dead-evt k)]) (eq? (sync d) d)))
  ;; output pumped into a port that isn't a file's
  (define s (open-output-string))
  (place-wait (parameterize ([current-output-port s]) (place ch (printf "from a place\n"))))
  (printf "captured ~s\n" (get-output-string s))
  (printf "allowed ~a ~a\n" (place-message-allowed? (vector 1 "x")) (place-message-allowed? (lambda () 1))))
(module+ main (run))

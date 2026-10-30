;;; SRFI 277: cyclic ports.  Wolfgang Corcoran-Mathe's R6RS sample
;;; implementation (reference/srfi-277/cyclic-ports.sls; MIT licence in
;;; reference/srfi-277/LICENSE): its two definitions, unmodified, in an
;;; R7RS library on the (rnrs) libraries it imports.
(define-library (srfi 277)
  (export open-cyclic-input-string
          open-cyclic-input-bytevector)
  (import (rnrs base)
          (rnrs bytevectors)
          (rnrs control)
          (rnrs io ports)
          (rnrs mutable-strings))
  (begin
  (define (open-cyclic-input-bytevector vec)
    (unless (and (bytevector? vec)
                 (not (zero? (bytevector-length vec))))
      (assertion-violation 'open-cyclic-input-bytevector
                           "argument must be a non-empty bytevector"
                           vec))
    (let ((len (bytevector-length vec))
          (pos 0))
      (make-custom-binary-input-port
       "cyclic bytevector port"
       (lambda (buf start count) ; read!
         (do ((i 0 (+ i 1)) ; index into buf
              (j pos (mod (+ j 1) len))) ; index into vec
             ((= i count)
              (set! pos j)
              count)
           (let ((b (bytevector-u8-ref vec j)))
             (bytevector-u8-set! buf (+ i start) b))))
       (lambda () pos)  ; get-position
       (lambda (new)
         (unless (< new len)
           (error 'set-port-position! "invalid position" new))
         (set! pos new))  ; set-position!
       #f)))

  (define (open-cyclic-input-string str)
    (unless (and (string? str) (not (equal? str "")))
      (assertion-violation 'open-cyclic-input-string
                           "argument must be a non-empty string"
                           str))
    ;; Data is read from a character vector instead of from *str*
    ;; itself, in case we are running in an O(n)-time string-ref
    ;; environment.
    (let ((len (string-length str))
          (char-vec (list->vector (string->list str)))
          (pos 0))
      (make-custom-textual-input-port
       "cyclic string port"
       (lambda (buf start count)  ; read!
         (do ((i 0 (+ i 1))  ; index into buf
              (j pos (mod (+ j 1) len)))  ; index into char-vec
             ((= i count)
              (set! pos j)
              count)
           (let ((c (vector-ref char-vec j)))
             (string-set! buf (+ i start) c))))
       (lambda () pos)  ; get-position
       (lambda (new) (set! pos new))  ; set-position!
       #f)))))

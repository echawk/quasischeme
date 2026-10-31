#lang racket/base
;; #:save-errno reads C's errno after the call (once a loop that never
;; returned: errno called itself).
(require ffi/unsafe)
(define c-open (get-ffi-obj "open" #f (_fun #:save-errno 'posix _path _int -> _int)))
(displayln (c-open "/nonexistent/quasischeme-test" 0))
(displayln (saved-errno))

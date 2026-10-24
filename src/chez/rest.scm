;;; -*- Mode: Scheme -*-
;;;; The rest of (chezscheme), as Chez Scheme 10's primdata.ss lists it:
;;;; what the other files of the library's body (src/chez/chez.lisp)
;;;; don't define.  The compiler's, the collector's and the profiler's
;;;; parameters are accepted and change nothing here, as the others in
;;;; top-level.scm; what needs Chez's own heap (reference bytevectors,
;;;; boot files, fasl's format) is left out (docs/chez.md).

;;; Boxes, pairs, vectors and strings

(define box-immutable %chez:box-immutable)
(define immutable-box? %chez:immutable-box?)
(define (mutable-box? x) (and (box? x) (not (immutable-box? x))))
(define car-cas! %chez:car-cas!)
(define cdr-cas! %chez:cdr-cas!)
(define (vector-set-fixnum! v i n)
  (unless (fixnum? n) (assertion-violation 'vector-set-fixnum! "not a fixnum" n))
  (vector-set! v i n))
;; Chez's immobile objects don't move; here no vector or bytevector of
;; Scheme's does but while pinned, so they're the ordinary ones
(define make-immobile-vector make-vector)
(define make-immobile-bytevector make-bytevector)
(define (box-immobile x) (box x))
(define (string-truncate! s n)
  (unless (string? s) (assertion-violation 'string-truncate! "not a mutable string" s))
  (unless (and (fixnum? n) (<= 0 n (string-length s)))
    (assertion-violation 'string-truncate! "invalid new length" n s))
  (%chez:string-truncate! s n))

;; LZ4 (compress-format's lz4); gzip isn't here
(define (bytevector-compress bv)
  (unless (eq? (compress-format) 'lz4)
    (assertion-violation 'bytevector-compress "gzip compression is not supported" bv))
  (%chez:bytevector-compress bv))
(define bytevector-uncompress %chez:bytevector-uncompress)

;;; Reference bytevectors (references as addresses: handles here)
(define make-reference-bytevector %chez:make-reference-bytevector)
(define make-immobile-reference-bytevector %chez:make-reference-bytevector)
(define reference-bytevector? %chez:reference-bytevector?)
(define bytevector-reference-set! %chez:bytevector-reference-set!)
(define bytevector-reference-ref %chez:bytevector-reference-ref)
(define bytevector-reference*-ref %chez:bytevector-reference*-ref)
(define object->reference-address %chez:object->reference-address)
(define reference-address->object %chez:reference-address->object)
(define reference*-address->object %chez:reference*-address->object)

;;; Phantom bytevectors: memory held outside the heap, counted by the
;;; collector in Chez; here only their length
(define-record-type (phantom-bytevector make-phantom-bytevector phantom-bytevector?)
  (nongenerative) (sealed #t)
  (fields (mutable length phantom-bytevector-length set-phantom-bytevector-length!)))

;;; Numbers

(define (conjugate z) (make-rectangular (real-part z) (- (imag-part z))))
(define (magnitude-squared z)
  (let ([x (real-part z)] [y (imag-part z)]) (+ (* x x) (* y y))))
;; log(1 + x), accurate for small x
(define (fllp x)
  (unless (flonum? x) (assertion-violation 'fllp "not a flonum" x))
  (let ([u (fl+ 1.0 x)])
    (if (fl= u 1.0) x (fl/ (fl* (log u) x) (fl- u 1.0)))))

;;; Unicode: grapheme clusters, by SBCL's rules

(define string-grapheme-span
  (case-lambda
    [(s start) (string-grapheme-span s start (string-length s))]
    [(s start end) (%chez:string-grapheme-span s start end)]))
(define string-grapheme-count
  (case-lambda
    [(s) (string-grapheme-count s 0 (string-length s))]
    [(s start) (string-grapheme-count s start (string-length s))]
    [(s start end) (%chez:string-grapheme-count s start end)]))
;; (char-grapheme-step char state): whether a cluster ends before CHAR,
;; and the next state; a state is 0 at the start, else the last character
(define (char-grapheme-step c state)
  (cond
    [(eqv? state 0) (values #f c)]
    [(char? state) (values (%chez:grapheme-break? state c) c)]
    [else (assertion-violation 'char-grapheme-step "invalid state" state)]))

;;; Ports

(define (unget-u8 p octet) (%chez:unget-u8 p octet))
(define (unget-char p c) (unread-char c p))
(define set-port-eof! %chez:set-port-eof!)
(define port-bol? %chez:port-bol?)
(define (set-port-bol! p bol?) (void))
(define truncate-port
  (case-lambda [(p) (%chez:truncate-port p 0)] [(p pos) (%chez:truncate-port p pos)]))
(define input-port-ready? %chez:input-port-ready?)
(define (port-has-port-nonblocking?? p) #f)
(define (port-has-set-port-nonblocking!? p) #f)
(define (port-output-count p) (- (port-output-size p) (port-output-index p)))
(define (port-output-full? p) (>= (port-output-index p) (port-output-size p)))
(define textual-port-output-count port-output-count)
;; a binary port's buffer: a generic port's, as the textual ones'
(define binary-port-input-buffer port-input-buffer)
(define binary-port-input-size port-input-size)
(define binary-port-input-index port-input-index)
(define binary-port-input-count port-input-count)
(define binary-port-output-buffer port-output-buffer)
(define binary-port-output-size port-output-size)
(define binary-port-output-index port-output-index)
(define binary-port-output-count port-output-count)
(define set-binary-port-input-buffer! set-port-input-buffer!)
(define set-binary-port-input-index! set-port-input-index!)
(define set-binary-port-input-size! set-port-input-size!)
(define set-binary-port-output-buffer! set-port-output-buffer!)
(define set-binary-port-output-index! set-port-output-index!)
(define set-binary-port-output-size! set-port-output-size!)
(define custom-port-buffer-size (make-parameter 1024))
(define transcoded-port-buffer-size (make-parameter 1024))
(define get-string-some
  (lambda (p)
    (let ([c (get-char p)])
      (if (eof-object? c)
          c
          (let loop ([acc (list c)])
            (if (and (input-port-ready? p) (not (eof-object? (peek-char p))))
                (loop (cons (get-char p) acc))
                (list->string (reverse acc))))))))
(define (get-string-some! p s start n)
  (let ([got (get-string-n! p s start (min n 1))])
    (if (or (eof-object? got) (= n 1))
        got
        (let loop ([i (+ start got)] [k got])
          (if (and (< k n) (input-port-ready? p) (not (eof-object? (peek-char p))))
              (begin (string-set! s i (get-char p)) (loop (+ i 1) (+ k 1)))
              k)))))
(define (put-string-some p s . range)
  (let* ([start (if (pair? range) (car range) 0)]
         [n (if (and (pair? range) (pair? (cdr range))) (cadr range) (- (string-length s) start))])
    (put-string p s start n)
    n))
(define (open-input-output-file path . options)
  (open-file-input/output-port path (file-options no-fail no-truncate) (buffer-mode block)
                               (native-transcoder)))
(define (pretty-file in out)
  (call-with-output-file out
    (lambda (o)
      (call-with-input-file in
        (lambda (i)
          (let loop ()
            (let ([x (read i)])
              (unless (eof-object? x) (pretty-print x o) (newline o) (loop)))))))))
;; codecs Chez gets from iconv: the ones here, by name
(define (iconv-codec name)
  (cond
    [(member (string-downcase name) '("utf-8" "utf8")) (utf-8-codec)]
    [(member (string-downcase name) '("latin1" "latin-1" "iso-8859-1" "iso8859-1")) (latin-1-codec)]
    [(member (string-downcase name) '("utf-16" "utf16")) (utf-16-codec)]
    [else (assertion-violation 'iconv-codec "unsupported encoding" name)]))
(define (utf-16le-codec) (utf-16-codec))
(define (utf-16be-codec) (utf-16-codec))

;;; Records and conditions

(define print-record (make-parameter #t ->boolean))
(define (record-instance? x) (and (record? x) #t))
(define (record-type-has-named-fields? rtd)
  (unless (record-type-descriptor? rtd)
    (assertion-violation 'record-type-has-named-fields? "not a record-type descriptor" rtd))
  #t)
(define require-nongenerative-clause (make-parameter #f ->boolean))
(define-condition-type &source &condition make-source-condition source-condition?
  (form source-condition-form))
(define (condition-name c) #f)
(define default-exception-handler
  (lambda (c)
    (if (and (warning? c) (not (serious-condition? c)))
        (begin (display-condition c (console-output-port)) (newline (console-output-port)))
        (begin (display-condition c (console-output-port)) (newline (console-output-port)) (reset)))))
(define debug-on-exception (make-parameter #f ->boolean))
(define (debug-condition . c) #f)
(define break-handler (make-parameter (lambda args (void))))

;;; Environments and the top level

(define (environment? x)
  (or (top-level-environment? x) (%psyntax:environment? x)))
(define (environment-mutable? env) (top-level-environment? env))
(define (ieee-environment) (environment '(rnrs) '(rnrs r5rs)))
(define (define-top-level-syntax s v . env)
  (eval `(define-syntax ,s ,v) (interaction-environment)))
(define (top-level-syntax? s . env)
  (and (memq s (environment-symbols (if (pair? env) (car env) (interaction-environment))))
       (not (top-level-bound? s))))
(define (top-level-syntax s . env)
  (unless (top-level-syntax? s) (assertion-violation 'top-level-syntax "not defined as syntax" s))
  s)
(define (apropos-list x . env)
  (let ([pat (if (symbol? x) (symbol->string x) x)]
        [e (if (pair? env) (car env) (interaction-environment))])
    (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b)))
               (filter (lambda (s) (string-search pat (symbol->string s))) (environment-symbols e)))))
(define (string-search pat s)
  (let ([n (string-length pat)] [m (string-length s)])
    (let loop ([i 0]) (and (<= (+ i n) m) (or (string=? pat (substring s i (+ i n))) (loop (+ i 1)))))))
(define (apropos x . env)
  (for-each (lambda (s) (display s) (newline)) (apply apropos-list x env)))
(define (invoke-library ref) (eval `(import ,ref) (interaction-environment)) (void))
(define with-source-path
  (lambda (who name k)
    (let loop ([dirs (source-directories)])
      (if (null? dirs)
          (if (file-exists? name) (k name) (assertion-violation who "file not found in source directories" name))
          (let ([path (if (string=? (car dirs) ".") name (string-append (car dirs) "/" name))])
            (if (file-exists? path) (k path) (loop (cdr dirs))))))))
;; expand/optimize: the expanded form, which is the form here (expand)
(define (expand/optimize x . env) x)
(define expand-output (make-parameter #f))
(define expand/optimize-output (make-parameter #f))
(define eval-syntax-expanders-when (make-parameter '(compile load eval)))
(define expand-omit-library-invocations (make-parameter #f ->boolean))
(define scheme-start (make-parameter (lambda args (void))))
(define scheme-script (make-parameter (lambda (path . args) (load path))))
(define scheme-program (make-parameter (lambda (path . args) (load-program path))))
(define suppress-greeting (make-parameter #f ->boolean))
(define (scheme-pre-release) #f)

;;; The REPL ("cafe") and transcripts

(define waiter-prompt-string (make-parameter ">"))
(define waiter-write (make-parameter (lambda (x) (unless (eq? x (void)) (pretty-print x)))))
(define waiter-prompt-and-read
  (make-parameter (lambda (n)
                    (display (waiter-prompt-string) (console-output-port))
                    (display " " (console-output-port))
                    (flush-output-port (console-output-port))
                    (read (console-input-port)))))
(define default-prompt-and-read (waiter-prompt-and-read))
(define (new-cafe . eval-proc)
  (let ([ev (if (pair? eval-proc) (car eval-proc) eval)])
    (call/cc
      (lambda (k)
        (let loop ()
          (let ([x ((waiter-prompt-and-read) 1)])
            (if (eof-object? x)
                (begin (newline (console-output-port)) (k (void)))
                (begin (call-with-values (lambda () (ev x)) (lambda vs (for-each (waiter-write) vs)))
                       (loop)))))))))
(define transcript-port #f)
(define (transcript-on path) (set! transcript-port (open-output-file path)) (void))
(define (transcript-off)
  (when transcript-port (close-port transcript-port) (set! transcript-port #f))
  (void))
(define (transcript-cafe path) (transcript-on path) (new-cafe) (transcript-off))
(define trace-print (make-parameter pretty-print))

;;; The compiler's parameters, and the entry points that need Chez's

(define compile-omit-concatenate-support (make-parameter #f ->boolean))
(define compile-procedure-realm (make-parameter #f))
(define compile-profile (make-parameter #f))
(define cp0-effort-limit (make-parameter 200))
(define cp0-outer-unroll-limit (make-parameter 0))
(define cp0-score-limit (make-parameter 20))
(define run-cp0 (make-parameter (lambda (cp0 x) (cp0 x))))
(define enable-arithmetic-left-associative (make-parameter #f ->boolean))
(define enable-cross-library-optimization (make-parameter #t ->boolean))
(define enable-error-source-expression (make-parameter #t ->boolean))
(define enable-type-recovery (make-parameter #t ->boolean))
(define enable-unsafe-application (make-parameter #f ->boolean))
(define enable-unsafe-variable-reference (make-parameter #f ->boolean))
(define generate-allocation-counts (make-parameter #f ->boolean))
(define generate-covin-files (make-parameter #f ->boolean))
(define generate-instruction-counts (make-parameter #f ->boolean))
(define generate-profile-forms (make-parameter #t ->boolean))
(define self-evaluating-vectors (make-parameter #f ->boolean))
(define subset-mode (make-parameter #f))
(define current-errno-source (make-parameter #f))
(define (compile-port in out . rest)
  (let loop ()
    (let ([x (read in)])
      (unless (eof-object? x) (eval x) (loop)))))
(define (visit-compiled-from-port p) (compile-port p #f))
(define (revisit-compiled-from-port p) (compile-port p #f))
(define (not-supported who) (lambda args (assertion-violation who "not supported: needs Chez's own boot and fasl formats")))
(define make-boot-file (not-supported 'make-boot-file))
(define make-boot-header (not-supported 'make-boot-header))
(define pbchunk-convert-file (not-supported 'pbchunk-convert-file))
(define vfasl-convert-file (not-supported 'vfasl-convert-file))
(define strip-fasl-file (not-supported 'strip-fasl-file))
(define fasl-compressed (make-parameter #t ->boolean))
;; fasl: Chez's format is its heap's; here a datum written in a form read
;; gives back, the fasl-write object's
(define (fasl-write x p . rest)
  (put-bytevector p (string->utf8 (call-with-string-output-port (lambda (o) (write x o) (newline o))))))
(define (fasl-read p . rest)
  (let ([line (let loop ([acc '()])
                (let ([b (get-u8 p)])
                  (cond [(eof-object? b) (if (null? acc) b (u8-list->bytevector (reverse acc)))]
                        [(= b 10) (u8-list->bytevector (reverse acc))]
                        [else (loop (cons b acc))])))])
    (if (eof-object? line) line (read (open-string-input-port (utf8->string line))))))
(define (fasl-file in out)
  (call-with-port (open-file-output-port out (file-options no-fail))
    (lambda (o)
      (call-with-input-file in
        (lambda (i) (let loop () (let ([x (read i)]) (unless (eof-object? x) (fasl-write x o) (loop)))))))))

;;; The collector, storage and statistics

(define collections %chez:collections)
(define collect-generation-radix (make-parameter 4))
(define collect-maximum-generation-threshold-factor (make-parameter 2))
(define collect-notify (make-parameter #f ->boolean))
(define in-place-minimum-generation (make-parameter 4))
(define release-minimum-generation (make-parameter 4))
(define heap-reserve-ratio (make-parameter 1.0))
(define compute-size
  (case-lambda [(x) (%chez:compute-size x)] [(x g) (%chez:compute-size x)]))
(define compute-size-increments
  (case-lambda [(xs) (map compute-size xs)] [(xs g) (map compute-size xs)]))
(define compute-composition
  (case-lambda [(x) (%chez:compute-composition x)] [(x g) (%chez:compute-composition x)]))
(define (object-counts) '())
(define (make-object-finder pred . rest) (lambda () #f))
(define display-statistics
  (case-lambda
    [() (display-statistics (current-output-port))]
    [(p) (sstats-print (statistics) p)]))
(define gensym-prefix (make-parameter "g"))
(define gensym-count (make-parameter 0))

;;; Cost centers and the profiler: times and allocation, no instruction
;;; counts

(define-record-type cost-center
  (nongenerative) (sealed #t)
  (fields name (mutable time) (mutable allocation) (mutable instructions) (mutable depth))
  (protocol (lambda (new)
              (case-lambda
                [() (new #f (make-time 'time-duration 0 0) 0 0 0)]
                [(name) (new name (make-time 'time-duration 0 0) 0 0 0)]))))
(define (with-cost-center . args)
  (let* ([cc (if (= (length args) 3) (cadr args) (car args))]
         [thunk (if (= (length args) 3) (caddr args) (cadr args))]
         [t0 (current-time 'time-process)] [b0 (bytes-allocated)])
    (dynamic-wind
      (lambda () (cost-center-depth-set! cc (+ (cost-center-depth cc) 1)))
      thunk
      (lambda ()
        (cost-center-depth-set! cc (- (cost-center-depth cc) 1))
        (cost-center-time-set! cc (add-duration (cost-center-time cc) (time-difference (current-time 'time-process) t0)))
        (cost-center-allocation-set! cc (+ (cost-center-allocation cc) (- (bytes-allocated) b0)))))))
(define (cost-center-allocation-count cc) (cost-center-allocation cc))
(define (cost-center-instruction-count cc) (cost-center-instructions cc))
(define (reset-cost-center! cc)
  (cost-center-time-set! cc (make-time 'time-duration 0 0))
  (cost-center-allocation-set! cc 0)
  (cost-center-instructions-set! cc 0))
(define (profile-clear) (void))
(define (profile-clear-database) (void))
(define (profile-dump) '())
(define (profile-dump-list . rest) '())
(define (profile-dump-data path . rest) (call-with-output-file path (lambda (o) (write '() o))))
(define (profile-dump-html . rest) (void))
(define (profile-load-data . paths) (void))
(define (profile-release-counters) (void))
(define (profile-query-weight x) #f)
(define profile-line-number-color (make-parameter #f))
(define profile-palette (make-parameter '#()))
(define with-profile-tracker
  (case-lambda
    [(thunk) (with-profile-tracker #f thunk)]
    [(preserve? thunk) (call-with-values thunk (lambda vs (apply values (append vs (list '())))))]))

;;; Source tables: source objects to values

(define-record-type source-table
  (nongenerative) (sealed #t)
  (fields (immutable ht))
  (protocol (lambda (new) (lambda () (new (make-eq-hashtable))))))
(define (source-table-set! t src v) (hashtable-set! (source-table-ht t) src v))
(define (source-table-ref t src default) (hashtable-ref (source-table-ht t) src default))
(define (source-table-contains? t src) (hashtable-contains? (source-table-ht t) src))
(define (source-table-delete! t src) (hashtable-delete! (source-table-ht t) src))
(define (source-table-size t) (hashtable-size (source-table-ht t)))
(define (source-table-cell t src default)
  (let ([ht (source-table-ht t)])
    (unless (hashtable-contains? ht src) (hashtable-set! ht src (cons src default)))
    (let ([v (hashtable-ref ht src #f)])
      (if (pair? v) v (let ([c (cons src v)]) (hashtable-set! ht src c) c)))))
(define (source-table-dump t)
  (let-values ([(ks vs) (hashtable-entries (source-table-ht t))])
    (map (lambda (k v) (cons k (if (and (pair? v) (eq? (car v) k)) (cdr v) v)))
         (vector->list ks) (vector->list vs))))
(define (put-source-table p t)
  (for-each (lambda (e)
              (let ([src (car e)])
                (write (list (source-file-descriptor-path (source-object-sfd src))
                             (source-object-bfp src) (source-object-efp src) (cdr e))
                       p)
                (newline p)))
            (source-table-dump t)))
(define get-source-table!
  (case-lambda
    [(p t) (get-source-table! p t #f)]
    [(p t combine)
     (let loop ()
       (let ([x (read p)])
         (unless (eof-object? x)
           (let* ([sfd (make-source-file-descriptor (car x) (open-bytevector-input-port (bytevector)))]
                  [src (make-source-object sfd (cadr x) (caddr x))]
                  [v (cadddr x)])
             (source-table-set! t src v))
           (loop))))]))

;;; Windows' registry and foreign entries

(define (get-registry key) #f)
(define (put-registry! key v) (assertion-violation 'put-registry! "no registry: not Windows"))
(define (remove-registry! key) (assertion-violation 'remove-registry! "no registry: not Windows"))
(define (multibyte->string cp bv) (assertion-violation 'multibyte->string "not Windows"))
(define (string->multibyte cp s) (assertion-violation 'string->multibyte "not Windows"))
(define (remove-foreign-entry name)
  (unless (foreign-entry? name) (assertion-violation 'remove-foreign-entry "no entry" name))
  (void))
(define (foreign-address-name addr) #f)
(define (foreign-alignof type) (foreign-sizeof type))
(define (make-codec-buffer . args) (make-bytevector 1024))

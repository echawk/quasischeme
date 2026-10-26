
; Scheme48's READ module, adapted for use in Quasischeme.
; (compile-file "~/pseudo/read" scheme-translator::revised^4-scheme-env)
; (load "~/pseudo/read" scheme-translator::revised^4-scheme-env)
; (define read revised^4-scheme:.read)

(define char->ascii #'qs-lisp:char-code)
(define ascii->char #'qs-lisp:code-char)
(define ascii-whitespaces '(32 10 9 12 13)) ;space linefeed tab page return
(define ascii-limit 128)

(define (reverse-list->string l n)
  ;; Significantly faster than (list->string (reverse l))
  (let ((s (make-string n #\x)))
    (let loop ((i (- n 1)) (l l))
      (if (< i 0)
	  s
	  (begin (string-set! s i (car l))
		 (loop (- i 1) (cdr l)))))))


(define (input-port-option port-option)
  (cond ((null? port-option) (current-input-port))
	((null? (cdr port-option)) (car port-option))
	(else (error "read-mumble: too many arguments" port-option))))

(define error #'qs:scheme-error)
(define warn #'qs:scheme-warn)


; -*- Mode: Scheme; Syntax: Scheme; Package: Scheme; -*-
; Copyright (c) 1993 by Richard Kelsey and Jonathan Rees.  See file COPYING.


; A little Scheme reader.

; Nonstandard things used:
;  Ascii stuff: char->ascii, ascii->char, ascii-whitespaces, ascii-limit
;    (for dispatch table; portable definitions in alt/ascii.scm)
;  reverse-list->string  -- ok to define as follows:
;    (define (reverse-list->string l n)
;      (list->string (reverse l)))
;  really-string->symbol -- ok to define as follows:
;    ;  signal (only for use by reading-error; easily excised)


(define (scheme-read . port-option)
  (let ((port (input-port-option port-option)))
    (qs:call-with-reader-state
     port
     (lambda ()
       (let ((form (sub-read port)))
	 ;; A token here is an unexpected ) or ., an error (R7RS 6.13.2).
	 (if (reader-token? form)
	     (reading-error port (cdr form))
	     (datum-of form)))))))

; A datum the reader looks into itself (a character's name, a labelled
; datum, a box's contents): read without annotations.
(define (sub-read-plain port)
  (qs:call-without-annotating (lambda () (sub-read-carefully port))))

(define (sub-read-carefully port)
  (let ((form (sub-read port)))
    (cond ((eof-object? form)
           (reading-error port "unexpected end of file"))
	  ((reader-token? form) (reading-error port (cdr form)))
	  (else (datum-of form)))))

; Chez Scheme's #!eof, the end-of-file object as a datum: read as this
; marker, so that a list or the like doesn't take it for the file's end.
(define eof-datum (list 'eof-datum))
(define (datum-of form) (if (eq? form eof-datum) qs:eof-object form))

(define reader-token-marker (list 'reader-token))
(define (make-reader-token message) (cons reader-token-marker message))
(define (reader-token? form)
  (and (pair? form) (eq? (car form) reader-token-marker)))

(define close-paren (make-reader-token "unexpected right parenthesis"))
(define close-bracket (make-reader-token "unexpected right bracket"))

; Does FORM close the list opened by C?  ( and [ close with either )
; or ], except in Chez Scheme's reader, where they must match.
(define (closes? form c port)
  (cond ((not (or (eq? form close-paren) (eq? form close-bracket))) #f)
	((not (qs:true? (qs:chez-reader-p))) #t)
	((and (eqv? c #\() (eq? form close-bracket))
	 (reading-error port "parenthesized list terminated by close bracket"))
	((and (eqv? c #\[) (eq? form close-paren))
	 (reading-error port "bracketed list terminated by close parenthesis"))
	(else #t)))
(define dot         (make-reader-token "unexpected \" . \""))


; Main dispatch

; Characters beyond the dispatch tables (anything non-ASCII) are
; whitespace if Unicode says so, and otherwise symbol constituents, as
; R6RS and R7RS allow for most of Unicode.

(define (sub-read port)
  ;; the host reads whitespace, before an annotation's start is taken
  (qs:skip-whitespace port)
  (let* ((start (and (qs:true? (qs:annotating-p)) (qs:reader-position port)))
	 (form (sub-read-1 port))
	 (form (if (and (qs:neoteric-p) (not (eof-object? form)) (not (reader-token? form)))
		   (neoteric-suffixes form port)
		   form)))
    ;; Chez's annotations, while a file is read for them: a datum read
    ;; after atmosphere already has its own
    (if (and start (not (eof-object? form)) (not (reader-token? form))
	     (not (eq? form eof-datum)) (not (qs:true? (qs:annotated-p form))))
	(qs:reader-annotate form port start)
	form)))

(define (sub-read-1 port)
  (let ((c (read-char port)))
    (cond ((eof-object? c) c)
	  ((>= (char->ascii c) ascii-limit)
	   (if (char-whitespace? c)
	       (sub-read port)
	       (parse-token (sub-read-symbol-token c port) port)))
	  (else
	   ((vector-ref read-dispatch-vector (char->ascii c))
	    c port)))))

(define (terminating? c)
  (if (< (char->ascii c) ascii-limit)
      (vector-ref read-terminating?-vector (char->ascii c))
      (char-whitespace? c)))

(define read-dispatch-vector
  (make-vector ascii-limit
               (lambda (c port)
                 (reading-error port "illegal character read" c))))

(define read-terminating?-vector
  (make-vector ascii-limit #t))

(define (set-standard-syntax! char terminating? reader)
  (vector-set! read-dispatch-vector     (char->ascii char) reader)
  (vector-set! read-terminating?-vector (char->ascii char) terminating?))

(let ((sub-read-whitespace
       (lambda (c port)
         c                              ;ignored
         (sub-read port))))
  (for-each (lambda (c)
              (vector-set! read-dispatch-vector c sub-read-whitespace))
            ascii-whitespaces))

(let ((sub-read-constituent
       (lambda (c port)
	 (let ((token (sub-read-symbol-token c port)))
	   ;; SRFIs 108 and 109: &{...} and &name{...}, &name[...]{...}
	   (if (and (char=? c #\&) (null? (cdr token))
		    (let ((next (peek-char port)))
		      (and (char? next) (or (char=? next #\{) (char=? next #\[)))))
	       (qs:read-quasi-literal (substring (car token) 1 (string-length (car token))) port)
	       (parse-token token port))))))
  (for-each (lambda (c)
              (set-standard-syntax! c #f sub-read-constituent))
            (string->list
             (string-append "!$%&*+-./0123456789:<=>?@^_~ABCDEFGHIJKLM"
                            "NOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz\\"))))

; Usual read macros

(define (set-standard-read-macro! c terminating? proc)
  (set-standard-syntax! c terminating? proc))

(define (sub-read-list c port)
  (let ((form (sub-read port)))
    (cond ((eof-object? form)
           (reading-error port
			  "end of file inside list -- unbalanced parentheses"))
          ((closes? form c port) '())
	  ;; A dot needs a datum before it, (#;a . b) included.
          ((eq? form dot)
	   (reading-error port "nothing before \" . \" in a list"))
          (else (cons (datum-of form) (sub-read-list-tail c port))))))

(define (sub-read-list-tail c port)
  (let ((form (sub-read port)))
    (cond ((eof-object? form)
           (reading-error port
			  "end of file inside list -- unbalanced parentheses"))
          ((closes? form c port) '())
          ((eq? form dot)
           (let* ((last-form (sub-read-carefully port))
                  (another-form (sub-read port)))
             (cond ((closes? another-form c port) last-form)
                   (else
                    (reading-error port
				   "randomness after form after dot"
				   another-form)))))
          (else (cons (datum-of form) (sub-read-list-tail c port))))))

(set-standard-read-macro! #\( #t sub-read-list)

; R6RS 4.2.1: brackets are parentheses.  (Not checked for matching.)

(set-standard-read-macro! #\[ #t sub-read-list)

(set-standard-read-macro! #\] #t
  (lambda (c port)
    c port
    close-bracket))

; SRFI 105: {a + b} is (+ a b), and within curly braces f(x) is (f x),
; x[i] is ($bracket-apply$ x i) and f{a + b} is (f (+ a b)).  (Braces
; and brackets aren't checked for matching either.)

(set-standard-read-macro! #\{ #t
  (lambda (c port)
    (sub-read-curly c port)))

(set-standard-read-macro! #\} #t
  (lambda (c port)
    c port
    close-paren))

(define (sub-read-curly c port)
  (curly-infix (qs:call-neoterically (lambda () (sub-read-list c port)))))

(define (curly-infix es)
  (cond ((not (list? es)) (cons '$nfx$ es))
	((null? es) '())
	((null? (cdr es)) (car es))
	((null? (cddr es)) es)
	((simple-infix? es) (cons (cadr es) (every-other es)))
	(else (cons '$nfx$ es))))

; An odd number of elements, at least three, with the same operator
; between each pair.
(define (simple-infix? es)
  (let ((op (cadr es)))
    (let loop ((rest (cdr es)))		;at an operator
      (cond ((null? rest) #f)
	    ((not (equal? (car rest) op)) #f)
	    ((null? (cdr rest)) #f)
	    ((null? (cddr rest)) #t)
	    (else (loop (cddr rest)))))))

(define (every-other es)
  (if (null? es)
      '()
      (cons (car es) (if (null? (cdr es)) '() (every-other (cddr es))))))

; The arguments of f(...), which may be f(. args): (f . args).
(define (sub-read-arguments c port)
  (let ((form (sub-read port)))
    (cond ((eq? form dot)
	   (let* ((tail (sub-read-carefully port))
		  (close (sub-read port)))
	     (if (closes? close c port)
		 tail
		 (reading-error port "randomness after form after dot" close))))
	  ((eof-object? form)
	   (reading-error port "end of file inside list -- unbalanced parentheses"))
	  ((closes? form c port) '())
	  (else (cons (datum-of form) (sub-read-list-tail c port))))))

(define (neoteric-suffixes form port)
  (let ((c (peek-char port)))
    (cond ((eqv? c #\()
	   (read-char port)
	   (neoteric-suffixes (cons form (sub-read-arguments c port)) port))
	  ((eqv? c #\[)
	   (read-char port)
	   (neoteric-suffixes (cons '$bracket-apply$ (cons form (sub-read-list c port))) port))
	  ((eqv? c #\{)
	   (read-char port)
	   (let ((curly (sub-read-curly c port)))
	     (neoteric-suffixes (if (null? curly) (list form) (list form curly)) port)))
	  (else form))))

; |symbol| with any characters (R7RS 2.1): \| \\ and \x<hex>; escapes.
; The name is taken exactly as written, with no case folding.

(set-standard-read-macro! #\| #t
  (lambda (c port)
    c
    (let loop ((l '()) (i 0))
      (let ((c (read-char port)))
	(cond ((eof-object? c)
	       (reading-error port "end of file within |symbol|"))
	      ((char=? c #\|)
	       (let ((p (peek-char port)))
		 ;; Chez: the symbol goes on, |a b|c is "a bc"
		 (if (and (qs:true? (qs:chez-reader-p)) (char? p) (not (terminating? p)))
		     (let ((rest (sub-read-symbol-token (read-char port) port)))
		       (qs:intern-scheme-symbol (string-append (reverse-list->string l i) (car rest))))
		     (qs:intern-scheme-symbol (reverse-list->string l i)))))
	      ((char=? c #\\)
	       (loop (cons (read-escape port) l) (+ i 1)))
	      (else (loop (cons c l) (+ i 1))))))))

(set-standard-read-macro! #\) #t
  (lambda (c port)
    c port
    close-paren))

(set-standard-read-macro! #\' #t
  (lambda (c port)
    c
    (list 'quote (sub-read-carefully port))))

(set-standard-read-macro! #\` #t
  (lambda (c port)
    c
    (list 'quasiquote (sub-read-carefully port))))

(set-standard-read-macro! #\, #t
  (lambda (c port)
    c
    (let* ((next (peek-char port))
	   ;; DO NOT beta-reduce!
	   (keyword (cond ((eof-object? next)
			   (reading-error port "end of file after ,"))
			  ((char=? next #\@)
			   (read-char port)
			   'unquote-splicing)
			  (else 'unquote))))
      (list keyword
            (sub-read-carefully port)))))

; String escapes: \\ and \" are the only ones R5RS requires, but \n \t
; \r \a \b \0 are standard as of R6RS/R7RS and are such common Scheme
; (and C) idiom that most R5RS implementations already accept them too
; -- and chibi's own R5RS test suite relies on \n. A backslash before
; any other character is read as that character literally, same as
; before.

; READ-ESCAPE reads what follows a backslash in a string or |symbol|:
; the one-character escapes above, or \x<hex>; (R6RS/R7RS).

(define (read-escape port)
  (let ((c (read-char port)))
    (cond ((eof-object? c)
	   (reading-error port "end of file after \\"))
	  ((char=? c #\x)
	   (let loop ((digits '()))
	     (let ((d (read-char port)))
	       (cond ((eof-object? d)
		      (reading-error port "end of file in \\x escape"))
		     ((char=? d #\;)
		      (let ((n (string->number (list->string (reverse digits)) 16)))
			(if n
			    (ascii->char n)
			    (reading-error port "bad \\x escape"))))
		     (else (loop (cons d digits)))))))
	  ((qs:true? (qs:chez-reader-p)) (chez-read-string-escape c port))
	  (else (string-escape-char c)))))

(define (string-escape-char c)
  (cond ((char=? c #\n) #\newline)
	((char=? c #\t) #\tab)
	((char=? c #\r) #\return)
	((char=? c #\a) (ascii->char 7))
	((char=? c #\b) (ascii->char 8))
	((char=? c #\v) (ascii->char 11))
	((char=? c #\f) (ascii->char 12))
	((char=? c #\0) (ascii->char 0))
	(else c)))

; Chez Scheme's escapes: those of R6RS, and \ooo, three octal digits
; of a character code below 256; any other is an error

(define (chez-read-string-escape c port)
  (cond ((memv c '(#\n #\t #\r #\a #\b #\v #\f)) (string-escape-char c))
	((memv c '(#\\ #\" #\' #\|)) c)
	((octal-digit? c)
	 (let* ((d (read-char port)) (e (read-char port)))
	   (if (and (char? d) (char? e) (octal-digit? d) (octal-digit? e))
	       (let ((n (+ (* 64 (octal-value c)) (* 8 (octal-value d)) (octal-value e))))
		 (if (< n 256)
		     (ascii->char n)
		     (reading-error port "invalid string character" c d e)))
	       (reading-error port "invalid string character" c))))
	(else (reading-error port "invalid string character" c))))

(define (octal-digit? c) (and (char<=? #\0 c) (char<=? c #\7)))
(define (octal-value c) (- (char->ascii c) (char->ascii #\0)))

(define (skip-line-continuation port)
  (let skip-before ()
    (let ((c (read-char port)))
      (cond ((eof-object? c) c)
	    ((char=? c #\newline)
	     (let skip-after ()
	       (let ((d (peek-char port)))
		 (if (and (char? d) (or (char=? d #\space) (char=? d #\tab)))
		     (begin (read-char port) (skip-after))))))
	    (else (skip-before))))))

(set-standard-read-macro! #\" #t
  (lambda (c port)
    c ;ignored
    (let loop ((l '()) (i 0))
      (let ((c (read-char port)))
        (cond ((eof-object? c)
               (reading-error port "end of file within a string"))
              ((char=? c #\\)
	       (let ((next (peek-char port)))
		 (cond ((eof-object? next)
			(reading-error port "end of file within a string"))
		       ;; \<intraline whitespace><newline><intraline
		       ;; whitespace>: a line continuation, read as nothing.
		       ((or (char=? next #\newline) (char=? next #\space)
			    (char=? next #\tab))
			(skip-line-continuation port)
			(loop l i))
		       (else
			(loop (cons (read-escape port) l) (+ i 1))))))
              ((char=? c #\")
	       (reverse-list->string l i))
              (else
	       (loop (cons c l) (+ i 1))))))))

(set-standard-read-macro! #\; #t
  (lambda (c port)
    c ;ignored
    (gobble-line port)
    (sub-read port)))

(define (gobble-line port)
  (let loop ()
    (let ((c (read-char port)))
      (cond ((eof-object? c) c)
	    ((char=? c #\newline) #f)
	    (else (loop))))))

(define *sharp-macros* '())

(define (define-sharp-macro c proc)
  (set! *sharp-macros* (cons (cons c proc) *sharp-macros*)))

(set-standard-read-macro! #\# #f
  (lambda (c port)
    c ;ignored
    (let* ((c (peek-char port))
	   (c (if (eof-object? c)
		  (reading-error port "end of file after #")
		  (char-downcase c)))
	   (probe (assq c *sharp-macros*)))
      (if (and (r6rs-strict? port)
	       (not (memv c '(#\( #\t #\f #\\ #\; #\| #\! #\' #\` #\, #\v
			      #\x #\b #\o #\d #\e #\i))))
	  (not-in-r6rs port (string #\# c)))
      (if probe
	  ((cdr probe) c port)
	  (reading-error port "unknown # syntax" c)))))

; #t #f and R7RS's #true #false.

(define (sharp-boolean value long-name)
  (lambda (c port)
    c
    (let ((name (car (sub-read-token (read-char port) port))))
      (if (and (> (string-length name) 1) (r6rs-strict? port))
	  (not-in-r6rs port "alternative boolean"))
      (if (or (= (string-length name) 1)
	      (string=? (common-lisp:string-downcase name) long-name))
	  value
	  (reading-error port "unknown # syntax" name)))))

(define-sharp-macro #\f
  (let ((boolean (sharp-boolean #f "false")))
    (lambda (c port)
      ;; #f32( and #f64( are SRFI 4 vectors
      (read-char port)                  ;consume f
      (let ((next (peek-char port)))
	(if (and (char? next) (char-numeric? next))
	    (sharp-numeric-vector-after "f" c port)
	    (let ((name (car (sub-read-token #\f port))))
	      (if (or (= (string-length name) 1)
		      (string=? (common-lisp:string-downcase name) "false"))
		  #f
		  (reading-error port "unknown # syntax" name))))))))
(define-sharp-macro #\t (sharp-boolean #t "true"))

; Directives: #!fold-case and #!no-fold-case (R7RS 2.1), #!r6rs (R6RS
; 4.2.4, a flag with no effect here), #!srfi-88 and #!no-srfi-88 (SRFI
; 88's keywords, foo:, on or off), those that select an alternative
; reader for the rest of the port (qs:*reader-directives*: #!sweet,
; ...), and any other #!<identifier>, which is ignored the same way.  Each is a comment, so read on.

(define-sharp-macro #\!
  (lambda (c port)
    (read-char port)                   ;consume the !
    (let ((name (common-lisp:string-downcase (car (sub-read-token (read-char port) port)))))
      ;; Folding is per port (R7RS 2.1): it applies to what is read
      ;; from this port after the directive.
      (if (or (string=? name "fold-case") (string=? name "no-fold-case"))
	  (qs:set-port-fold-case port (qs-lisp:string= name "fold-case")))
      ;; SRFI 88: after #!srfi-88, foo: is a keyword
      (if (or (string=? name "srfi-88") (string=? name "no-srfi-88"))
	  (qs:set-port-keywords port (qs-lisp:string= name "srfi-88")))
      ;; Chez Scheme's #!r6rs: only R6RS syntax after it, until #!chezscheme
      (if (or (string=? name "r6rs") (string=? name "chezscheme"))
	  (qs:set-port-r6rs port (qs-lisp:string= name "r6rs")))
      (if (and (r6rs-strict? port) (member name '("eof" "bwp")))
	  (not-in-r6rs port (string-append "#!" name)))
      ;; Chez Scheme's #!eof: the end-of-file object
      (if (string=? name "eof")
	  eof-datum
      ;; Chez Scheme's #!base-rtd and the like
      (let ((datum (qs:sharp-bang-datum name)))
	(if datum
	    datum
      ;; #!sweet and the like: the port's alternative reader reads on
      (let ((reader (qs:reader-directive port name)))
	(cond (reader (qs:call-alternative-reader reader port))
	      ;; Chez Scheme knows only its own
	      ((and (qs:true? (qs:chez-reader-p))
		    (not (member name '("fold-case" "no-fold-case" "r6rs" "chezscheme" "srfi-88" "no-srfi-88"
				      "eof" "bwp" "base-rtd")))
		    (not (and (> (string-length name) 0) (char=? (string-ref name 0) #\/))))
	       (reading-error port (string-append "invalid syntax #!" name)))
	      (else (sub-read port))))))))))

; Datum labels, #<n>=<datum> and #<n># (R7RS 2.4).

; Chez Scheme's #<n>(...) and #<n>vfx(...): longer than this is an error
(define vector-length-limit (expt 2 32))

(define (sub-read-datum-label c port)
  c
  (let loop ((n 0))
    (let ((d (read-char port)))
      (cond ((eof-object? d)
	     (reading-error port "end of file in a datum label"))
	    ((char-numeric? d)
	     (loop (+ (* n 10) (- (char->ascii d) (char->ascii #\0)))))
	    ((char=? d #\=)
	     (qs:read-labelled-datum port n
	       (lambda () (sub-read-plain port))))
	    ((char=? d #\#)
	     (qs:datum-label-reference port n))
	    ;; Chez Scheme's #3(a b): a vector of length 3, the last
	    ;; element repeated to fill it
	    ((char=? d #\()
	     (if (> n vector-length-limit)
		 (reading-error port "invalid vector length" n))
	     (let ((elements (sub-read-list c port)))
	       (if (> (length elements) n)
		   (reading-error port "too many elements for the vector's length" n))
	       (let ((v (make-vector n (let last ((l elements))
					  (cond ((null? l) 0)
						((null? (cdr l)) (car l))
						(else (last (cdr l))))))))
		 (do ((i 0 (+ i 1)) (l elements (cdr l)))
		     ((null? l) v)
		   (vector-set! v i (car l))))))
	    ;; Chez Scheme's #3%car: ($primitive 3 car), at optimize level 3
	    ((char=? d #\%)
	     (if (> n 3) (reading-error port "invalid sharp-sign prefix" n))
	     (list '$primitive n (sub-read-plain port)))
	    ;; Chez Scheme's #12r-3b: a number in radix 12
	    ((char-ci=? d #\r)
	     (let* ((token (car (sub-read-token #\# port)))
		    (x (and (not (and (> n 18) (char-ci=? (string-ref token (- (string-length token) 1)) #\i)))
			    (string->number (substring token 1 (string-length token)) n))))
	       (or x (reading-error port "invalid number syntax" token))))
	    ;; Chez Scheme's #5vu8(1 2), #3vfx(...): filled out with the last element
	    ;; Chez Scheme's #5vs(a b): a stencil vector of mask 5
	    ((and (char=? d #\v) (eqv? (peek-char port) #\s))
	     (read-char port)
	     (if (not (eqv? (read-char port) #\())
		 (reading-error port "bad #vs syntax"))
	     (qs:make-stencil-vector n (sub-read-list c port)))
	    ((char=? d #\v)
	     (if (> n vector-length-limit)
		 (reading-error port "invalid vector length" n))
	     (let* ((a (read-char port)) (b (read-char port)))
	       (if (not (eqv? (read-char port) #\())
		   (reading-error port "bad #v syntax"))
	       (let* ((elements (sub-read-list c port))
		      (fill (let last ((l elements))
			      (cond ((null? l) 0)
				    ((null? (cdr l)) (car l))
				    (else (last (cdr l))))))
		      (elements (let pad ((l elements) (k (length elements)))
				  (if (< k n) (pad (append l (list fill)) (+ k 1)) l))))
		 (cond ((and (eqv? a #\u) (eqv? b #\8)) (qs:list->bytevector elements))
		       ((and (eqv? a #\f) (eqv? b #\x)) (qs:list->fxvector elements))
		       ((and (eqv? a #\f) (eqv? b #\l))
			(qs:list->numeric-vector "f64" elements))
		       (else (reading-error port "bad #v syntax"))))))
	    ((char-alphabetic? d)
	     (sub-read-array-literal n d port))
	    (else
	     (reading-error port "bad datum label" n d))))))

; Array literals (SRFI 163, and SRFI 58's): #<rank><tag><bounds><datum>,
; the tag a (or A) or a SRFI 4 tag (u32, f64, ...), or SRFI 58's A:type;
; each bound @lower, :length or @lower:length.  The array is made by
; qs:make-array-literal (src/core.lisp), with (srfi 163)'s procedure.

(define (sub-read-array-literal rank first port)
  (let* ((tag (read-array-tag first port))
	 (bounds (read-array-bounds port))
	 (datum (sub-read-plain port)))
    (qs:make-array-literal rank tag bounds datum)))

(define (read-array-tag first port)
  (let loop ((l (list first)))
    (let ((c (peek-char port)))
      (cond ((and (char? c) (or (char-alphabetic? c) (char-numeric? c)))
	     (loop (cons (read-char port) l)))
	    ;; SRFI 58's A:type, the type a name, not a length
	    ((and (char? c) (char=? c #\:) (null? (cdr l))
		  (char=? (char-downcase first) #\a))
	     (read-char port)
	     (let ((next (peek-char port)))
	       (if (and (char? next) (char-alphabetic? next))
		   (list->string (cons first (cons #\: (string->list (car (sub-read-token (read-char port) port))))))
		   (begin
		     ;; a length after all: put the : back as a bound
		     (set! pending-length #t)
		     (string first)))))
	    (else (list->string (reverse l)))))))

; READ-ARRAY-TAG may have consumed the : of a first :length bound.
(define pending-length #f)

(define (read-array-bounds port)
  (define (read-integer)
    (let loop ((l '()))
      (let ((c (peek-char port)))
	(if (and (char? c) (or (char-numeric? c) (and (null? l) (char=? c #\-))))
	    (loop (cons (read-char port) l))
	    (let ((n (string->number (list->string (reverse l)))))
	      (or n (reading-error port "bad array bound")))))))
  (let loop ((bounds '()))
    (let ((c (peek-char port)))
      (cond (pending-length
	     (set! pending-length #f)
	     (loop (cons (cons 0 (read-integer)) bounds)))
	    ((eqv? c #\@)
	     (read-char port)
	     (let ((lower (read-integer)))
	       (if (eqv? (peek-char port) #\:)
		   (begin (read-char port)
			  (loop (cons (cons lower (read-integer)) bounds)))
		   (loop (cons (cons lower #f) bounds)))))
	    ((eqv? c #\:)
	     (read-char port)
	     (loop (cons (cons 0 (read-integer)) bounds)))
	    (else (reverse bounds))))))

(for-each (lambda (c) (define-sharp-macro c sub-read-datum-label))
	  (string->list "0123456789"))

(define named-characters
  `((space     . ,(ascii->char 32))
    (newline   . ,(ascii->char 10))
    (tab       . ,(ascii->char 9))
    (nul       . ,(ascii->char 0))
    (null      . ,(ascii->char 0))
    (backspace . ,(ascii->char 8))
    (delete    . ,(ascii->char 127))
    (rubout    . ,(ascii->char 127))
    (escape    . ,(ascii->char 27))
    (altmode   . ,(ascii->char 27))
    (return    . ,(ascii->char 13))
    (linefeed  . ,(ascii->char 10))
    (page      . ,(ascii->char 12))
    (alarm     . ,(ascii->char 7))
    (vtab      . ,(ascii->char 11))    ;R6RS
    (esc       . ,(ascii->char 27))    ;R6RS
    (nul       . ,(ascii->char 0))     ;Chez Scheme's
    (bel       . ,(ascii->char 7))
    (vt        . ,(ascii->char 11))
    (nel       . ,(ascii->char #x85))
    (ls        . ,(ascii->char #x2028))))

(define-sharp-macro #\\
  (lambda (c port)
    c
    (read-char port)
    (let ((c (peek-char port)))
      (cond ((eof-object? c)
	     (reading-error port "end of file after #\\"))
	    ;; Chez Scheme's #\ooo: three octal digits, of a code below 256
	    ((and (char-numeric? c) (qs:true? (qs:chez-reader-p)))
	     (let ((token (car (sub-read-token (read-char port) port))))
	       (cond ((= (string-length token) 1) (string-ref token 0))
		     ((and (= (string-length token) 3)
			   (octal-digit? (string-ref token 0)) (octal-digit? (string-ref token 1))
			   (octal-digit? (string-ref token 2))
			   (< (+ (* 64 (octal-value (string-ref token 0)))
				 (* 8 (octal-value (string-ref token 1)))
				 (octal-value (string-ref token 2)))
			      256))
		      (ascii->char (+ (* 64 (octal-value (string-ref token 0)))
				      (* 8 (octal-value (string-ref token 1)))
				      (octal-value (string-ref token 2)))))
		     (else (reading-error port "invalid character" token)))))
	    ((char-alphabetic? c)
	     (let ((name (sub-read-plain port)))
	       (cond ((= (string-length (symbol->string name)) 1)
		      c)
		     ;; #\x<hex> (R6RS/R7RS)
		     ((and (char=? (string-ref (symbol->string name) 0) #\x)
			   (string->number (substring (symbol->string name) 1
						      (string-length (symbol->string name)))
					   16))
		      => ascii->char)
		     ;; Character names match case-insensitively (#\Space,
		     ;; #\newline, ...); the keys of NAMED-CHARACTERS are
		     ;; lower-case names.
		     ;; in Chez Scheme only as written, unless folding
		     ((assq (string->symbol
			     (if (qs:true? (qs:chez-reader-p))
				 (qs-lisp:if qs:*fold-case*
					     (common-lisp:string-downcase (symbol->string name))
					     (symbol->string name))
				 (common-lisp:string-downcase (symbol->string name))))
			    named-characters)
		      => cdr)
		     (else
		      (reading-error port "unknown #\\ name" name)))))
	    (else
	     (read-char port))))))

(define-sharp-macro #\(
  (lambda (c port)
    (read-char port)
    (list->vector (sub-read-list c port))))

; #| ... |# block comments (nestable) and #;datum datum comments.

(define (skip-block-comment port depth)
  (if (= depth 0)
      #f
      (let ((c (read-char port)))
	(cond ((eof-object? c)
	       (reading-error port "end of file within a block comment"))
	      ((and (char=? c #\#) (eqv? (peek-char port) #\|))
	       (read-char port)
	       (skip-block-comment port (+ depth 1)))
	      ((and (char=? c #\|) (eqv? (peek-char port) #\#))
	       (read-char port)
	       (skip-block-comment port (- depth 1)))
	      (else
	       (skip-block-comment port depth))))))

(define-sharp-macro #\|
  (lambda (c port)
    (read-char port)                   ;consume the |
    (skip-block-comment port 1)
    (sub-read port)))

; #:name -- a Lisp keyword, for calling Lisp functions with keyword
; arguments (docs/interop.md).  Neither R6RS nor R7RS gives #: a meaning.
(define-sharp-macro #\:
  (lambda (c port)
    (read-char port)                   ;consume the :
    (let ((p (peek-char port)))
      (if (or (eof-object? p) (terminating? p))
          (reading-error port "missing keyword name after #:")
          (qs:intern-lisp-keyword (car (sub-read-token (read-char port) port)))))))

;; SRFI 107: #<tag ...>...</tag> (src/quasi.lisp)
(define-sharp-macro #\<
  (lambda (c port)
    c
    (read-char port)
    (qs:read-xml-literal port)))

(define-sharp-macro #\;
  (lambda (c port)
    (read-char port)                   ;consume the ;
    (sub-read-carefully port)          ;discard the next datum
    (sub-read port)))

(let ((number-sharp-macro
       (lambda (c port)
	 c
	 (let ((string (car (sub-read-token #\# port))))
	   (or (string->number string)
	       (reading-error port "unsupported number syntax" string))))))
  (for-each (lambda (c)
	      (define-sharp-macro c number-sharp-macro))
	    '(#\b #\o #\d #\x #\i #\e)))


; Tokens
;
; SUB-READ-TOKEN returns a list whose car is the token as written.
; (It used to return a case-folded spelling and the raw one; symbols
; are now case-sensitive -- see INVERT-CASE in core.lisp -- and folding,
; when wanted, happens in INTERN-TOKEN.)

(define (sub-read-token c port)
  (let loop ((l (list c)) (n 1))
    (let ((p (peek-char port)))
      (cond ((or (eof-object? p) (terminating? p))
             (list (reverse-list->string l n)))
            (else
             (let ((c (read-char port)))
               (loop (cons c l) (+ n 1))))))))

; A token that may be a symbol: R6RS's \x<hex>; escapes in it stand for
; characters, and a token with one is a symbol, never a number.

; In Chez Scheme a symbol may have |...| parts, taken as written, and a
; \c escape stands for c; either keeps the symbol from being folded
; (VERBATIM), where an \x<hex>; escape doesn't.

(define (sub-read-symbol-token c port)
  ;; A token without escapes is read by the host (qs:read-plain-token),
  ;; whole, or up to its first \ or Chez's |, where this goes on
  (if (char=? c #\\)
      (symbol-token-char '() 1 c #f #f port)
      (let ((fast (qs:read-plain-token c port read-terminating?-vector)))
	(if (null? (cdr fast))
	    fast
	    (symbol-token-bars (car fast) (cdr fast) #f #f port)))))

; C, a token's next character (read already), then the rest: L its
; characters so far, last first, N how many

(define (symbol-token-char l n c escaped? verbatim? port)
  (let* ((escape? (char=? c #\\))
	 (hex? (and escape? (eqv? (peek-char port) #\x)))
	 (l (cons (if escape? (read-symbol-escape port) c) l))
	 (escaped? (or escaped? escape?))
	 (verbatim? (or verbatim? (and escape? (not hex?)))))
    (symbol-token-bars l n escaped? verbatim? port)))

(define (symbol-token-bars l n escaped? verbatim? port)
  (let ((p (peek-char port)))
    (cond ((and (eqv? p #\|) (qs:true? (qs:chez-reader-p)))
	   (read-char port)
	   (let ((part (read-bar-part port)))
	     (symbol-token-bars (append part l) (+ n (length part)) #t #t port)))
	  ((or (eof-object? p) (terminating? p))
	   (cons (reverse-list->string l n)
		 (append (if escaped? '(escaped) '()) (if verbatim? '(verbatim) '()))))
	  (else (symbol-token-char l (+ n 1) (read-char port) escaped? verbatim? port)))))

; The characters of a |...| part, after its |, last first

(define (read-bar-part port)
  (let loop ((l '()))
    (let ((c (read-char port)))
      (cond ((eof-object? c)
	     (reading-error port "end of file within |symbol|"))
	    ((char=? c #\|) l)
	    ((char=? c #\\) (loop (cons (read-escape port) l)))
	    (else (loop (cons c l)))))))

(define (read-symbol-escape port)
  ;; Chez Scheme's \c, any character but x, stands for c
  (if (and (qs:true? (qs:chez-reader-p))
	   (not (eqv? (peek-char port) #\x))
	   (not (eof-object? (peek-char port))))
      (read-char port)
      (read-hex-symbol-escape port)))

(define (read-hex-symbol-escape port)
  (if (not (eqv? (read-char port) #\x))
      (reading-error port "invalid escape in symbol: expected \\x"))
  (let loop ((digits '()))
    (let ((d (read-char port)))
      (cond ((eof-object? d)
	     (reading-error port "end of file in symbol escape"))
	    ((char=? d #\;)
	     (let* ((hex (list->string (reverse digits)))
		    (n (string->number hex 16)))
	       (if (and n (exact? n) (integer? n)
			(or (<= 0 n #xD7FF) (<= #xE000 n #x10FFFF)))
		   (ascii->char n)
		   (reading-error port (string-append "out of range escape: `\\x" hex ";'")))))
	    (else (loop (cons d digits)))))))

(define (parse-token token port)
  (let ((string (car token)))
    (if (and (null? (cdr token))
	     (let ((c (string-ref string 0)))
	  (or (char-numeric? c) (char=? c #\+) (char=? c #\-) (char=? c #\.))))
	(cond ((string->number string))
	      ((member string strange-symbol-names)
	       (token-symbol token port))
	      ((string=? string ".")
	       dot)
	      ;; Anything else that doesn't parse as a number: a symbol
	      ;; if it can be one (R6RS/R7RS "peculiar identifiers" such
	      ;; as ->x and .foo), else an error.
	      ((and (char-numeric? (string-ref string 0))
		    (not (qs:true? (qs:chez-reader-p))))
	       (reading-error port "unsupported number syntax" string))
	      ;; Chez Scheme: 1/0, 1#/0#: a rational it can't represent
	      ((and (qs:true? (qs:chez-reader-p)) (zero-denominator? string))
	       (reading-error port "cannot represent" string))
	      (else (token-symbol token port)))
	(token-symbol token port))))

; After Chez Scheme's #!r6rs, a symbol must be an R6RS identifier (or
; have an escape in it).
(define (token-symbol token port)
  (if (and (null? (cdr token))
	   (r6rs-strict? port)
	   (not (qs:true? (qs:r6rs-identifier-p (car token)))))
      (reading-error port (string-append (car token) " symbol syntax not allowed in #!r6rs mode"))
      (intern-token (car token) (memq 'verbatim (cdr token)))))

(define (r6rs-strict? port) (qs:true? (qs:port-r6rs-p port)))

(define (not-in-r6rs port what)
  (reading-error port (string-append what " syntax not allowed in #!r6rs mode")))

; [+-]digits#.../0...#...: a rational whose denominator is zero

(define (zero-denominator? string)
  (let ((n (string-length string)))
    (let loop ((i (if (and (> n 0) (memv (string-ref string 0) '(#\+ #\-))) 1 0)) (digits? #f))
      (cond ((= i n) #f)
	    ((char-numeric? (string-ref string i)) (loop (+ i 1) #t))
	    ((and digits? (char=? (string-ref string i) #\#)) (loop (+ i 1) #t))
	    ((and digits? (char=? (string-ref string i) #\/) (< (+ i 1) n))
	     (let zeros ((j (+ i 1)) (zero? #f))
	       (cond ((= j n) zero?)
		     ((char=? (string-ref string j) #\0) (zeros (+ j 1) #t))
		     ((and zero? (char=? (string-ref string j) #\#)) (zeros (+ j 1) #t))
		     (else #f))))
	    (else #f)))))

(define strange-symbol-names
  '("+" "-" "..." "1+" "-1+" "1-"))  ;1+ and -1+ for S&ICP, 1- for Chez Scheme

; NB: no special handling of ":" here. It's tempting to read FOO:BAR
; as a Common-Lisp-style package-qualified symbol (the way the CL
; reader bridge, and the #'-escape below, do) -- but unlike in CL, ":"
; is just an ordinary constituent character in R5RS/R7RS symbol syntax
; with no special meaning, and real Scheme code uses it that way (e.g.
; ":::" as a custom syntax-rules ellipsis identifier, in R7RS). Giving
; it CL semantics here breaks those. This reader is for Scheme source;
; code that specifically wants to name a CL symbol from Scheme should
; keep using the #'-escape (below), same as read.scm's own definitions
; at the top of this file do.

(define (intern-token string . verbatim)
  (let ((string (qs-lisp:if qs:*fold-case*
			   (if (or (null? verbatim) (not (car verbatim)))
			       (qs:fold-symbol-name string)
			       string)
			   string))
	(n (string-length string)))
    (if (and (qs:keywords-p) (> n 1) (char=? (string-ref string (- n 1)) #\:))
	(qs:intern-keyword-object (substring string 0 (- n 1)))
	(qs:intern-scheme-symbol string))))

; Reader errors

(define (reading-error port message . irritants)
  (apply #'qs:scheme-reading-error port message irritants))


; Initialize for Quasischeme...

(qs-lisp:setq qs:*scheme-read* scheme-read)


;; Bytevectors: R7RS #u8(...) and R6RS #vu8(...); and SRFI 4's (and
;; SRFI 160's) homogeneous vectors, #s16(...), #f64(...), #c128(...).

(define (sharp-numeric-vector c port)
  (sharp-numeric-vector-after (string (char-downcase (read-char port))) c port))

;; After # and the tag's letter LETTER: digits, then the list.
(define (sharp-numeric-vector-after letter c port)
  (let loop ((digits '()))
    (let ((d (peek-char port)))
      (if (and (char? d) (char-numeric? d))
	  (loop (cons (read-char port) digits))
	  (let ((tag (string-append letter (list->string (reverse digits)))))
	    (if (and (string=? tag "u8") (eqv? d #\"))
		(begin (read-char port) (string-notated-bytevector port))
		(sharp-numeric-vector-list tag c port)))))))

;; SRFI 207: #u8"text", read as a string is, its characters' codes the
;; bytes.  (Characters past U+00FF are an error; the SRFI asks for
;; printable ASCII and escapes.)
(define (string-notated-bytevector port)
  (let ((codes (map char->ascii
		    (string->list ((vector-ref read-dispatch-vector (char->ascii #\")) #\" port)))))
    (if (not (null? (filter-out-bytes codes)))
	(reading-error port "a character in #u8\"...\" isn't a byte"))
    (qs:list->bytevector codes)))

(define (filter-out-bytes codes)
  (cond ((null? codes) '())
	((< (car codes) 256) (filter-out-bytes (cdr codes)))
	(else codes)))

(define (sharp-numeric-vector-list tag c port)
  (if (not (eqv? (read-char port) #\())
      (reading-error port "bad homogeneous vector syntax" tag))
  (if (string=? tag "u8")
      (qs:list->bytevector (sub-read-list c port))
      (qs:list->numeric-vector tag (sub-read-list c port))))

(define-sharp-macro #\u sharp-numeric-vector)
(define-sharp-macro #\s sharp-numeric-vector)
(define-sharp-macro #\c sharp-numeric-vector)

(define-sharp-macro #\v
  (lambda (c port)
    (read-char port)                   ;consume v
    (let* ((a (read-char port))
	   (b (read-char port)))
      (if (not (eqv? (read-char port) #\())
	  (reading-error port "bad #v syntax"))
      (if (and (r6rs-strict? port) (not (and (eqv? a #\u) (eqv? b #\8))))
	  (not-in-r6rs port (string #\# #\v a b)))
      (cond ((and (eqv? a #\u) (eqv? b #\8))
	     (qs:list->bytevector (sub-read-list c port)))
	    ;; Chez Scheme's fxvectors and flvectors (f64vectors here)
	    ((and (eqv? a #\f) (eqv? b #\x))
	     (qs:list->fxvector (sub-read-list c port)))
	    ((and (eqv? a #\f) (eqv? b #\l))
	     (qs:list->numeric-vector "f64" (sub-read-list c port)))
	    (else (reading-error port "bad #v syntax"))))))

; Chez Scheme's #[name field ...]: a record of the type record-reader
; associates with name.

(define-sharp-macro #\[
  (lambda (c port)
    c
    (read-char port)
    (if (r6rs-strict? port) (not-in-r6rs port "#["))
    (qs:read-record-literal (sub-read-list #\[ port))))

; Chez Scheme's #&x (a box) and #%x (($primitive x): the system's x).

(define-sharp-macro #\&
  (lambda (c port)
    c
    (read-char port)
    (qs:make-box (sub-read-plain port))))

(define-sharp-macro #\%
  (lambda (c port)
    c
    (read-char port)
    (list '$primitive (sub-read-plain port))))

; Chez Scheme's #{pretty unique}: a gensym.  The same unique name reads
; as the same symbol.  Each name folds as a symbol does, unless it has
; a \c escape.

(define-sharp-macro #\{
  (lambda (c port)
    c
    (read-char port)
    (let loop ((parts '()) (l '()) (n 0) (verbatim? #f))
      (let ((d (read-char port)))
	(define (part)
	  (let ((s (reverse-list->string l n)))
	    (qs-lisp:if qs:*fold-case* (if verbatim? s (qs:fold-symbol-name s)) s)))
	(cond ((eof-object? d) (reading-error port "end of file in #{"))
	      ((or (char=? d #\}) (char-whitespace? d))
	       (let ((parts (if (> n 0) (cons (part) parts) parts)))
		 (if (char=? d #\})
		     (cond ((and (pair? parts) (pair? (cdr parts)) (null? (cddr parts)))
			    (qs:make-gensym-with-unique-name (cadr parts) (car parts)))
			   ((and (pair? parts) (null? (cdr parts)))
			    (qs:make-gensym-from-name (car parts)))
			   (else (reading-error port "invalid #{...} gensym syntax")))
		     (loop parts '() 0 #f))))
	      ((char=? d #\\)
	       (let ((e (read-char port)))
		 (if (eof-object? e) (reading-error port "end of file in #{"))
		 (loop parts (cons e l) (+ n 1) #t)))
	      (else (loop parts (cons d l) (+ n 1) verbatim?)))))))

;; R6RS 4.3.5 abbreviations: #'x #`x #,x #,@x.  (These replace an older
;; Quasischeme-specific #'cl-function escape; see README.)

(define-sharp-macro #\'
  (lambda (c port)
    c
    (read-char port)
    (list 'syntax (sub-read-carefully port))))

(define-sharp-macro #\`
  (lambda (c port)
    c
    (read-char port)
    (list 'quasisyntax (sub-read-carefully port))))

(define-sharp-macro #\,
  (lambda (c port)
    c
    (read-char port)
    (if (eqv? (peek-char port) #\@)
	(begin (read-char port)
	       (list 'unsyntax-splicing (sub-read-carefully port)))
	;; SRFI 10: #,(tag datum ...) is the datum tag's reader
	;; constructor makes, if define-reader-ctor gave it one
	(let* ((datum (sub-read-carefully port))
	       (ctor (and (pair? datum) (symbol? (car datum)) (qs:reader-ctor (car datum)))))
	  (if ctor
	      (apply ctor (cdr datum))
	      (list 'unsyntax datum))))))

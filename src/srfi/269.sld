;;; SRFI 269: portable test definitions.  Quasischeme's, written from the
;;; SRFI's text (the sample implementation it points to is GPL): the
;;; definition forms build their entities as the SRFI's alists and send
;;; its messages to (current-test-runner).  It has no runner of its own:
;;; until one is set, a message is an error saying so.
;;;
;;; The assertion context is a parameter, %CONTEXT, that testing extends
;;; and an assertion's body thunk installs again; suite loaders are
;;; tagged procedures (SRFI 229), which suite-loader? recognizes; source
;;; locations are left out, as the SRFI allows.
(define-library (srfi 269)
  (export is testing test test-loader suite suite-loader define-suite
          metadata current-test-runner set-default-test-runner!
          test? suite? suite-loader?)
  (import (scheme base) (scheme case-lambda) (srfi 229))
  (begin
    (define-syntax metadata
      (syntax-rules ()
        ((_ . anything) (syntax-error "metadata outside a test or suite form"))))

    ;; The default runner: the one set-default-test-runner! sets, which
    ;; until then reports that none has been.
    (define default-runner
      (lambda (message)
        (error "SRFI 269: no test runner has been configured (set-default-test-runner! or parameterize current-test-runner)"
               (cdr (assq 'type message)))))
    (define current-test-runner
      (make-parameter (lambda (message) (default-runner message))))
    (define (set-default-test-runner! runner)
      (set! default-runner runner))
    (define (send message) ((current-test-runner) message))

    ;; The assertion context: descriptions of the enclosing testing
    ;; forms, outermost first.
    (define %context (make-parameter '()))

    (define (assertion-entity thunk body context description?)
      (let ((entity (list (cons 'assertion/body-thunk thunk)
                          (cons 'assertion/body body)
                          (cons 'assertion/context context))))
        (if (car description?)
            (append entity (list (cons 'assertion/description (cdr description?))))
            entity)))

    (define (check-description who x)
      (unless (string? x)
        (error "SRFI 269: a description must be a string" who x))
      x)

    (define-syntax is
      (syntax-rules ()
        ((_ expression)
         (let ((context (%context)))
           (send (list (cons 'type 'runner/run-assertion)
                       (cons 'assertion
                             (assertion-entity
                              (lambda () (parameterize ((%context context)) expression))
                              'expression context (cons #f #f)))))))
        ((_ expression description)
         (let* ((context (%context))
                (d (check-description 'is description)))
           (send (list (cons 'type 'runner/run-assertion)
                       (cons 'assertion
                             (assertion-entity
                              (lambda () (parameterize ((%context context)) expression))
                              'expression context (cons #t d)))))))))

    (define-syntax testing
      (syntax-rules ()
        ((_ description body1 body ...)
         (let ((d (check-description 'testing description)))
           (parameterize ((%context (append (%context) (list d))))
             (let () body1 body ...))))))

    ;; A loader of ENTITY, under KEY in its message: called with no
    ;; argument or a load-time metadata alist.
    (define (make-loader type key entity)
      (case-lambda
        (() (send (list (cons 'type type) (cons key entity))))
        ((load-metadata)
         (send (list (cons 'type type) (cons key entity)
                     (cons 'load/metadata load-metadata))))))

    (define (test-entity procedure description metadata-alist)
      (list (cons 'test/body-procedure procedure)
            (cons 'test/description (check-description 'test description))
            (cons 'test/metadata metadata-alist)))

    (define-syntax test-body-procedure
      (syntax-rules ()
        ((_ () ) (lambda (context) (if #f #f)))
        ((_ (context)) (lambda (context) (if #f #f)))
        ((_ () body1 body ...) (lambda (ignored) body1 body ...))
        ((_ (context) body1 body ...) (lambda (context) body1 body ...))))

    (define-syntax test-loader
      (syntax-rules (metadata)
        ((_ description formals (metadata metadata-alist) body ...)
         (let* ((d description) (m metadata-alist))
           (make-loader 'runner/load-test 'test
                        (test-entity (test-body-procedure formals body ...) d m))))
        ((_ description formals body ...)
         (let ((d description))
           (make-loader 'runner/load-test 'test
                        (test-entity (test-body-procedure formals body ...) d '()))))))

    (define-syntax test
      (syntax-rules ()
        ((_ description formals body ...)
         ((test-loader description formals body ...)))))

    (define suite-loader-tag (list 'srfi-269-suite-loader))

    (define (make-suite-loader description metadata-alist thunk)
      (let ((loader (make-loader 'runner/load-suite 'suite
                                 (list (cons 'suite/body-thunk thunk)
                                       (cons 'suite/description
                                             (check-description 'suite description))
                                       (cons 'suite/metadata metadata-alist)))))
        (case-lambda/tag suite-loader-tag
          (() (loader))
          ((load-metadata) (loader load-metadata)))))

    (define-syntax suite-thunk
      (syntax-rules ()
        ((_) (lambda () (if #f #f)))
        ((_ body1 body ...) (lambda () body1 body ...))))

    (define-syntax suite-loader
      (syntax-rules (metadata)
        ((_ description (metadata metadata-alist) body ...)
         (let* ((d description) (m metadata-alist))
           (make-suite-loader d m (suite-thunk body ...))))
        ((_ description body ...)
         (make-suite-loader description '() (suite-thunk body ...)))))

    (define-syntax suite
      (syntax-rules ()
        ((_ description body ...)
         ((suite-loader description body ...)))))

    (define-syntax define-suite
      (syntax-rules ()
        ((_ (name) body ...)
         (define name (suite-loader (symbol->string 'name) body ...)))))

    (define (alist-with? obj keys)
      (and (list? obj)
           (let loop ((l obj))
             (or (null? l) (and (pair? (car l)) (loop (cdr l)))))
           (let loop ((keys keys))
             (or (null? keys) (and (assq (car keys) obj) (loop (cdr keys)))))))

    (define (test? obj) (alist-with? obj '(test/body-procedure test/description)))
    (define (suite? obj) (alist-with? obj '(suite/body-thunk suite/description)))
    (define (suite-loader? obj)
      (and (procedure/tag? obj) (eq? (procedure-tag obj) suite-loader-tag)))))

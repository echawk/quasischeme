;;; SRFI 269 tests: Quasischeme's, from the SRFI's text: the entities and
;;; messages the definition forms send to a runner that records them,
;;; runs tests and suites, and returns an assertion's value.
(import (scheme base) (scheme write) (scheme process-context)
        (srfi 269))

(define failures 0)
(define (check name ok)
  (unless ok
    (set! failures (+ failures 1))
    (display "FAIL: ") (display name) (newline)))
(define (ref key alist) (cdr (assq key alist)))

;; No runner configured: a message is an error.
(check "no runner"
       (guard (e (#t #t)) (is #t) #f))

(define messages '())
(define (recording-runner message)
  (set! messages (cons message messages))
  (case (ref 'type message)
    ((runner/run-assertion) ((ref 'assertion/body-thunk (ref 'assertion message))))
    ((runner/load-test) ((ref 'test/body-procedure (ref 'test message)) '((answer . 42))))
    ((runner/load-suite) ((ref 'suite/body-thunk (ref 'suite message))))))
(set-default-test-runner! recording-runner)

;; is: the entity, its value through the runner
(check "is returns the body's value" (= 7 (is (+ 3 4))))
(let ((a (ref 'assertion (car messages))))
  (check "assertion body" (equal? '(+ 3 4) (ref 'assertion/body a)))
  (check "assertion context empty" (null? (ref 'assertion/context a)))
  (check "no description" (not (assq 'assertion/description a))))
(is #t "described")
(check "description" (equal? "described" (ref 'assertion/description (ref 'assertion (car messages)))))

;; testing: the context, outermost first, kept by a thunk run later
(define saved #f)
(testing "outer"
  (testing "inner"
    (parameterize ((current-test-runner
                    (lambda (m) (set! saved (ref 'assertion m)) #t)))
      (is (equal? '("outer" "inner") (ref 'assertion/context saved))))))
(check "nested context" (equal? '("outer" "inner") (ref 'assertion/context saved)))
(check "context re-established" ((ref 'assertion/body-thunk saved)))

;; test: entity, metadata, the context argument
(set! messages '())
(define seen-context #f)
(test "with context" (ctx)
  (metadata '((tags . (unit))))
  (set! seen-context ctx)
  (is (= 42 (cdr (assq 'answer ctx)))))
(let ((load (car (reverse messages))))
  (check "load-test message" (eq? 'runner/load-test (ref 'type load)))
  (check "test?" (test? (ref 'test load)))
  (check "test description" (equal? "with context" (ref 'test/description (ref 'test load))))
  (check "test metadata" (equal? '((tags . (unit))) (ref 'test/metadata (ref 'test load)))))
(check "context passed" (equal? '((answer . 42)) seen-context))
(test "no context, no body" ())
(check "empty metadata" (null? (ref 'test/metadata (ref 'test (car messages)))))

;; test-loader: load-time metadata
(define loader (test-loader "deferred" () (is #t)))
(set! messages '())
(loader '((run . 1)))
(check "load/metadata" (equal? '((run . 1)) (ref 'load/metadata (car (reverse messages)))))

;; suite, suite-loader, define-suite
(set! messages '())
(suite "top" (metadata '((slow? . #f)))
  (test "one" () (is #t))
  (suite "nested" (test "two" () (is (= 2 (+ 1 1))))))
(let ((suites (let loop ((ms (reverse messages)) (out '()))
                (cond ((null? ms) (reverse out))
                      ((eq? 'runner/load-suite (ref 'type (car ms))) (loop (cdr ms) (cons (ref 'suite (car ms)) out)))
                      (else (loop (cdr ms) out))))))
  (check "two suites" (= 2 (length suites)))
  (check "suite?" (suite? (car suites)))
  (check "suite metadata" (equal? '((slow? . #f)) (ref 'suite/metadata (car suites))))
  (check "nested description" (equal? "nested" (ref 'suite/description (cadr suites)))))
(define-suite (my-tests) (test "three" () (is #t)))
(check "suite-loader?" (suite-loader? my-tests))
(check "plain lambda isn't" (not (suite-loader? (lambda () #f))))
(set! messages '())
(my-tests '((configuration . strict)))
(check "define-suite description" (equal? "my-tests" (ref 'suite/description (ref 'suite (car (reverse messages))))))
(check "suite load/metadata" (equal? '((configuration . strict)) (ref 'load/metadata (car (reverse messages)))))
(check "not a test" (not (test? '((suite/body-thunk . #f)))))

(if (zero? failures)
    (begin (display "SRFI 269: all passed") (newline) (exit 0))
    (exit 1))

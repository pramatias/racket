#lang racket/base
(require racket/place/distributed
         racket/class
         racket/place
         racket/runtime-path
         "bank.rkt"
         "tuple.rkt")
(define-runtime-path bank-path "bank.rkt")
(define-runtime-path tuple-path "tuple.rkt")

(provide main)

(define (main)
  (define (test expect fun . args)
    (printf "~s ==> " (cons fun args))
    (flush-output)
    (let ([res (if (procedure? fun)
                 (apply fun args)
                 (car args))])
      (printf "~s\n" res)
      (let ([ok? (equal? expect res)])
        (unless ok?
          (printf "  BUT EXPECTED ~s\n" expect)
          (eprintf "ERROR\n"))
        ok?)))

  (define remote-vm   (spawn-remote-racket-vm "localhost" #:listen-port 6344))
  (define tuple-place (supervise-named-place-thunk-at remote-vm 'tuple-server tuple-path 'make-tuple-server))
  (define bank-place  (supervise-place-thunk-at remote-vm bank-path 'make-bank))

  (master-event-loop
    remote-vm
    (after-seconds 2
      (define c (connect-to-named-place remote-vm 'tuple-server))
      (define d (connect-to-named-place remote-vm 'tuple-server))
      (tuple-server-hello c)
      (tuple-server-hello d)
      (test 100 tuple-server-set c "user0" 100)
      (test 200 tuple-server-set d "user2" 200)
      (test 100 tuple-server-get c "user0")
      (test 200 tuple-server-get d "user2")
      (test 100 tuple-server-get d "user0")
      (test 200 tuple-server-get c "user2")
      )
    (after-seconds 4
      (test '(created user1) bank-new-account bank-place 'user1)
      (test '(ok 10) bank-add bank-place 'user1 10)
      (test '(ok 5) bank-removeM bank-place 'user1 5)
      )

    (after-seconds 15
      (node-send-exit remote-vm))
    (after-seconds 20
      (exit 0))))

;;; -*- mode: scheme; coding: utf-8 -*-

(use srfi-11)
(use gauche.threads)
(use util.match)
(use util.queue)

(use redis)
(use redis.async)

(define raytracer-mod (make-module #f))
(load "./raytracer.scm" :environment raytracer-mod)

(define spheres ((global-variable-ref raytracer-mod 'make-scene)))

; REDISCLOUD_URL=redis://rediscloud:lmzBksmjjRkVf2FI@pub-redis-10787.us-east-1-2.1.ec2.garantiadata.com:10787
; REDISCLOUD_URL=redis://rediscloud@localhost:6379
(define *passwd* #f)

(define (connect-redis)
  (rxmatch-let (rxmatch #/(?:\w+):\/\/(?:\w+)(?::(\w+))?@([^:]+):(\d+)/
                        (sys-getenv "REDISCLOUD_URL"))
      (value passwd host port)
    (set! *passwd* #?=passwd)
    (redis-open-async #?=host #?=port)))

(define (gen-update-proc)
  (lambda (pub sub)
    (call/cc
     (lambda (yield)
       (define (wait-for-response proc)
         (call/cc (lambda (next)
                    (call/cc (lambda (cont)
                               (proc (lambda (res)
                                       (cont res)))
                               (yield (lambda (pub sub) (next))))))))

       (worker-main wait-for-response pub sub)
       ))))

(define (worker-main yield pub sub)
  (when *passwd*
    #?=(yield (redis-async-auth pub *passwd*))
    #?=(yield (redis-async-auth sub *passwd*)))

  (while #t
    #?=(yield (redis-async-subscribe sub "task"))
    #?=(yield (redis-async-wait-for-publish! sub))
    #?=(yield (redis-async-unsubscribe sub "task"))
    #?=(dequeue-all! (ref sub 'recv-queue))

    (let loop ()
      (let ((task (yield (redis-async-lpop pub "tasks"))))
        (when task
          (let-values (((request-id task-id size frame)
                        (match (read-from-string task)
                          (`(,req-id ,task-id ,size ,frame)
                           (values req-id task-id size frame)))))
            (let1 image
                (with-output-to-string
                  (lambda ()
                    ((global-variable-ref raytracer-mod 'output-in-ppm-format)
                     frame
                     ((global-variable-ref raytracer-mod 'render-body)
                      spheres size frame))))
              (yield (redis-async-publish
                      pub #`"result-,request-id"
                      (string-append (write-to-string `(,task-id)) image)))
              (loop))))
      ))

    )
  (sys-exit 0)
  )

(define (main args)
  (let ((pub (connect-redis))
        (sub (connect-redis)))

    ((gen-update-proc) pub sub)

    (while #t
      (redis-async-update! pub)
      (redis-async-update! sub)
      (sys-nanosleep (expt 10 8)))      ; sleep 100ms
  ))

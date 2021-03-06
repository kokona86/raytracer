;; A very basic raytracer example.
;; Copyright (C) 2012  www.scratchapixel.com
;; Scheme implementation by Toru Hisai @torus

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;; - changes 02/04/13: fixed flag in ofstream causing a bug under Windows,
;; added default values for M_PI and INFINITY
;; - changes 24/05/13: small change to way we compute the refraction direction
;; vector (eta=ior if we are inside and 1/ior if we are outside the sphere)
;;
;; Scheme implementation
;; - 06/20/14: translated for the Gauche Scheme interpreter

(use srfi-1)

(use gauche.collection)
(use gauche.uvector)
(use gauche.record)
(use gauche.parseopt)
(use gl.math3d)

(use text.tree)

(use redis)
(use redis.async)

(define-constant *max-ray-depth* 5)
(define-constant *PI* 3.141592653589793)
(define-constant *ior* 1.1)
(define-constant *inv-ior* (/ 1 1.1))
(define-constant *bias* 0.0001)

(define-record-type sphere-type #t #f
  (center sphere-center)
  (radius sphere-radius)
  (surface-color sphere-surface-color)
  (reflection sphere-reflection)
  (transparency sphere-transparency)
  (emission-color sphere-emission-color)
  (radius2 sphere-radius2))

(define (make-sphere c r sc :optional (refl 0) (transp 0) (ec (vector4f 0 0 0)))
  (make-sphere-type c r sc refl transp ec (* r r)))

(define (intersect self rayorig raydir)
  (let* ((l (- (sphere-center self) rayorig))
         (tca (vector4f-dot l raydir)))
    (if (< tca 0)
        ()
        (let ((d2 (- (vector4f-dot l l) (* tca tca))))
          (if (> d2 (sphere-radius2 self))
              ()
              (let ((thc (sqrt(- (sphere-radius2 self) d2))))
                (list (- tca thc) (+ tca thc))))))))

(define (mix a b m)
  (+ (* b m) (* a (- 1 m))))

(define (vec-* vec1 vec2)
  (vector4f (* (vector4f-ref vec1 0) (vector4f-ref vec2 0))
            (* (vector4f-ref vec1 1) (vector4f-ref vec2 1))
            (* (vector4f-ref vec1 2) (vector4f-ref vec2 2))
            (* (vector4f-ref vec1 3) (vector4f-ref vec2 3))))

(define (xxxxx surface-color spheres sphere raydir phit nhit inside depth)
  (let* ((facingratio (- (vector4f-dot raydir nhit)))
         (fresneleffect (mix (expt (- 1 facingratio) 3) 1 0.1))
         (refldir (- raydir
                     (* nhit
                        (* 2 (vector4f-dot raydir nhit))))))
    (vector4f-normalize! refldir)
    (let ((reflection (trace (+ phit (* nhit *bias*))
                             refldir spheres (+ depth 1)))
          (refraction (vector4f 0 0 0)))
      (unless (= (sphere-transparency sphere) 0)
        (let* ((eta (if inside *ior* *inv-ior*))
               (cosi (- (vector4f-dot nhit raydir)))
               (k (- 1 (* eta eta (- 1 (* cosi cosi)))))
               (refrdir (+ (* raydir eta) (* nhit (- (* eta cosi) (sqrt k))))))
          (vector4f-normalize! refrdir)
          (set! refraction (trace (- phit (* nhit *bias*))
                                  refrdir spheres
                                  (+ depth 1)))
          ))
      (let1 sc (vec-* (+ (* reflection fresneleffect)
                           (* refraction
                              (- 1 fresneleffect)
                              (sphere-transparency sphere)))
                        (sphere-surface-color sphere))
        (vector4f-set! surface-color 0 (vector4f-ref sc 0))
        (vector4f-set! surface-color 1 (vector4f-ref sc 1))
        (vector4f-set! surface-color 2 (vector4f-ref sc 2))
        (vector4f-set! surface-color 3 (vector4f-ref sc 3))
        )
      ))
  )

(define (yyyyy surface-color spheres sphere phit nhit)
  (let ((phit-bias (+ phit (* nhit *bias*)))
        (size-of-spheres (size-of spheres)))
    (let loop ((i 0))
      (when (< i size-of-spheres)
        (let* ((ith-sphere (vector-ref spheres i))
               (emission-color (sphere-emission-color ith-sphere)))
          (when (> (vector4f-ref emission-color 0) 0)
            (let ((transmission #t)
                  (light-direction (- (sphere-center ith-sphere) phit)))
              (vector4f-normalize! light-direction)
              (let loop2 ((j 0))
                (when (< j size-of-spheres)
                  (if (= i j)
                      (loop2 (+ j 1))
                      (let ((t (intersect (vector-ref spheres j)
                                          phit-bias
                                          light-direction)))
                        (if (null? t)
                            (loop2 (+ j 1))
                            (set! transmission #f))))))
              (when transmission
                (vector4f-add!
                 surface-color
                 (vec-* (* (sphere-surface-color sphere)
                           (max 0 (vector4f-dot nhit light-direction)))
                        emission-color)))))
          (loop (+ i 1)))
        ))))

(define (trace rayorig raydir spheres depth)
  (define tnear +inf.0)
  (define sphere ())
  (let loop ((i 0))
    (when (< i (size-of spheres))
      (let ((t (intersect (vector-ref spheres i) rayorig raydir)))
        (when (not (null? t))
          (let ((t0 (car t)) (t1 (cadr t)))
            (when (< t0 0) (set! t0 t1))
            (when (< t0 tnear)
              (set! tnear t0)
              (set! sphere (vector-ref spheres i)))))
        (loop (+ i 1)))))

  (if (null? sphere)
      (vector4f 2 2 2)
      (let* ((surface-color (vector4f 0 0 0))
             (phit (+ rayorig (* raydir tnear)))
             (nhit (- phit (sphere-center sphere))))
        (vector4f-normalize! nhit)
        (let ((inside #f))
          (when (> (vector4f-dot raydir nhit) 0)
            (set! nhit (* nhit -1))
            (set! inside #t))

          (if (and (or (> (sphere-transparency sphere) 0)
                       (> (sphere-reflection sphere) 0))
                   (< depth *max-ray-depth*))
              (xxxxx surface-color spheres sphere raydir phit nhit inside depth)
              (yyyyy surface-color spheres sphere phit nhit))
          (+ surface-color (sphere-emission-color sphere))))))

(define (render-body spheres size frame)
  (let* ((width (car size))
         (height (cadr size))
         (window-left (car frame))
         (window-top (cadr frame))
         (window-width (caddr frame))
         (window-height (cadddr frame))
         (image (make-vector (* window-width window-height)))
         (pixel-index 0)
         (inv-width (/ 1 width)) (inv-height (/ 1 height))
         (fov 30)
         (aspectratio (/ width height))
         (angle (tan (/ (* *PI* 0.5 fov) 180))))
    (let loop-y ((y window-top))
      (when (< y (+ window-top window-height))
        (let loop-x ((x window-left))
          (when (< x (+ window-left window-width))
            (let ((xx (* (- (* 2 (+ x 0.5) inv-width) 1) angle aspectratio))
                  (yy (* (- 1 (* 2 (* (+ y 0.5) inv-height))) angle)))
              (let ((raydir (vector4f xx yy -1)))
                (vector4f-normalize! raydir)
                (vector-set! image pixel-index (trace (vector4f 0 0 0)
                                                      raydir spheres 0))
                (inc! pixel-index)
                (loop-x (+ x 1))))))
        (loop-y (+ y 1))))

    image
    )
)

(define (output-in-ppm-format frame image)
  (let ((window-width (caddr frame))
        (window-height (cadddr frame)))
    (let loop ((i 0))
      (when (< i (* window-width window-height))
        (write-block
         (u8vector
          (floor (* (min 1 (vector4f-ref (vector-ref image i) 0)) 255))
          (floor (* (min 1 (vector4f-ref (vector-ref image i) 1)) 255))
          (floor (* (min 1 (vector4f-ref (vector-ref image i) 2)) 255))))
        (loop (+ i 1))))))

(define (output-ppm-header frame)
  (let ((window-width (caddr frame))
        (window-height (cadddr frame)))
    (display "P6\n")
    (display window-width)
    (display " ")
    (display window-height)
    (display "\n255\n"))
  )

(define (render spheres size frame)
  (output-ppm-header frame)
  (output-in-ppm-format frame (render-body spheres size frame))
  )

(define (make-scene)
  (vector
   (make-sphere (vector4f 0 -10004 -20) 10000 (vector4f 0.2 0.2 0.2) 0 0)
   (make-sphere (vector4f 0 0 -20) 4 (vector4f 1 0.32 0.36) 1 0.5)
   (make-sphere (vector4f 5 -1 -15) 2 (vector4f 0.9 0.76 0.46) 1 0)
   (make-sphere (vector4f 5 0 -25) 3 (vector4f 0.65 0.77 0.97) 1 0)
   (make-sphere (vector4f -5.5 0 -15) 3 (vector4f 0.90 0.90 0.90) 1 0)

   ;; light
   (make-sphere (vector4f 0 20 -30) 3 (vector4f 0 0 0) 0 0 (vector4f 3 3 3))
   )
  )

(define (main args)
  (let1 spheres (make-scene)
    (let-args (cdr args)
        ((size "s|size=ii" `(640 480))
         (frame "f|frame=iiii" `(0 0 640 480)))
      (render spheres size frame)))
  0)


;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Distributed rendering

(define *passwd* #f)
(define (connect-redis)
  (rxmatch-let (rxmatch #/(?:\w+):\/\/(?:\w+)(?::(\w+))?@([^:]+):(\d+)/
                        (sys-getenv "REDISCLOUD_URL"))
      (value passwd host port)
    (set! *passwd* #?=passwd)
    (redis-open-async #?=host #?=port)))


(define (gen-update-proc size frame exit)
  (lambda (pub sub)
    (call/cc
     (lambda (yield)
       (define (wait-for-response proc)
         (call/cc (lambda (next)
                    (call/cc (lambda (cont)
                               (proc (lambda (res)
                                       (cont res)))
                               (yield (lambda (pub sub) (next))))))))

       (worker-main wait-for-response pub sub size frame exit)
       ))))

(define (worker-main yield pub sub size frame exit)
  (when *passwd*
    #?=(yield (redis-async-auth pub *passwd*))
    #?=(yield (redis-async-auth sub *passwd*)))

  (let* ((request-id (yield (redis-async-incr pub "last-request-id")))
         (channel #`"result-,request-id")
         (waiting-tasks (make-tree-map))
         (results (make-tree-map)))
    (yield (redis-async-subscribe sub channel))
    (let loop ((x (car frame)) (y (cadr frame)) (task-id 0))
      (when (< y (+ (cadr frame) (cadddr frame)))
        (if (< x (+ (car frame) (caddr frame)))
            (begin
              (tree-map-put! waiting-tasks task-id #t)
              ((redis-async-rpush pub "tasks"
                                  `(,request-id ,task-id ,size (,x ,y 640 1)))
               (lambda (res) res))
              (loop (+ x 640) y (+ task-id 1)))
            (loop (car frame) (+ y 1) task-id)))
      )

    (yield (redis-async-publish pub "task" request-id))

    (let loop ()
      (unless (tree-map-empty? waiting-tasks)
        (let* ((res (yield (redis-async-wait-for-publish! sub)))
               (port (open-input-string (ref res 2)))
               (task-id (car (read port))))
          (tree-map-delete! waiting-tasks task-id)
          (tree-map-num-entries waiting-tasks)
          (tree-map-put! results task-id (get-remaining-input-string port))
          (loop)))
      )
    (yield (redis-async-unsubscribe sub channel))

    (redis-close (ref pub 'conn))
    (redis-close (ref sub 'conn))
    (exit (tree-map-values results))
    ))

(define (main-dist args)
  (let1 spheres (make-scene)
    (let-args (cdr args)
        ((size "s|size=ii" `(640 480))
         (frame "f|frame=iiii" `(0 0 640 480)))
      (render-dist spheres size frame)))
  0)

(define (render-dist spheres size frame)
  (output-ppm-header frame)

  (let ((pub (connect-redis))
        (sub (connect-redis)))

    (display
     (tree->string
      (call/cc
       (lambda (exit)
         ((gen-update-proc size frame exit) pub sub)

         (while #t
           (redis-async-update! pub)
           (redis-async-update! sub)
           (sys-nanosleep (expt 10 8)))      ; sleep 100ms
         )
       ))))
  )

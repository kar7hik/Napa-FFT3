(defvar *fwd-base-case* 8)

(defun gen-flat-dif (n &key (scale 1d0) window)
  (with-vector (n :maxlive 13)
    (let ((last n))
      (labels ((scale (i)
                 (setf (@ i)
                       (op (complex-sample)
                           `(lambda (x)
                              (%window (%scale x ,scale)
                                       ,window
                                       ,i))
                           (@ i))))
               (rec (start n)
                 (cond
                   ((= n 2)
                    (when (and (= n last)
                               (or (not (eql scale 1d0))
                                   window))
                      (scale start)
                      (scale (1+ start)))
                    (butterfly start (1+ start)))
                   ((>= n 4)
                    (let* ((n/2    (truncate n 2))
                           (start2 (+ start n/2))
                           (n/4    (truncate n/2 2))
                           (start3 (+ start2 n/4)))
                      (dotimes (i n/2)
                        (when (= last n)
                          (scale (+ i start))
                          (scale (+ i start2)))
                        (butterfly (+ i start)
                                   (+ i start2)))
                      (rec start n/2)
                      (dotimes (count n/4)
                        (let ((i (+ count start2))
                              (j (+ count start3))
                              (k (+ n/2 +twiddle-offset+
                                    (* 2 count))))
                          (rotate j nil 3/4)
                          (butterfly i j)
                          (rotate i k      (/ (* -1 count) n))
                          (rotate j (1+ k) (/ (* -3 count) n))))
                      (rec start2 n/4)
                      (rec start3 n/4))))))
        (rec 0 n)))))

(defun gen-base-difs ()
  (list `(dif/1 (start)
          (declare (ignore start))
          nil)
        `(dif/2 (start)
          (declare (type index start))
          (let ((s0 (aref vec start))
                (s1 (aref vec (1+ start))))
            (setf (aref vec      start) (+ s0 s1)
                  (aref vec (1+ start)) (- s0 s1)))
          nil)
        `(dif/4 (start)
          (declare (type index start))
          (let* ((s0 (aref vec start))
                 (s2 (aref vec (+ start 2)))
                 (s0+s2 (+ s0 s2))
                 (s0-s2 (- s0 s2))
                 
                 (s1 (aref vec (+ start 1)))
                 (s3 (aref vec (+ start 3)))
                 (s1+s3 (+ s1 s3))
                 (s1-s3 (mul+i (- s1 s3))))
            (setf (aref vec       start) (+ s0+s2 s1+s3)
                  (aref vec (+ start 1)) (- s0+s2 s1+s3)
                  (aref vec (+ start 2)) (- s0-s2 s1-s3)
                  (aref vec (+ start 3)) (+ s0-s2 s1-s3)))
          nil)
        ;; I think this one is worse than split-radix
        `(dif/8 (start)
          (declare (type index start))
          (let* ((s0 (aref vec start))
                 (s4 (aref vec (+ start 4)))
                 (s0+4 (+ s0 s4))
                 (s0-4 (- s0 s4))
                 
                 (s1 (aref vec (+ start 1)))
                 (s5 (aref vec (+ start 5)))
                 (s1+5 (+ s1 s5))
                 (s1-5 (- s1 s5))
                 
                 (s2 (aref vec (+ start 2)))
                 (s6 (aref vec (+ start 6)))
                 (s2+6 (+ s2 s6))
                 (s2-6 (- s2 s6))
                 
                 (s3 (aref vec (+ start 3)))
                 (s7 (aref vec (+ start 7)))
                 (s3+7 (+ s3 s7))
                 (s3-7 (- s3 s7)))
            (let ((a (+ s0+4 s2+6))
                  (b (+ s1+5 s3+7)))
              (setf (aref vec       start) (+ a b)
                    (aref vec (+ start 1)) (- a b)))
            (let ((a (- s0+4 s2+6))
                  (b ,(mul-root '(- s1+5 s3+7)
                                -2/8)))
              (setf (aref vec (+ start 2)) (+ a b)
                    (aref vec (+ start 3)) (- a b)))
            (let ((a (+ s0-4 ,(mul-root 's2-6 -2/8)))
                  (b ,(mul-root `(+ s1-5 ,(mul-root 's3-7 -2/8))
                                -1/8)))
              (setf (aref vec (+ start 4)) (+ a b)
                    (aref vec (+ start 5)) (- a b)))
            (let ((a (+ s0-4 ,(mul-root 's2-6 -6/8)))
                  (b ,(mul-root `(+ ,(mul-root 's1-5 -2/8)
                                    s3-7)
                                -1/8)))
              (setf (aref vec (+ start 6)) (+ a b)
                    (aref vec (+ start 7)) (- a b)))
            nil))))

(defun gen-dif (n &key (scale 1d0) window)
  (let ((defs '())
        (base-defs (gen-base-difs))
        (last n))
    (labels ((name (n)
               (intern (format nil "~A/~A" 'dif n)))
             (gen (n)
               (cond
                 ((= n 16)
                  (gen 8)
                  (push
                   `(dif/16 (start)
                     (declare (type index start))
                     (for (8 (i start)
                             ,@(and (= n last)
                                    window
                                    `((k window-start))))
                       (let ((x ,(if (= n last)
                                     `(%window (%scale (aref vec i) ,scale)
                                               ,window
                                               ,(if window 'k 0))
                                     `(aref vec i)))
                             (y ,(if (= n last)
                                     `(%window (%scale (aref vec (+ i 8)) ,scale)
                                               ,window
                                               ,(if window `(+ k 8) 0))
                                     `(aref vec (+ i 8)))))
                         (setf (aref vec i) (+ x y)
                               (aref vec (+ i 8)) (- x y))))
                       (dif/8 start)
                       ,@(loop
                           for i below 4
                           collect
                           `(let ((x (aref vec (+ start ,(+ i 8))))
                                  (y (mul-i (aref vec (+ start ,(+ i 8 4))))))
                              (setf (aref vec (+ start ,(+ i 8)))
                                    ,(mul-root
                                      `(+ x y) (* -1/16 i)
                                      `(aref twiddle ,(+ 8 +twiddle-offset+
                                                         (* 2 i))))
                                    (aref vec (+ start ,(+ i 8 4)))
                                    ,(mul-root
                                      `(- x y) (* -3/16 i)
                                      `(aref twiddle ,(+ 8 +twiddle-offset+
                                                         1
                                                         (* 2 i)))))))
                       (dif/4 (+ start 8))
                       (dif/4 (+ start 12)))
                   defs))
                 ((> n *fwd-base-case*)
                  (gen (truncate n 2))
                  (let* ((n/2 (truncate n 2))
                         (n/4 (truncate n 4))
                         (name/2 (name n/2))
                         (name/4 (name n/4))
                         (body
                           `(,(name n) (start)
                             (declare (type index start))
                             (for (,n/2 (i start)
                                        ,@(and (= n last)
                                               window
                                               `((k window-start))))
                               (let ((x ,(if (= n last)
                                             `(%window (%scale (aref vec i) ,scale)
                                                       ,window
                                                       ,(if window 'k 0))
                                             `(aref vec i)))
                                     (y ,(if (= n last)
                                             `(%window (%scale (aref vec (+ i ,n/2))
                                                               ,scale)
                                                       ,window
                                                       ,(if window `(+ k ,n/2) 0))
                                             `(aref vec (+ i ,n/2)))))
                                 (setf (aref vec          i) (+ x y)
                                       (aref vec (+ i ,n/2)) (- x y))))
                             (,name/2 start)
                             (for (,n/4 (i start)
                                        (k ,(+ n/2 +twiddle-offset+) 2))
                               (let ((x  (aref vec (+ i ,n/2)))
                                     (y  (mul-i (aref vec (+ i ,(+ n/2 n/4)))))
                                     (t1 (aref twiddle k))
                                     (t2 (aref twiddle (1+ k))))
                                 (setf (aref vec (+ i ,n/2))
                                       (* t1 (+ x y))
                                       (aref vec (+ i ,(+ n/2 n/4)))
                                       (* t2 (- x y)))))
                             (,name/4 (+ start ,n/2))
                             (,name/4 (+ start ,(+ n/2 n/4))))))
                    (push body defs))))))
      (gen n)
      `(labels (,@base-defs ,@(nreverse defs))
         (declare (ignorable ,@(mapcar (lambda (x) `#',(car x)) base-defs))
                  (inline ,@(mapcar #'car base-defs)
                          ,(name n)))
         ,(and (<= n *fwd-base-case*)
               (not (and (eql scale 1d0)
                         (null window)))
               `(for (,n (i start)
                         ,@(and window `((j window-start))))
                  (setf (aref vec i) (%scale
                                      (%window (aref vec i)
                                               ,window
                                               ,(if window 'j 0))
                                      ,scale))))
         (,(name n) start)))))

(defun %dif (vec start n twiddle)
  (declare (type complex-sample-array vec twiddle)
           (type index start)
           (type size n))
  (labels ((rec (start n)
             (declare (type index start)
                      (type size n))
             (cond ((>= n 4)
                    (let* ((n/2    (truncate n 2))
                           (start2 (+ start n/2))
                           (n/4    (truncate n/2 2))
                           (start3 (+ start2 n/4)))
                      (for (n/2 (i start)
                                (j start2))
                        (let ((x (aref vec i))
                              (y (aref vec j)))
                          (setf (aref vec i) (+ x y)
                                (aref vec j) (- x y))))
                      (rec start n/2)
                      (for (n/4 (i start2)
                                (j start3)
                                (k (+ n/2 +twiddle-offset+) 2))
                        (let ((x (aref vec i))
                              (y (mul-i (aref vec j)))
                              (t1 (aref twiddle k))
                              (t2 (aref twiddle (1+ k))))
                          (setf (aref vec i) (* t1 (+ x y))
                                (aref vec j) (* t2 (- x y)))))
                      (rec start2 n/4)
                      (rec start3 n/4)))
                   ((= n 2)
                    (let ((s0 (aref vec start))
                          (s1 (aref vec (1+ start))))
                      (setf (aref vec start) (+ s0 s1)
                            (aref vec (1+ start)) (- s0 s1)))
                    nil))))
    (rec start n)
    vec))

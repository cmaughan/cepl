(in-package :cgl)
(named-readtables:in-readtable fn_::fn_lambda)

(defun parse-compose-gpipe-args (args)
  `(,(mapcar (fn+ #'car #'last1) args)
    nil))

(defun %defpipeline-compose (name args options gpipe-args)
  (assert (and (every #'symbolp args) (not (some #'keywordp args))))
  (destructuring-bind (args &optional user-uniforms)
      (split-sequence :&uniform args :test #'string-equal)
    (assoc-bind ((fbos :fbos) (context :context) (post :post))
        (parse-options options)
      (destructuring-bind (pipeline-names gpipe-context)
          (parse-compose-gpipe-args gpipe-args)
        (assert (not (and gpipe-context context)))
        (let* ((uniform-args (make-pipeline-uniform-args
                              pipeline-names
                              (get-overidden-uniforms gpipe-args)))
               (uniforms
                (append (mapcar #'first uniform-args)
                        user-uniforms))
               (stream-args (%number-args (collate-args pipeline-names)))
               (args (append (apply #'append stream-args) args)))
          `(progn
             (eval-when (:compile-toplevel :load-toplevel :execute)
                 (update-pipeline-spec
                  (make-compose-pipeline-spec
                   ',name ',pipeline-names ',args ',uniform-args
                   ',(or gpipe-context context))))
             (let (,@(when fbos (mapcar #'car fbos))
                   (initd nil))
               (def-compose-dispatch ,name ,args ,uniforms ,context
                                     ,gpipe-args ,pipeline-names ,fbos ,post))
             (def-compose-dummy ,name ,args ,uniforms)))))))

(defun %number-args (collated-args)
  (mapcar #'second
          (reverse
           (reduce (lambda (c x)
                     (let ((len (+ (apply #'+ (mapcar #'first c)) (length x))))
                       (cons (list len (loop for i from (or (caar c) 0)
                                          below len collect (symb 'stream i)))
                             c)))
                   collated-args
                   :initial-value nil))))

;;--------------------------------------------------

(defmacro def-compose-dispatch (name args uniforms context
                                gpipe-args pipeline-names fbos post)
  (declare (ignore context))
  `(defun ,(dispatch-func-name name)
       (,@args ,@(when uniforms `(&key ,@uniforms)))
     (unless initd
       ,@(mapcar #'fbo-comp-form fbos)
       (setf initd t)
       ,(when post `(funcall ,post)))
     ,@(mapcar #'make-map-g-pass gpipe-args
               (%number-args (collate-args pipeline-names)))))

(defun fbo-comp-form (form)
  (destructuring-bind (name . make-fbo-args) form
    `(setf ,name (make-fbo ,@make-fbo-args))))

(defun make-map-g-pass (pass-form stream-args)
  (destructuring-bind (fbo &rest call-forms) pass-form
    (let* ((lisp-forms (butlast call-forms))
           (call-form (last1 call-forms))
           (func-name (first call-form))
           (map-g-form `(map-g #',func-name ,@stream-args ,@(rest call-form)
                             ,@(mapcat #'%uniform-arg-to-call
                                       (get-pipeline-uniforms func-name
                                                              call-form)))))
      (if fbo
          `(with-bind-fbo (,@(listify fbo))
             ,@lisp-forms
             ,map-g-form)
          (if lisp-forms
              `(progn
                 ,@lisp-forms
                 ,map-g-form)
              map-g-form)))))

(defun %uniform-arg-to-call (uniform-arg)
  `(,(kwd (first uniform-arg)) ,(first uniform-arg)))

;;--------------------------------------------------

(defmacro def-compose-dummy (name args uniforms)
  `(defun ,name (,@args ,@(when uniforms `(&key ,@uniforms)))
     (declare (ignorable ,@uniforms ,@args))
     (error "Pipelines do not take a stream directly, the stream must be map-g'd over the pipeline")))

;;--------------------------------------------------

(defun collate-args (pipeline-names)
  (mapcar #'%collate-args (get-pipeline-specs pipeline-names)))
(defmethod %collate-args ((spec shader-pipeline-spec))
  (slot-value (gpu-func-spec (first (slot-value spec 'stages))) 'in-args))
(defmethod %collate-args ((spec compose-pipeline-spec))
  (slot-value spec 'in-args))

(defun get-pipeline-specs (pipeline-names)
  (mapcar #'pipeline-spec pipeline-names))

(defun get-overidden-uniforms (pass-forms)
  (let* ((forms (mapcar #'last1 pass-forms)))
    (mapcar λ(remove-if-not #'keywordp _) forms)))

;;{TODO} handle equivalent types
(defun make-pipeline-uniform-args (pipeline-names overriden-uniforms)
  (let ((all-uniforms
         (mapcat (lambda (uniforms overriden)
                   (loop :for uniform :in uniforms
                      :if (not (member (first uniform) overriden
                                       :test #'string-equal))
                      :collect uniform))
                 (mapcar #'get-pipeline-uniforms pipeline-names)
                 overriden-uniforms)))
    (%aggregate-uniforms all-uniforms)))

(defun get-pipeline-uniforms (pipeline-name &optional call-form)
  (%get-pipeline-uniforms (pipeline-spec pipeline-name) call-form))

(defmethod %get-pipeline-uniforms
    ((pipeline-spec shader-pipeline-spec) call-form)
  (let ((result (aggregate-uniforms (slot-value pipeline-spec 'stages)))
        (overriden-uniforms (remove-if-not #'keywordp call-form)))
    (remove-if λ(member _ overriden-uniforms
                        :test (lambda (x y) (string-equal (car x) y)))
               result)))

(defmethod %get-pipeline-uniforms
    ((pipeline-spec compose-pipeline-spec) call-form)
  (let ((result (slot-value pipeline-spec 'uniforms))
        (overriden-uniforms (remove-if-not #'keywordp call-form)))
    (remove-if λ(member _ overriden-uniforms
                        :test (lambda (x y) (string-equal (car x) y)))
               result)))

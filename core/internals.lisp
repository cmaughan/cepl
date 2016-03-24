(in-package :cepl.internals)

(defgeneric populate (object data))

(defmethod dimensions ((object t))
  (error "Jungl: Cannot extract dimensions from ~s object:~%~s"
	 (type-of object) object))

(defun 1d-p (object)
  (= 1 (length (dimensions object))))

(defgeneric gl-assign-attrib-pointers (array-type &optional attrib-num
                                              pointer-offset
                                              stride-override
						    normalised))

(defmethod gl-assign-attrib-pointers ((array-type t) &optional (attrib-num 0)
                                                       (pointer-offset 0)
                                                       stride-override
                                                       normalised)
  (let ((type (varjo:type-spec->type array-type)))
    (if (and (varjo:core-typep type) (not (varjo:v-typep type 'v-sampler)))
        (let ((slot-layout (cepl.types::expand-slot-to-layout
			    nil type normalised))
              (stride 0))
          (loop :for attr :in slot-layout
             :for i :from 0
             :with offset = 0
             :do (progn
                   (gl:enable-vertex-attrib-array (+ attrib-num i))
                   (%gl:vertex-attrib-pointer
                    (+ attrib-num i) (first attr) (second attr)
                    (third attr) (or stride-override stride)
                    (cffi:make-pointer (+ offset pointer-offset))))
             :do (setf offset (+ offset (* (first attr)
                                           (gl-type-size (second attr))))))
          (length slot-layout))
        (error "Type ~a is not known to cepl" type))))

(defgeneric clear-gl-context-cache (object))
(defgeneric s-arrayp (object))
(defgeneric s-prim-p (spec))
(defgeneric s-extra-prim-p (spec))
(defgeneric s-def (spec))
(defgeneric make-vao-from-id (gl-object gpu-arrays &optional index-array))
(defgeneric %collate-args (spec))
(defgeneric %get-pipeline-uniforms (pipeline-spec call-form))


(defgeneric symbol-names-cepl-structp (sym))
(defmethod symbol-names-cepl-structp ((sym t))
  nil)


(defun color-attachment-enum (attachment-num)
  (+ attachment-num #.(cffi:foreign-enum-value '%gl:enum :color-attachment0)))

(defvar %default-framebuffer nil)
(defvar %current-fbo nil)
(defvar *gl-window* nil)
(defvar *on-context* nil)

(defun gl-type-size (type)
  (if (keywordp type)
      (cffi:foreign-type-size type)
      (autowrap:foreign-type-size type)))

(defvar *expanded-gl-type-names*
  '((:uint :unsigned-int) (:ubyte :unsigned-byte)
    (:ubyte :unsigned-byte) (:ushort :unsigned-short)))

(defun expand-gl-type-name (type)
  (or (second (assoc type *expanded-gl-type-names*))
      type))

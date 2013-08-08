;;;--------------------------------------------------------------
;;; BUFFERS ;;;
;;;---------;;;

(defstruct glbuffer
  "This is our opengl buffer object. Along with the opengl
   buffer name (buffer-id) we also store the layout of the data
   within the buffer.
   This layout is as follows:
   `((data-type data-index-length offset-in-bytes-into-buffer))
   for example:
   `((:float 10 0) ('vert-data 50 40))"
  (buffer-id (car (gl:gen-buffers 1)))
  (format nil))

;; [TODO] Implement buffer freeing properly
(let ((buffer-pool nil))
  (defun add-buffer-to-pool (buffer)
    (setf buffer-pool (cons buffer buffer-pool))
    buffer)
  (defun free-all-buffers-in-pool ()
    (mapcar #'(lambda (x) (declare (ignore x))
                      (print "freeing a buffer")) 
            buffer-pool)))

;; [TODO] This needs a rework given how gl targets operate
(let ((buffer-id-cache nil)
      (buffer-target-cache nil))
  (defun bind-buffer (buffer buffer-target)
    "Binds the specified opengl buffer to the target"
    (let ((id (glbuffer-buffer-id buffer)))
      (unless (and (eq id buffer-id-cache) 
                   (eq buffer-target buffer-target-cache))
        (cl-opengl-bindings:bind-buffer buffer-target id)
        (setf buffer-target-cache id)
        (setf buffer-target-cache buffer-target))))
  (defun force-bind-buffer (buffer buffer-target)
    "Binds the specified opengl buffer to the target"
    (let ((id (glbuffer-buffer-id buffer)))
      (cl-opengl-bindings:bind-buffer buffer-target id)
      (setf buffer-id-cache id)
      (setf buffer-target-cache buffer-target)))
  (defun unbind-buffer ()
    (cl-opengl-bindings:bind-buffer :array-buffer 0)
    (setf buffer-id-cache 0)
    (setf buffer-target-cache :array-buffer)))

(defun gen-buffer (&key initial-contents 
                     (buffer-target :array-buffer) 
                     (usage :static-draw))
  (declare (symbol buffer-target usage))
  "Creates a new opengl buffer object. 
   Optionally you can provide a gl-array as the :initial-contents
   to have the buffer populated with the contents of the array"
  (let ((new-buffer (make-glbuffer)))
    (if initial-contents
        (buffer-data new-buffer initial-contents buffer-target
                     usage)
        new-buffer)))

;; buffer format is a list whose sublists are of the format
;; type, index-length, byte-offset-from-start-of-buffer

(defun buffer-data (buffer gl-array buffer-target usage
                    &key (offset 0)
                      (size (gl-array-byte-size gl-array)))
  "This function populates an opengl buffer with the contents 
   of the array. You also pass in the buffer type and the 
   draw type this buffer is to be used for.
   
   The function returns a buffer object with its format slot
   populated with the details of the data stored within the buffer"
  (bind-buffer buffer buffer-target)
  (%gl:buffer-data buffer-target 
                   size
                   (cffi:inc-pointer (pointer gl-array)
                                     (foreign-type-index (array-type gl-array)
                                                         offset))
                   usage)
  (setf (glbuffer-format buffer) 
        (list (list (array-type gl-array) (array-length gl-array) 0)))
  buffer)


(defun buffer-sub-data (buffer gl-array byte-offset buffer-target
                        &key (safe t))  
  "This function replaces a subsection of the data in the 
   specified buffer with the data in the gl-array.
   The byte offset specified where you wish to start overwriting 
   data from. 
   When the :safe option is t, the function checks to see if the 
   data you are about to write into the buffer will cross the 
   boundaries between data already in the buffer and will emit 
   an error if you are."
  (let ((byte-size (gl-array-byte-size gl-array)))
    (when (and safe (loop for format in (glbuffer-format buffer)
                       when (and (< byte-offset (third format))
                                 (> (+ byte-offset byte-size)
                                    (third format)))
                       return t))
      (error "The data you are trying to sub into the buffer crosses the boundaries specified in the buffer's format. If you want to do this anyway you should set :safe to nil, though it is not advised as your buffer format would be invalid"))
    (bind-buffer buffer buffer-target)
    (%gl:buffer-sub-data buffer-target
                         byte-offset
                         byte-size
                         (pointer gl-array)))
  buffer)


(defun multi-buffer-data (buffer arrays buffer-target usage)
  "This beast will take a list of arrays and auto-magically
   push them into a buffer taking care of both interleaving 
   and sequencial data and handling all the offsets."
  (let* ((array-byte-sizes (loop for array in arrays
                              collect 
                                (gl-array-byte-size array)))
         (total-size (apply #'+ array-byte-sizes)))
    (bind-buffer buffer buffer-target)
    (buffer-data buffer (first arrays) buffer-target usage
                 :size total-size)
    (setf (glbuffer-format buffer) 
          (loop for gl-array in arrays
             for size in array-byte-sizes
             with offset = 0
             collect (list (array-type gl-array)
                           (array-length gl-array)
                           offset)
             do (buffer-sub-data buffer gl-array offset
                                 buffer-target)
               (setf offset (+ offset size)))))
  buffer)

(defun buffer-reserve-raw-block (buffer size-in-bytes buffer-target 
                                 usage)
  "This function creates an empty block of data in the opengl buffer.
   It will remove ALL data currently in the buffer. It also will not
   update the format of the buffer so you must be sure to handle this
   yourself. It is much safer to use this as an assistant function to
   one which takes care of these issues"
  (bind-buffer buffer buffer-target)
  (%gl:buffer-data buffer-target size-in-bytes
                   (cffi:null-pointer) usage)
  buffer)

(defun buffer-reserve-block (buffer type length buffer-target usage)
  "This function creates an empty block of data in the opengl buffer
   equal in size to (* length size-in-bytes-of-type).
   It will remove ALL data currently in the buffer"
  (bind-buffer buffer buffer-target)
  (buffer-reserve-raw-block buffer
                            (foreign-type-index type length)
                            buffer-target
                            usage)
  ;; make format
  (setf (glbuffer-format buffer) `((,type ,length ,0)))
  buffer)

(defun buffer-reserve-blocks (buffer types-and-lengths
                              buffer-target usage)
  "This function creates an empty block of data in the opengl buffer
   equal in size to the sum of all of the 
   (* length size-in-bytes-of-type) in types-and-lengths.
   types-and-lengths should be of the format:
   `((type length) (type length) ...etc)
   It will remove ALL data currently in the buffer"
  (let ((size-in-bytes 0))
    (setf (glbuffer-format buffer) 
          (loop for (type length)
             in types-and-lengths
             do (incf size-in-bytes 
                      (foreign-type-index type length))
             collect `(,type ,length ,size-in-bytes)))
    (buffer-reserve-raw-block buffer size-in-bytes
                              buffer-target usage)
    buffer))
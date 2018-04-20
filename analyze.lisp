(defun previous (e l)
  (second (member e (reverse l))))

(defun live-set (identifier code all-code &optional (visited '()))
    (unless (or (member (car code) visited)
                (not code))
      (let ((instruction (first code))
            (next-instruction (second code)))
        (when (instruction-p instruction)
          (if (not visited)
            (setf visited (list instruction))
            (push instruction (cdr (last visited))))
          (let (this next branch)
            (when (instruction-target instruction)
              (setf branch (live-set
                              identifier
                              (target instruction all-code)
                              all-code
                              visited)))
            (unless (or (not next-instruction)
                        (eq (instruction-dest next-instruction)
                            identifier))
              (setf next (live-set identifier (cdr code) all-code visited)))
            (when (or (uses identifier instruction)
                      next)
              (setf this (list instruction)))
            (concatenate 'list this next branch))))))

(defun target (instruction code)
  (member-if (lambda (e) (equal (instruction-name e)
                                (instruction-target instruction)))
               code))

(defun uses (identifier instruction)
 (with-slots (arg1 arg2 arg3 arg4 arg5 parameters) instruction
   (or (eq arg1 identifier)
       (eq arg2 identifier)
       (eq arg3 identifier)
       (eq arg4 identifier)
       (eq arg5 identifier)
       (loop for param in parameters
         thereis (eq parameters identifier)))))

(defun all-bindings (all-code)
 (loop with dest
       with instruction
       for code on all-code
       do (setf instruction (first code))
       when instruction
         do (setf dest (instruction-dest instruction))
         when dest
           collect (list dest
                         instruction
                         (live-set dest (cdr code) all-code))))

(defparameter *analyzers* (list))
(defmacro def-analyzer (scopes &rest body)
  `(push (lambda (this bindings)
           (destructuring-bind (identifier instruction set) this
             (when (member (identifier-scope identifier)
                    ',scopes)
               ,@body)))
         *analyzers*))

(def-analyzer (:local :temp)
  (unless set
    (setf (instruction-dest instruction) +nonevar+)
    t))

(def-analyzer (:temp)
  (loop with sibling-bindings = (intersecting-bindings this bindings t)
        for binding in bindings
        for (b-identifier b-instruction b-set) in bindings
        when (eq b-instruction instruction)
          do (return nil)
        when (and (disjoint this binding)
                  (eq :temp (identifier-scope b-identifier))
                  (not (eq identifier b-identifier))
                  (eq (identifier-type identifier)
                      (identifier-type b-identifier)))
          unless (loop for sibling in sibling-bindings
                       thereis (not (disjoint sibling binding)))
            do (rewrite-binding this b-identifier)
               (loop for sibling in sibling-bindings
                     do (rewrite-binding sibling b-identifier)
                     finally (return t))))

(defun analyze (code)
  (let ((bindings (all-bindings code))
        (any-change nil))
    (loop for binding in bindings
      do (loop for analyzer in *analyzers*
           do (setf any-change (or (funcall analyzer binding bindings)
                                   any-change))))
    any-change))

(defun disjoint (binding1 binding2)
 (unless (eq binding1 binding2)
   (not (intersection (third binding1) (third binding2)))))

(defun disjoint-from-every (binding identifier bindings)
  (not (loop for binding2 in (intersecting-bindings binding bindings)
            thereis (eq identifier (first binding2)))))

(defun intersecting-bindings (binding1 bindings &optional self)
  (destructuring-bind (identifier1 instruction1 set1) binding1
   (loop for binding2 in bindings
         for (identifier2 instruction2 set2) in bindings
         unless (eq binding1 binding2)
           if (and self
                   (eq identifier1 identifier2)
                   (intersection set1 set2))
             collect binding2
           else
             when (intersection set1 set2)
               collect binding2)))

(defun rewrite-binding (binding new)
  (let ((old (first binding)))
   (setf (first binding) new
         (instruction-dest (second binding)) new)
   (loop for instruction in (third binding)
         do (rewrite-arguments instruction old new))))

(defun rewrite-arguments (instruction old new)
  (loop for slot in '(arg1 arg2 arg3 arg4 arg5)
       when (eq (slot-value instruction slot)
                 old)
         do (setf (slot-value instruction slot) new)))

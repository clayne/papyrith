
(in-package :papyrith)

(defvar *input-stream*)
(defvar *unread-buffer*)

(defun read-token (&optional (error-on-eof t))
  (let ((*package* (find-package :papyrith)))
    (if *unread-buffer*
      (pop *unread-buffer*)
      (read *input-stream* error-on-eof :eof))))

(defun unread-token (token)
  (push token *unread-buffer*)
  token)

(defun peek-token (&optional (number 1))
  (if (eq number 1)
    (unread-token (read-token nil))
    (let ((this-token (read-token nil))
          (token (peek-token (1- number))))
      (unread-token this-token)
      token)))

(defun read-type ()
  (if (and (eq (peek-token 2) '[)
           (eq (peek-token 3) ']))
    (make-keyword (symb (read-token) (read-token) (read-token)))
    (make-keyword (read-token))))

(defun peek-after-type (&optional (number 1))
  (if (and (eq (peek-token 2) '[)
           (eq (peek-token 3) ']))
    (peek-token (+ number 3))
    (peek-token (+ number 1))))

(defun end-of-input ()
  (or (eq (peek-token) :eof)
      (and (eq (peek-token) #\Newline)
           (eq (peek-token 2) :eof))))

(defun end-of-line ()
  (or (end-of-input)
      (eq (peek-token) #\Newline)))

(defun consume-newlines ()
  (when (end-of-line)
    (read-token)))

(defun check (&rest tokens)
  (unless (end-of-input)
    (loop for token in tokens
          thereis (equal (peek-token) token))))

(defun match (&rest tokens)
  (loop for token in tokens
        when (check token)
        return (read-token)))

(defun expect (token &optional message)
  (declare (ignore message))
  (when (check token)
    (read-token)))

(defmacro def-binary-operator-parsers (name next-parser &rest operators)
  (let ((parser-name (symb 'parse- name))
        (next-parser-name (symb 'parse- next-parser)))
    `(defun ,parser-name ()
      (let ((expr (,next-parser-name))
            operator right)
        (loop do (setf operator (match ,@operators))
              while operator
              do (setf right (,next-parser-name)
                       expr (list operator expr right)))
        expr))))

(defun parse-primary ()
  (if (match '|(|)
    (let (expr)
      (setf expr (parse-expression))
      (expect '|)|)
      expr)
    (read-token)))

(defun finish-call (callee)
  (let (args)
    (unless (match '|)|)
      (setf args (loop collect (parse-expression)
                       while (match '|,|))))
    (expect '|)|)
    `(call ,callee ,@args)))

(defun parse-argument ()
  (let (name value)
    (when (eq (peek-token 2) '=)
      (setf name (read-token))
      (expect '=))
    (setf value (parse-expression))
    (if name
      (list (make-keyword name) value)
      value)))

(defun parse-call ()
  (let ((expr (parse-primary)))
    (loop if (match '|(|)
          do (setf expr (finish-call expr))
          else if (match '|.|)
          do (setf expr `(|.| ,expr ,(read-token)))
          else if (match '[)
          do (setf expr (list 'aref expr (parse-expression)))
             (expect '])
          else do (loop-finish))
    expr))

(def-binary-operator-parsers cast call 'as 'is)

(defun parse-urnary ()
  (aif (match '! '-)
    (list it (parse-urnary))
    (parse-cast)))

(def-binary-operator-parsers multiplication urnary '/ '*)
(def-binary-operator-parsers addition multiplication '- '+)
(def-binary-operator-parsers equality addition '!= '== '> '>= '< '<=)
(def-binary-operator-parsers and equality '&&)
(def-binary-operator-parsers or and '||)
(def-binary-operator-parsers assignment or '= '+= '-= '*= '/= '%=)

(defun parse-expression ()
  (parse-assignment))

(defun parse-end ()
  (unless (end-of-input)
    (expect #\Newline)))

(defun parse-until (parser &rest end-tokens)
  (consume-newlines)
  (loop until (apply #'check end-tokens)
        collect (funcall parser)
        do (consume-newlines)))

(defun parse-if-clause ()
  (match 'if 'elseif)
  (consume-newlines)
  `(,(parse-expression)
    ,@(parse-until #'parse-statement 'else 'elseif 'endif)))

(defun parse-if ()
  (let (clauses else-clause)
    (setf clauses (parse-until #'parse-if-clause 'else 'endif))
    (when (match 'else)
      (setf else-clause `((1 ,@(parse-until #'parse-statement 'endif)))))
    (expect 'endif)
    (consume-newlines)
    `(if ,@clauses ,@else-clause)))

(defun parse-body (end)
  (loop until (equal (peek-token) end)
        collect (parse-statement)))

(defun parse-while ()
  (let (condition body)
    (consume-newlines)
    (expect 'while)
    (setf condition (parse-expression))
    (parse-end)
    (setf body (parse-until #'parse-statement 'endwhile))
    (expect 'endwhile)
    (consume-newlines)
    `(while ,condition ,@body)))

(defun parse-for ())
(defun parse-forin ())
(defun parse-switch ())

(defun parse-return ()
  (consume-newlines)
  (expect 'return)
  (let (value)
    (unless (end-of-line)
      (setf value (parse-expression)))
    (parse-end)
    (if value
      (list 'return value)
      '(return))))

(defun parse-break ()
  (consume-newlines)
  (expect 'break)
  (parse-end)
  '(break))

(defun parse-continue ()
  (consume-newlines)
  (expect 'continue)
  (parse-end)
  '(continue))

(defun parse-definition ()
  (if (and (symbolp (peek-token))
           (symbolp (peek-after-type 1))
           (or (eq (peek-after-type 2) '=)
               (eq (peek-after-type 2) #\Newline)))
    (let (type name value)
      (setf type (read-type)
            name (read-token))
      (when (eq (peek-token) '=)
        (read-token)
        (setf value (list (parse-expression))))
      (parse-end)
      `(variable ,type ,name ,@value))
    (parse-expression)))

(defun parse-statement ()
  (case (peek-token)
    (if (parse-if))
    (while (parse-while))
    (for (parse-for))
    (forin (parse-forin))
    (switch (parse-switch))
    (return (parse-return))
    (break (parse-break))
    (continue (parse-continue))
    (t (parse-definition))))

(defun parse-struct ())
(defun parse-property ())

(defun parse-property-group()
  (expect 'propertygroup)
  (let ((properties (parse-until #'parse-property 'endpropertygroup)))
    (expect 'endpropertygroup)
    `(property-group ,@properties)))

(defun parse-state ())

(defun parse-import ()
  (expect 'import)
  (let ((script (read-token)))
    (parse-end)
    (list 'import script)))

(defun parse-argument-definitions ()
  (expect '|(|)
  (unless (match '|)|)
    (loop collect (list (make-keyword (read-type)) (read-token))
          until (match '|)|)
          while (match '|,|))))

(defun parse-function ()
  (let (type name arguments flags docstring body)
    (unless (match 'function)
      (setf type (list :return-type (read-type)))
      (expect 'function))
    (setf name (read-token)
          arguments (list :parameters (parse-argument-definitions))
          flags (parse-flags 'global)
          docstring (parse-docstring))
    (parse-end)
    (setf body (parse-until #'parse-statement 'endfunction))
    (expect 'endfunction)
    (parse-end)
    `(function (,name ,@type ,@docstring ,@arguments) ,@body)))

(defun parse-variable () (parse-statement))
(defun parse-toplevel-form ()
  (case (peek-token)
    (struct (parse-struct))
    (propertygroup (parse-property-group))
    (state (parse-state))
    (import (parse-import))
    (function (parse-function))
    (t (case (peek-after-type)
         (property (parse-property))
         (function (parse-function))
         (t (parse-variable))))))

(defun parse-extends ()
  (when (match 'extends)
    (list :extends (read-token))))

(defun parse-native ()
  (when (match 'native)
    '(:native t)))

(defun parse-flags (flags)
  (unless (end-of-line)
    (list :flags
          (loop with flag
                until (end-of-line)
                do (setf flag (read-token))
                when (member flag flags)
                collect (make-keyword flag)
                finally (parse-end)))))

(defun parse-docstring ()
  (consume-newlines)
  (when (stringp (peek-token))
    (list :docstring (string-trim " " (read-token)))))

(defun parse-toplevel-forms ()
  (consume-newlines)
  (loop until (end-of-input)
        collect (parse-toplevel-form)))

(defun phony-reader (c)
  (lambda (stream char)
    (declare (ignore stream char))
    (values c)))

(defun docstring-reader (stream char)
  (declare (ignore char))
  (concatenate 'string
               (loop until (equal (peek-char nil stream) #\})
                     collect (read-char stream)
                     finally (read-char stream))))

(defun newline-reader (stream char)
  (declare (ignore stream char))
  (loop while (eq (peek-token) #\Newline)
        do (read-token))
  #\Newline)

(defun op-assign-reader ()
  (lambda (stream char)
    (if (equal #\= (peek-char nil stream))
      (progn (read-char stream)
             (values (symb char '=)))
      (values (symb char)))))

(defun parse-script (stream)
  (let ((*input-stream* stream)
        (*unread-buffer* (list))
        (*readtable* (copy-readtable)))
    (set-macro-character #\+ (op-assign-reader))
    (set-macro-character #\- (op-assign-reader))
    (set-macro-character #\* (op-assign-reader))
    (set-macro-character #\/ (op-assign-reader))
    (set-macro-character #\% (op-assign-reader))
    (set-macro-character #\= (phony-reader '=))
    (set-macro-character #\! (phony-reader '!))
    (set-macro-character #\[ (phony-reader '[))
    (set-macro-character #\] (phony-reader ']))
    (set-macro-character #\, (phony-reader '|,|))
    (set-macro-character #\. (phony-reader '|.|))
    (set-macro-character #\( (phony-reader '|(|))
    (set-macro-character #\) (phony-reader '|)|))
    (set-macro-character #\{ #'docstring-reader)
    (set-macro-character #\Newline #'newline-reader)
    (expect 'scriptname)
    `(script (,(read-token)
              ,@(parse-extends)
              ,@(parse-native)
              ,@(parse-flags '(conditional const debugonly betaonly hidden default))
              ,@(parse-docstring))
      ,@(parse-toplevel-forms))))

(defun parse-script-from-file (path)
  (declare (ignore path)))

(defun parse-script-from-string (string)
  (with-input-from-string (stream string)
    (parse-script stream)))

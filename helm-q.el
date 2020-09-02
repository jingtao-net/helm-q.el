;;; helm-q.el --- A library to manage remote q sessions with Helm and q-mode  -*- lexical-binding: t; -*-

;; URL: https://github.com/emacs-q/helm-q.el
;; Package-Requires: ((emacs "26.1") (cl-lib "0.6") (helm "1.9.4") (s "1.10.0") (q-mode "0.1") (cl-lib "1.0"))

;;; Commentary:

;; helm-q is an Emacs Lisp library to manage remote q sessions with Helm and q-mode.

;;; Code:

;; The code is automatically generated by function `literate-elisp-tangle' from file `helm-q.org'.
;; It is not designed to be readable by a human.
;; It is generated to load by Emacs directly without depending on `literate-elisp'.
;; you should read file `helm-q.org' to find out the usage and implementation detail of this source file.


(require 's)
(require 'cl-lib)
(require 'helm)
(require 'q-mode)
;;; Code:

(defgroup helm-q nil
  "Helm mode for managing kdb+/q instances."
  :group 'helm)

(defcustom helm-q-config-directory "~/.helm-q/"
  "The directory containing kdb connection files."
  :group 'helm-q
  :type 'string)

(defcustom helm-q-password-storage nil ; Change to 'pass will enable password storage via the standard unix password manager.
  "The default storage method to use."
  :group 'helm-q
  :options '(nil pass)
  :type 'symbol)

(defclass helm-q-source (helm-source-sync)
  ((instance-list
    :initarg :instance-list
    :initform #'helm-q-instance-list
    :custom function
    :documentation
    "  A function with no arguments to create instance list.")
   (candidate-columns
    :initform '(address service env region)
    :documentation "The columns used to display each candidate.")
   (candidate-columns-width-hash
    :initform (make-hash-table :test 'equal)
    :documentation "The width of each column in candidate-columns, key is the column symbol and value is the width of it.")
   (init :initform 'helm-q-source-list--init)
   (multimatch :initform nil)
   (multiline :initform t)
   (match :initform 'helm-q-source-match-function)
   (action :initform
           '(("Connect to a pre-existing q process"            . helm-q-source-action-qcon)
             ("Display username/password for current instance" . helm-q-source-action-show-password)
             ("Add username/password for current instance"     . helm-q-source-action-add-password)
             ("Update username/password for current instance"  . helm-q-source-action-update-password)
             ))
   (filtered-candidate-transformer :initform 'helm-q-source-filtered-candidate-transformer)
   (migemo :initform 'nomultimatch)
   (volatile :initform t)
   (nohighlight :initform nil)
   ))

(defun helm-q-calculate-columns-width (instances)
  "Calculate columns width.
Argument INSTANCES: the instance list."
  (cl-loop with width-hash = (helm-attr 'candidate-columns-width-hash)
           for column in (helm-attr 'candidate-columns)
           do (cl-loop for instance in instances
                       for width = (length (cdr (assoc column instance)))
                       if (or (null (gethash column width-hash))
                              (> width (gethash column width-hash)))
                       do (setf (gethash column width-hash) width))))

(defun helm-q-instance-display-string (instance)
  "Argument INSTANCE: one instance."
  (let ((first-row (s-join helm-buffers-column-separator
                           (cl-loop for column in (helm-attr 'candidate-columns)
                                    collect (helm-substring-by-width (format "%s" (cdr (assoc column instance)))
                                                                     (gethash column (helm-attr 'candidate-columns-width-hash))))))
        (context-matched-columns (helm-q-context-matched-columns instance)))
    (propertize
     (if (null context-matched-columns)
       (propertize first-row 'face 'bold)
       (concat (propertize first-row 'face 'bold) "\n"
               (s-join helm-buffers-column-separator
                       (cons helm-buffers-column-separator
                             context-matched-columns))))
     'instance instance)))

(defun helm-q-instance-list ()
  "Load source from json files in a directory."
  (require 'json)
  (let ((instances (cl-loop for file in (directory-files helm-q-config-directory t ".json$")
                            append (cl-loop for instance across (json-read-file file)
                                            collect instance))))
    (helm-q-calculate-columns-width instances)
    ;; a list whose members are `(DISPLAY . REAL)' pairs.
    (cl-loop for instance in instances
             collect (cons (helm-q-instance-display-string instance) instance))))

(defun helm-q-source-list--init ()
  "Initialize helm-q-source."
  (helm-attrset 'candidates (funcall (helm-attr 'instance-list))))

(defun helm-q-get-instance-by-display (display-str)
  "Get an instance by its display string.
Argument DISPLAY-STR: the display string."
  (cl-loop with candidates = (helm-attr 'candidates)
           for candidate in candidates
           when (string= display-str (car candidate))
           return (cdr candidate)))

(defun helm-q-context-matched-columns (instance)
  "Return a list of string for matched columns.
Argument INSTANCE: one instance."
  (unless (s-blank? helm-pattern)
    (append
     (cl-loop for table-columns in (cdr (assoc 'tablescolumns instance))
              for tab-name = (format "%s" (car table-columns))
              append (append (if (helm-buffer--match-pattern helm-pattern tab-name nil)
                                 (list (format "Table:'%s'" tab-name)))
                             (cl-loop for column-name across (cdr table-columns)
                                      if (helm-buffer--match-pattern helm-pattern column-name nil)
                                      collect (format "Column:'%s.%s'" tab-name column-name))))
     (cl-loop for (function) in (cdr (assoc 'functions instance))
              for function-name = (format "%s" function)
              if (helm-buffer--match-pattern helm-pattern function-name nil)
              collect (format "Function:'%s'" function-name))

     (cl-loop for variable-name across (cdr (assoc 'variables instance))
              if (helm-buffer--match-pattern helm-pattern variable-name nil)
              collect (format "Var:'%s'" variable-name)))))

(defun helm-q-source-match-function (candidate)
  "Default function to match buffers.
Argument CANDIDATE: one helm candidate."
  (let ((instance (helm-q-get-instance-by-display candidate))
        (helm-buffers-fuzzy-matching t))
    (or
      (cl-loop for slot in (helm-attr 'candidate-columns)
               for slot-value = (cdr (assoc slot instance))
               thereis (helm-buffer--match-pattern helm-pattern slot-value nil))
      (helm-q-context-matched-columns instance))))

(defun helm-q-source-filtered-candidate-transformer (candidates source)
  "Filter candidates by context match.
Argument CANDIDATES: the candidate list.
Argument SOURCE: the source."
  (cl-loop for (nil . instance) in candidates
           collect (cons (helm-q-instance-display-string instance) instance)))

(defvar helm-q-pass-prefix "helm-q")

(defun helm-q-pass-path-of-host (host)
  "Get the path for an host.
Argument HOST: the host of an instance."
  (format "%s/%s/" helm-q-pass-prefix host))

(defun helm-q-pass-path-of-host-user (host user)
  "Get the path for an host.
Argument HOST: the host of an instance.
Argument USER: the user for the host."
  (format "%s/%s/%s" helm-q-pass-prefix host user))

(cl-defgeneric helm-q-pass-users-of-host (storage host)
  "Get a list of users by its host.
Argument STORAGE: a valid storage method.
Argument HOST: a host.")

(cl-defgeneric helm-q-get-pass (storage host user)
  "Get pass by its host and user.
Argument STORAGE: a valid storage method.
Argument HOST: a host.
Argument USER: an user name.")

(cl-defgeneric helm-q-update-pass (storage host user &optional password)
  "Update user and pass to local encrypted storage file.
Argument STORAGE: a valid storage method.
Argument HOST: the host of an instance.
Argument USER: the user for the instance.
Argument PASSWORD: the optional password for the instance.")

(cl-defmethod helm-q-pass-users-of-host ((storage (eql nil)) host)
  "Get a list of users by its host.
Argument STORAGE: should be 'pass
Argument HOST:"
  nil)

(cl-defmethod helm-q-get-pass ((storage (eql nil)) host user)
  "Get pass by its host and user.
Argument STORAGE: should be 'pass
Argument HOST:
Argument USER:"
  nil)

(cl-defmethod helm-q-update-pass ((storage (eql nil)) host user &optional password)
  "Update user and pass to local pass storage file.
Argument STORAGE: should be 'pass
Argument HOST: the host of an instance.
Argument USER: the user for the instance.
Argument PASSWORD: the optional password for the instance."
  (message "You can't save password because this feature is disabled by Emacs lisp variable 'helm-q-password-storage'."))

(defun helm-q-run-pass (infile &rest args)
  "Run pass with args.
Argument INFILE: input file for pass process.
Argument ARGS: additional arguments for pass."
  (with-temp-buffer
      (let* ((exit-code (apply 'call-process "pass" infile (current-buffer) t args))
             (result (string-trim (buffer-string))))
        (cons (= 0 exit-code) result))))

(cl-defmethod helm-q-pass-users-of-host ((storage (eql pass)) host)
  "Get a list of users by its host.
Argument STORAGE: should be 'pass
Argument HOST:"
  (cl-destructuring-bind (succ-p . result)
      (helm-q-run-pass nil "ls" (helm-q-pass-path-of-host host))
    (when succ-p
      (let ((words (split-string result)))
        ;; th words list has the format `("helm-q/host.domain.com:5000" "├──" "user1" "└──" "user2")' .
        (cl-loop for user-list on (cdr words) by 'cddr
                 collect (second user-list))))))

(cl-defmethod helm-q-get-pass ((storage (eql pass)) host user)
  "Get pass by its host and user.
Argument STORAGE: should be 'pass
Argument HOST:
Argument USER:"
  (cl-destructuring-bind (succ-p . entry)
      (helm-q-run-pass nil "show" (helm-q-pass-path-of-host-user host user))
    (when succ-p
      entry)))

(cl-defmethod helm-q-update-pass ((storage (eql pass)) host user &optional password)
  "Update user and pass to local pass storage file.
Argument STORAGE: should be 'pass
Argument HOST: the host of an instance.
Argument USER: the user for the instance.
Argument PASSWORD: the optional password for the instance."
  (let* ((pass (or password (read-passwd (format "Password for %s@%s: " user host) t)))
         (in-file (make-temp-file "helm-q-")))
    ;; when insert a password in pass, it will ask for password, `call-process' will let pass read it from this input file.
    (with-temp-file in-file
      (insert pass "\n" pass "\n\n"))
    (unwind-protect
        (cl-destructuring-bind (succ-p . entry)
            (helm-q-run-pass in-file "insert" "-f" (helm-q-pass-path-of-host-user host user))
          succ-p)
      (delete-file in-file); delete this file to avoid potential security leak.
      nil)))

(defun helm-q-user (users)
  "Select a user in Helm.
Argument USERS: a user list."
  (let ((prompt "Please select an user:")
        (user "")
        (helm-source
         `((name . "helm-q-user-list")
           (candidates . ,users)
           (action . (lambda (candidate) (setf user candidate)))))
        (helm :sources '(helm-source) :prompt prompt)
        user)))

(defvar helm-q-pass-required-p nil "Switch it on when helm-q was invoked with prefix argument.")

(defun helm-q-source-action-qcon (candidate)
  "Argument CANDIDATE: selected candidate."
  (let* ((instance candidate)
         (host (cdr (assoc 'address instance)))
         (host-port (split-string host ":"))
         (q-qcon-server (car host-port))
         (q-qcon-port (or (second host-port) q-qcon-port))
         (users (helm-q-pass-users-of-host helm-q-password-storage host))
         (q-qcon-user (if helm-q-pass-required-p
                        (read-string "Please enter a new user name: " (car users))
                        (case (length users)
                          (0 "")
                          (1 (car users))
                          (2 (helm-q-user users)))))
         (q-qcon-password (when q-qcon-user
                            (if helm-q-pass-required-p
                              (read-passwd (format "Password for %s@%s: " q-qcon-user host))
                              (helm-q-get-pass helm-q-password-storage host q-qcon-user))))
         ;; KLUDGE: q-mode should supply a function to build buffer name.
         (q-buffer-name (format "*%s*" (format "qcon-%s" (q-qcon-default-args))))
         (q-buffer (get-buffer q-buffer-name)))
    (if (and q-buffer
             (process-live-p (get-buffer-process q-buffer)))
      ;; activate this buffer if the instance has already been connected.
      (q-activate-buffer q-buffer-name)
      (when (helm-q-test-active-connection host)
        (q-qcon (q-qcon-default-args))))))

(defun helm-q-source-action-show-password (candidate)
  "Show password for current instance.
Argument CANDIDATE: selected candidate."
  (if (null helm-q-password-storage)
    (message "This feature is disabled by Emacs lisp variable 'helm-q-password-storage'.")
    (let* ((instance candidate)
           (host (cdr (assoc 'address instance)))
           (users (helm-q-pass-users-of-host helm-q-password-storage host)))
      (case (length users)
        (0 (message "No username/password for host %s" host))
        (1 (message "%s@%s's password is '%s'" (car users) host (helm-q-get-pass helm-q-password-storage host (car users))))
        (t (let ((user (helm-q-user users)))
             (when user
               (message "%s@%s's password is '%s'" user host (helm-q-get-pass helm-q-password-storage host user)))))))))

(defun helm-q-source-action-add-password (candidate)
  "Add password for current instance.
Argument CANDIDATE: selected candidate."
  (if (null helm-q-password-storage)
    (message "This feature is disabled by Emacs lisp variable 'helm-q-password-storage'.")
    (let* ((instance candidate)
           (host (cdr (assoc 'address instance)))
           (user (read-string "Please enter the user name: ")))
      (if (s-blank? user)
        (message "Please input a valid user name!")
        (helm-q-update-pass helm-q-password-storage host user)))))

(defun helm-q-source-action-update-password (candidate)
  "Update password for current instance.
Argument CANDIDATE: selected candidate."
  (if (null helm-q-password-storage)
    (message "This feature is disabled by Emacs lisp variable 'helm-q-password-storage'.")
    (let* ((instance candidate)
           (host (cdr (assoc 'address instance)))
           (users (helm-q-pass-users-of-host helm-q-password-storage host)))
      (case (length users)
        (0 (message "No username/password for host %s" host))
        (1 (helm-q-update-pass helm-q-password-storage host (car users)))
        (t (let ((user (helm-q-user users)))
             (when user
               (helm-q-update-pass helm-q-password-storage host user))))))))

(defun helm-q (arg)
  "Select data source in helm.
Argument ARG: prefix argument."
  (interactive "P")
  (let ((helm-candidate-separator " ")
        (helm-q-pass-required-p (and arg t)))
    (helm :sources (list (helm-make-source "helm-running-q" 'helm-q-running-source)
                         (helm-make-source "helm-q" 'helm-q-source))
          :buffer "*helm q*")))

(defun helm-q-test-active-connection (host)
  "Test connection of qcon, return true if connection is ok.
Argument HOST: the host of current instance."
  (message "Test connection...")
  (let ((in-file (make-temp-file "helm-q-"))
        (test-message "Test Connection."))
    ;; prepare test commands in input file.
    (with-temp-file in-file
      (insert
       ;; echo a test message.
       "\"" test-message "\"" "\n"
       ;; quit from this process.
       "\\\\" "\n\n"))
    (with-temp-buffer
      (let* ((exit-code (apply 'call-process q-qcon-program in-file (current-buffer) t
                               (list (q-qcon-default-args))))
             (result (string-trim (buffer-string))))
        (delete-file in-file); remove temp file after use.
        (if (/= 0 exit-code)
          ;; if failed to connect, report the result as error message.
          (progn (message "connection failed: %s" result)
                 nil)
          (if (ignore-errors
                (goto-char (point-min))
                ;; The test message should occur in the output.
                (search-forward test-message nil nil 1))
            (progn
              ;; connection is ok, save password for this connection if it is from user input.
              (when helm-q-pass-required-p
                (helm-q-update-pass helm-q-password-storage host q-qcon-user q-qcon-password))
              t)
            (progn
              ;; invalid user/pass, ask for a new username and password.
              (message "connection is not responding: %s" result)
              (if (s-blank? q-qcon-user)
                (progn
                  ;; Prompting for user and password in case of unsuccessful passwordless connection attempt.
                  (setf q-qcon-user (read-string "Please enter the user name: " q-qcon-user))
                  (setf q-qcon-password (read-passwd "Please enter the password: "))
                  ;; test connection with new username and password.
                  (let ((helm-q-pass-required-p t)); save the password if it is ok.
                    (helm-q-test-active-connection host)))
                (progn
                  ;; Prompting for new password in case of failed authentication.
                  (setf q-qcon-password (read-passwd "Please enter the password: "))
                  ;; test connection with new username and password.
                  (let ((helm-q-pass-required-p t)); save the password if it is ok.
                    (helm-q-test-active-connection host)))))))))))

(defclass helm-q-running-source (helm-source-sync)
  ((buffer-list
    :initarg :buffer-list
    :initform #'helm-q-running-buffer-list
    :custom function
    :documentation
    "  A function with no arguments to get running buffer list.")
   (init :initform 'helm-q-running-source-list--init)
   (multimatch :initform nil)
   (multiline :initform nil)
   (action :initform
           '(("Select a pre-existing q process" . helm-q-running-source-action-select-an-instance)))
   (migemo :initform 'nomultimatch)
   (volatile :initform t)
   (nohighlight :initform nil)))

(defun helm-q-running-source-action-select-an-instance (candidate)
  "Select an running instance.
Argument CANDIDATE: the selected candidate."
  (q-activate-buffer candidate))

(defun helm-q-running-buffer-list ()
  "Get running Q buffers."
  (loop for buffer in (buffer-list)
        if (with-current-buffer buffer
             (equal 'q-shell-mode major-mode))
          collect (let ((buffer-name (buffer-name buffer)))
                    (if (string= buffer-name (buffer-name q-active-buffer))
                      (propertize buffer-name 'face 'bold)
                      buffer-name))))

(defun helm-q-running-source-list--init ()
  "Initialize helm-q-running-source."
  (helm-attrset 'candidates (funcall (helm-attr 'buffer-list))))

(defun helm-q-update-active-buffer (&rest args)
  "An advice function for `q-send-string'.
To update active buffer based on prefix argument.
Argument ARGS: the argument for original function."
  (let ((update-active-buffer-p nil)
        (helm-q-pass-required-p helm-q-pass-required-p))
    (case (prefix-numeric-value current-prefix-arg)
      (4 ; prefix C-u
       (setf update-active-buffer-p t))
      (16 ; prefix C-u C-u
       (setf update-active-buffer-p t
             helm-q-pass-required-p t)))
    (when update-active-buffer-p
      (let ((another-win (if (one-window-p)
                           (if (> (window-width) 100)
                             (split-window-horizontally)
                             (split-window-vertically))
                           (next-window))))
        (helm :sources (list (helm-make-source "helm-running-q" 'helm-q-running-source)
                             (helm-make-source "helm-q" 'helm-q-source))
              :buffer "*helm q*")
        (set-window-buffer another-win q-active-buffer)))))
(advice-add 'q-send-string :before #'helm-q-update-active-buffer)


(provide 'helm-q)
;;; helm-q.el ends here

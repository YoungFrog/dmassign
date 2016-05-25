;; -*- lexical-binding: t; -*-

(require 'dash)
(require 'hi-lock)

(defvar dmassign-repartition-f "repartition.txt")
(defvar dmassign-profs-f "profs.txt")

(defvar dmassign-prof-status
  '(("Assistant intérimaire" . 0)
    ("Assistant" . 1)
    ("FRIA/FNRS" . 2)
    ("Postdoc/Chargé de recherche" . 3)
    ("Chercheur qualifié / Maître d'enseignement" . 4)
    ("Chargé de cours" . 5)
    ("Professeur" . 6)
    ("Professeur ordinaire" . 7)
    ("Prof. de l'université" . 8)
    ("Prof. extérieur" . 9))
  "Voir profs.txt")

(defvar dmassign-profs-list nil)

(defstruct dmassign-profs shortname fullname initials status charge)

(defconst dmassign-conflicts-options "--task-conflicts --quiet")
(defvar dmassign-conflicts-list nil)

(defconst dmassign-profs-charge-options "--teacher-charges --quiet")

(defvar dmassign-force-update-data nil)

;;; Generic helper macros/functions
(defun dmassign-read-regexp-forward (regexp &optional n)
  "Read text matching REGEXP, starting from point. Return matched
text (or N-th subgroup) and move point past the matched text it.
Return nil if REGEXP failed to match."
  (setq n (or n 0))
  (when (re-search-forward
         (concat "\\=" regexp)
         nil t)
    (goto-char (match-end 0))
    (match-string n)))
(defmacro dmassign-collect-foreach-line (form)
  `(loop 
    until (eobp)
    collect ,form
    do (forward-line)))
(defun sort-according-to (function list &optional numericp inverse)
  (funcall (if inverse #'nreverse #'identity)
   (sort list
         (lambda (x y)
           (let ((valuex (funcall function x))
                 (valuey (funcall function y)))
             (if numericp
                 (< valuex valuey)
               (string< (format "%s" valuex) (format "%s" valuey))))))))

;;; Useful profs functions
(defun dmassign-prof-at-point nil
  "Return a structure for prof at point"
  (save-excursion
    (beginning-of-line)
    (or
     (ignore-errors
       (make-dmassign-profs
        :shortname (dmassign-read-regexp-forward "\\([^;]+\\);" 1)
        :fullname (dmassign-read-regexp-forward "\\([^;]+\\);" 1)
        :initials (dmassign-read-regexp-forward "\\([^;]+\\);" 1)
        :status (string-to-number (dmassign-read-regexp-forward "\\([^;\n]+\\)\n?" 1))))
     (error "Cannot parse line %s" (s-trim (thing-at-point 'line))))))
(defun dmassign-profs-parse ()
  "Do the actual parsing."
  (setq
   dmassign-profs-list
   (dmassign-with-file dmassign-profs-f
     (loop
      until (eobp)
      collect (dmassign-prof-at-point)
      do (forward-line)))))
(defun dmassign-profs-via-shortname (shortname)
  "Find a teacher struct by its shortname"
  (let ((candidates (-select (lambda (prof) (equal shortname (dmassign-profs-shortname prof))) (dmassign-profs-list))))
    (if (= 1 (length candidates))
        (car candidates)
      (if (= 0 (length candidates))
          (if (string-match "^XTP-" shortname)
              (dmassign-profs-via-shortname "XTP")
            (error "No match for prof: %s" shortname))
        (error "Too many profs match")))))
(defun dmassign-profs-charge-parse ()
  "Do the actual parsing and add to the teacher structures."
  (with-temp-buffer
    (call-process-shell-command "~/bin/dmassign" nil '(t nil) nil dmassign-profs-charge-options)
    (goto-char (point-min))
    (loop
     until (eobp)
     do (let* ((shortname
                (dmassign-read-regexp-forward "\\([^ ]+\\)" 1))
               (charge (string-to-number
                        (progn
                          (skip-chars-forward " ")
                          (dmassign-read-regexp-forward "[[:digit:].]+"))))
               (prof (dmassign-profs-via-shortname shortname)))
          (if prof
              (setf (dmassign-profs-charge prof) charge)
            (message "Cannot find teacher: %s" shortname)))
     do (forward-line))))
(defun dmassign-profs-get (what shortname-or-prof)
  "WHAT can be one of: shortname fullname initials status charge"
  (let ((prof (if (stringp shortname-or-prof)
                  (cdr (assoc shortname-or-prof (dmassign-profs-list)))
                shortname-or-prof)))
    (if (dmassign-profs-p prof)
        (funcall (intern (format "dmassign-profs-%s" what)) prof)
      (user-error "Cannot find prof: %s" shortname-or-prof))))
(defun dmassign-profs-list () 
  ""
  (unless dmassign-profs-list
    (dmassign-profs-parse)
    (dmassign-profs-charge-parse))
  dmassign-profs-list)
(defun dmassign-profs-status-text (prof)
  ""
  (car (nth (dmassign-profs-status prof) dmassign-prof-status)))
(defun dmassign-assistants-list () "Return everyone considered \"Assistant\" in the prof list."
  (-select (lambda (prof) (memq (dmassign-profs-status prof) (list 0 1 2 3))) (dmassign-profs-list)))

;;; Handle tasks and conflicts
(defun dmassign-conflicts-parse () "Actualparsing"
  (setq dmassign-conflicts-list
        (with-temp-buffer
          (unless (eq 0 (call-process-shell-command "~/bin/dmassign" nil '(t nil) nil dmassign-conflicts-options))
            (error "Error parsing conflicts."))
          (goto-char (point-min))
          (dmassign-collect-foreach-line 
           (mapcar
            #'dmassign-task-parse
            (split-string
             (dmassign-line-at-point)
             "|"))))))
;; (defun dmassign-conflicts-reparse-owners ()
;;   (with-current-buffer (get-buffer dmassign-repartition-f)
;;     (while (not (eobp))
;;       (when (not (dmassign-task-at-comment-p))
;;         (let* ((task-at-point (dmassign-task-at-point))
;;                (corresponding-task (dmassign-assoc-task-in-list-of-conflicts task-at-point)))
;;           (dmassign-tasks-set-owner corresponding-task (dmassign-task-get 'owner task-at-point)))
;;         (forward-line)))))
(defun dmassign-tasks-set-owner (task owner)
  ""
  (setf (nth 5 task) owner))
(defun dmassign-task-parse (rawtask)
  "Parse a single task and make it a structure that dmassign-task-get can operate on."
  (with-temp-buffer
    (insert rawtask)
    (goto-char (point-min))
    (list
     ; (when (string= "*" (dmassign-read-regexp-forward "[ *]")) 'todo) ; this is optionnal
     (or (dmassign-read-regexp-forward "\\(Th\\|Exe\\);" 1) ; type
         (error "Unparsable task: unknown task"))
     (dmassign-read-regexp-forward "\\([^;]+\\);" 1) ; mnemonic
     (dmassign-read-regexp-forward "\\([^;]*\\);" 1) ; group
     (dmassign-read-regexp-forward "\\([^;]+\\);" 1) ; modulation
     (dmassign-read-regexp-forward "\\([^;\n ]*\\)" 1) ; owner
     (dmassign-read-regexp-forward " \\(.*\\)" 1) ; rest
     )))
(defun list-to-index (list elt)
  "Behaves badly with circular lists"
  (let ((i 0))
    (while (and list (not (eq elt (car list))))
      (setq list (cdr list)
            i (1+ i)))
    (and list i)))
;(list-to-index '(foo bar baz) 'none)
(defun dmassign-task-get (type task)
  "TYPE is any of:
type mnemonic group modulation owner mnemonicnoquadri
TASK defaults to task at point if nil"
  (let* ((list-of-parsed-states '(type mnemonic group modulation owner-shortname rest)))
    (cond ((memq type list-of-parsed-states)
           (nth (list-to-index list-of-parsed-states type) task))
          ((eq type 'mnemonicnoquadri)
           (let ((mnemo (dmassign-task-get 'mnemonic task)))
             (if (string-match "/.*" mnemo)
                 (substring mnemo 0 (match-beginning 0))
               mnemo)))
          ((eq type 'trueowner)
           (with-current-buffer (get-file-buffer dmassign-repartition-f)
             (let ((trueowner-shortname (nth 4 (dmassign-task-find-task task))))
               (unless trueowner-shortname
                 (error "Could not find task or its true owner %s" task))
               (when (not (equal "" trueowner-shortname))
                 (letf (((nth 5 task) trueowner-shortname))
                   (dmassign-profs-via-shortname trueowner-shortname)))))
           (dmassign-profs-via-shortname (dmassign-task-get 'owner-shortname task)))
          ((eq type 'owner)
           (dmassign-profs-via-shortname (dmassign-task-get 'owner-shortname task)))
          ((eq type 'rawplusconflict) ;; pseudo raw, re-constructed
           (concat (dmassign-task-get 'raw task) (format " %s" (dmassign-task-get 'rest task))))
          ((eq type 'raw) ;; pseudo raw, re-constructed
           (mapconcat (lambda (x)
                        (dmassign-task-get x task))
                      '(type mnemonic group modulation owner-shortname)
                      ";"))
          ((eq type 'noowner) ;; pseudo raw, without owner
           (mapconcat (lambda (x)
                        (dmassign-task-get x task))
                      '(type mnemonic group modulation)
                      ";"))
          ((eq type 'nombredeconflits) ;; not every task object has that.
           (let ((rest (dmassign-task-get 'rest task)))
             (if (and rest (string-match "^(\\([0-9]+\\)" rest))
                 (string-to-number (match-string 1 rest))
               (error "This task has no \"number of conflicts\"")))))))
(defun dmassign-conflicts-list () ""
  (interactive "P")
  (when (not dmassign-conflicts-list)
    (message "Parsing conflicts...")
    (dmassign-conflicts-parse)
    (message "Parsing conflicts... done."))
  dmassign-conflicts-list)

(defun dmassign-task-no-owner (task) ""
  (dmassign-task-get 'noowner task))
(defun dmassign-conflicts-list-with-task (task)
  "List of tasks conflicting with the given TASK"
  (cdr
   (dmassign-assoc-task-in-list-of-conflicts task)))
(defun dmassign-conflicts-list-with-same-type (task)
  "List of task conflicting with given TASK, and with the same type"
  (let ((current-type (dmassign-task-get 'type task)))
    (-select
     (lambda (conflictingtask)    ; only those that match current type
       (string= current-type
                (dmassign-task-get 'type conflictingtask)))
     (dmassign-conflicts-list-with-task task))))
(defun dmassign-show-conflicts (task) ""
  (let* ((current-owner (dmassign-task-get 'owner-shortname task)))
    (mapconcat (lambda (task) ;; printer function
                 (apply 'propertize
                        (format "%s" (dmassign-task-get 'rawplusconflict task))
                        (when (equal (dmassign-task-get 'owner-shortname task) current-owner)
                          '(face hi-yellow))))
               (sort-according-to
                (lambda (task)
                  (dmassign-task-get 'nombredeconflits task))
                (dmassign-conflicts-list-with-same-type task)
                'numeric)
               "\n")))
(defun dmassign-tasks-equalp (x y)
  (string=
   (dmassign-task-no-owner x)
   (dmassign-task-no-owner y)))
(defun dmassign-assoc-task-in-list-of-conflicts (task)
  "Like `assoc', but the equality test is `dmassign-tasks-equalp'"
  ;; FIXME: when there are tasks like:
  ;; Th;MATHF205;MATH2;12/0/0;Ley
  ;; Th;MATHF205;MATH2;12/0/0;Bruss
  (let ((candidates (-select
                     (lambda (x)
                       (dmassign-tasks-equalp task (car x)))
                     (dmassign-conflicts-list))))
    (when (< 1 (length candidates))
      (let ((owner (dmassign-task-get 'owner task)))
        ;; if current owner is in the list of candidates he's our best
        ;; candidates.
        (--when-let
            (cl-assoc-if
             (lambda (x)
               (equal owner (dmassign-task-get 'owner x)))
             candidates )
          (setq candidates (remove it candidates))
          (push it candidates)))
      (message "Retaining only first match for task %s. Total number of matches: %s" task (length candidates)))
    (car candidates)))
(defun dmassign-find-assistant (all)
  (interactive "P")
  (let* ((task (dmassign-task-at-point))
         (conflicting-tasks (dmassign-conflicts-list-with-task task))
         (conflicting-assistants
          (mapcar (lambda (task)
                    (dmassign-task-get 'trueowner task))
                  conflicting-tasks))
         (candidates (-select
                      (lambda (x)
                        "Matches if x is not a conflicting assistant."
                        (not (-contains-p conflicting-assistants x)))
                      (if all
                          (dmassign-assistants-list)
                        (--select
                         (= (dmassign-profs-get 'status it) 1)
                         (dmassign-assistants-list)))))
         (assistant (ido-completing-read-with-printfun
                     "Assistant: "
                     (sort-according-to
                      (lambda (x)
                        (or (dmassign-profs-get 'charge x) 0))
                      candidates 'numeric 'inverse)
                     (lambda (assistant)
                       (format "%s (%s/%s)"
                               (dmassign-profs-shortname assistant)
                               (dmassign-profs-get 'charge assistant)
                               (dmassign-profs-status-text assistant)))
                     nil t)))
    (dmassign--field 5)
    (delete-region (point)
                   (progn
                     (when (search-forward ";" (point-at-eol) 'move)
                       (forward-char -1))
                     (point)))
    (insert (dmassign-profs-shortname assistant))))
(defun dmassign-task-at-comment-p ()
  "Non-nil if task at point is a comment."
  (null
   (condition-case nil
       (dmassign-task-at-point)
     (error nil))))
(defun dmassign-task-at-point (&optional noerror) ""
  (save-match-data
    (let ((task (dmassign-line-at-point)))
      (if (string-match dmassign-comment-re task)
          (unless noerror
            (error "No task at point"))
        (when (string-match "^#\\*\\([^#\n]*\\)" task)
          (setq task (match-string 1 task)))
        (dmassign-task-parse task)))))

(defun dmassign-task-find-task (task)
  "Find first task in current buffer which match given TASK. Test
is done with dmassign-tasks-equalp"
  (save-excursion
    (goto-char (point-min))
    (while (and (not (eobp))
                (not
                 (and (not (dmassign-task-at-comment-p))
                      (dmassign-tasks-equalp task (dmassign-task-at-point)))))
      (forward-line))
    (or (dmassign-task-at-point 'noerror)
        (progn
          (dmassign-force-next-update 'all)
          (error "Cannot find task (forcing next command to update): %s" task))))
  ;; (save-excursion 
  ;;   (goto-char (point-min))
  ;;   (let ((i 0))
  ;;     (while (re-search-forward (dmassign-task-no-owner task) nil t)
  ;;       (incf i))
  ;;     (if (eq i 1)
  ;;         (line-number-at-pos)
  ;;       (error "Line not found for task %s (matches: %d)" task i))))
  )
(defun dmassign-line-at-point () ""
  (buffer-substring-no-properties (point-at-bol) (point-at-eol)))
(define-derived-mode dmassign-prof-table-mode
    tabulated-list-mode "Prof"
  "Major mode for browing the table of profs."
  (setq tabulated-list-format [("Name" 15 t)
                               ("Status" 6 t)
                               ("Full name" 30 t)])
  (tabulated-list-init-header))
(defun list-prof-table ()
  (interactive)
  (let ((list  (dmassign-profs-list)))
    (setq list
          (mapcar (lambda (prof)
                    (list nil
                          (vector (dmassign-profs-shortname prof)
                                  (number-to-string (dmassign-profs-status prof))
                                  (dmassign-profs-fullname prof))))
                  list))
    (pop-to-buffer "Liste des profs")
    (setq tabulated-list-entries list))
  (dmassign-prof-table-mode)
  (tabulated-list-print))
(defun dmassign-prof-table ()
  (interactive)
  (pp dmassign-profs-list))
(defun dmassign-prof-add (shortname fullname initials status)
  "Interactively add a new \"prof\" to the profs.txt
  file (assumed to be current buffer) "
  (interactive  (let ((first (read-from-minibuffer "Prénom: "))
                      (last (read-from-minibuffer "Nom de famille: ")))
                  (list (read-from-minibuffer "Shortname: " last)
                        (concat first " " (upcase last))
                        (read-from-minibuffer "Initiales: " 
                                              (concat
                                               (mapcar 'first
                                                       (mapcar 'string-to-list
                                                               (split-string
                                                                (concat first " " last)
                                                                " ")))))
                        (cdr (assoc (completing-read "Statut: " dmassign-prof-status nil t) dmassign-prof-status)))))
  (save-excursion
    (goto-char (point-min))
    (if (re-search-forward (concat "^" (regexp-quote shortname) ";") nil t)
        (user-error "shortname already used: %s" shortname)))
  (save-excursion
    (goto-char (point-min))
    (if (search-forward (concat ";" initials ";") nil t)
        (user-error "initials already used: %s" initials)))
  (save-excursion
    (goto-char (point-min))
    (while (string< (or (word-at-point) "A") shortname)
      (forward-line))
    (insert (format "%s;%s;%s;%s\n" shortname fullname initials status))))

(defmacro dmassign-with-file (file &rest body)
  (declare (indent 1)
           (debug (form body)))
  `(with-temp-buffer
     (insert-file-contents ,file)
     (flush-lines "^ *#\\|^ *$")
     (progn ,@body)))
(defun dmassign-tasks-assigned-to (&optional prof)
  "List of tasks currently assigned to given PROF (at point, interactively)"
  (interactive (list (dmassign-task-get 'owner
                                        (dmassign-task-at-point))))
  (message 
   "Answer: %s"
   (dmassign-with-file dmassign-repartition-f
     (keep-lines (concat ";" (regexp-quote (dmassign-profs-shortname prof)) "$") nil t)
     (buffer-string))))
(defun dmassign-force-next-update (all)
  "Use prefix arg ALL to also reparse the conflicts."
  (interactive "P")
  (when all
    (setq dmassign-conflicts-list nil))
  (setq dmassign-profs-list nil)
  (message "Next update will take %slonger." (if all "much " "")))
(define-derived-mode dmassign-mode prog-mode "Dmassign"
  "Trying to be useful for assigning tasks to people"
  ;; currently only used to have a mode map.
  (setq next-error-function #'dmassign-next-conflict)
  ;(add-hook 'after-save-hook 'dmassign-force-next-update nil 'local)
  (setq comment-start "#"
        comment-end ""))
;; (defun dmassign-next-conflict (arg reset) ""
;;   (dotimes (_ arg)
;;     (when reset)
;;     (re-search-forward
;;      (regexp-quote
;;       (with-current-buffer
;;           (get-buffer-create "*Conflicts*")
;;         (prog1 (dmassign-task-no-owner (dmassign-task-at-point))
;;           (if (bobp) (forward-char) (forward-line)))))
;;      nil t)))
(setq dmassign-mode-map
  (let ((keymap (make-sparse-keymap)))
    (cl-flet
        ((addkey
          (keyseq definition)
          (define-key keymap
            (kbd keyseq)
            definition)))
      (addkey "C-c C-a" 'dmassign-tasks-assigned-to)
      (addkey "C-c C-d" 'dmassign-line-mark-toggle)
      (addkey "C-c C-n" 'dmassign-line-next)
      (addkey "C-c C-p" 'dmassign-line-previous-todo)
      (addkey "C-c C-r" 'dmassign-force-next-update)
      (addkey "C-c C-s" 'dmassign-show-info)
      (addkey "C-c C-q" 'dmassign-find-assistant)
      (addkey "C-c C-t" 'dmassign-show-teacher)
      (addkey "C-c C-c" 'compile)
      (addkey "C-c C-g" 'dmassign-grep-old-repartitions)
      (addkey "C-c C-v" 'dmassign-show-file)
      ;; (addkey "C-S-p" 'dmassign-previous-skip-comment)
      ;; (addkey "C-S-n" 'dmassign-next-skip-comment)
      keymap)))
(defun dmassign-show-file ()
  "" 
  (interactive)
  (require 'gnus-dired)
  (if (file-exists-p "test/all.pdf")
      (gnus-dired-find-file-mailcap "test/all.pdf")))
;; (defun dmassign-next-skip-comment ()
;;   ""
;;   (interactive)
;;   (save-excursion
;;     (forward-line 1)
;;     (when (not (and (re-search-forward dmassign-comment-re nil t) 
;;                     (equal "Exe" (dmassign-task-get 'type (dmassign-task-at-point t)))))
;;       (user-error "No more non-comment line.")))
;;   (goto-char (match-beginning 0)))
;; (defun dmassign-next-skip-comment (arg)
;;   ""
;;   (interactive "p")
;;   (let ((forward (> arg 0))
;;         (arg (abs arg))
;;         (opoint (point)))
;;     (dotimes (_ arg)
;;       (loop do (if (funcall
;;                     (if forward
;;                         #'eobp
;;                       #'bobp))
;;                    (progn (goto-char opoint)
;;                           (user-error "No more non-comment line."))
;;                  (forward-line (if forward 1 -1)))
;;             until (let ((task
;;                          (dmassign-task-at-point t)))
;;                     (when task
;;                       (equal "Exe"
;;                              (dmassign-task-get 'type task))))))))
(defun dmassign-previous-skip-comment (arg)
  ""
  (interactive "p")
  (dmassign-next-skip-comment (- arg)))
(defvar dmassign-comment-re "^ *$\\|^#$\\|^#[^*]")

(defun next-line-and-lookup () "" (interactive)  (forward-line) (call-interactively 'dmassign-lookup-course-in-catalogue))
(defun dmassign-lookup-course-in-catalogue (mnemo insert) ""
  (interactive (list (or (word-at-point) (user-error "No course at point")) t))
  (setq mnemo (replace-regexp-in-string "\\(\\)....$" "-" mnemo nil nil 1))
  (let (result
        (relevantlines (with-temp-buffer
                         (insert-file-contents dmassign-catalogue)
                         (keep-lines (format "^%s" (regexp-quote mnemo)))
                         (pcsv-parse-buffer))))
    (save-excursion
      (forward-line)
      (setq result
            (mapconcat
             (lambda (line)
               (format "#@# %s (ECTS %s) %s %s\n"
                       (nth 0 line)
                       (nth 4 line)
                       (mapconcat
                        (lambda (n)
                          (let ((weight (string-to-number
                                         (if (string= (nth n line) "")
                                             "0"
                                           (nth n line)))))
                            (format "%s"
                                    (/ weight
                                       (if (eq (% weight 12) 0) 12 12.0)))))
                        '(5 7 6 8 9 10 11)
                        "/")
                       (last line)))
             relevantlines
             ""))
      (funcall
       (if (and insert (not (looking-at (regexp-quote result))))
           #'insert
         #'message)
       result))))
(defvar dmassign-catalogue "2013-2014/cours sciences.csv")
;; (defun dmassign-line-todo-p ()
;;   "Non-nil if line is a todo item. match-data is set such that
;; the group \\1 contains the actual task (without TODO markers)"
;;   (save-excursion
;;     (beginning-of-line)
;;     (looking-at "\\(?:#\\*\\)\\(.*\\)$")))
(defun dmassign-line-remove-comment ()
  (and (dmassign-line-comment-p) (replace-match "")))
(defun dmassign-line-comment-p () ""
  (save-excursion
    (beginning-of-line)
    (prog1
        (or
         (and (bolp) (eolp))
         (search-forward "#" (point-at-eol) 'noerror))
      (backward-char)
      (skip-chars-backward " ")
      (looking-at ".*"))))

(defun dmassign--field (n)
  (beginning-of-line)
  (search-forward ";" (point-at-eol) nil (1- n)))

(defun dmassign-line-mark-done ()
  "Mark current task as \"attribué\" (i.e. remove XTP-)"
  (interactive)
  (save-excursion
    (if (dmassign-line-comment-p)
        (user-error "Line has a comment. Remove it.")
      (dmassign--field 5)
      (when (looking-at "XTP-")
        (replace-match "")))))

(defun dmassign-line-mark-todo ()
  "Mark current task as \"non-attribué\" (i.e. add XTP)"
  (interactive)
  (if (dmassign-line-comment-p)
      (user-error "Line has a comment. Remove it.")
    (save-excursion
      (dmassign--field 5)
      (unless (looking-at "XTP")
        (insert "XTP-")))))
(defun dmassign-line-mark-toggle ()
  ""
  (interactive)
  (funcall
   (if (dmassign-line-todo-p)
       #'dmassign-line-mark-done
     #'dmassign-line-mark-todo)))
(defun dmassign-line-todo-p ()
  ""
  (save-excursion
    (beginning-of-line)
    (and
     (ignore-errors 
       (dmassign--field 5)
       t)
     (looking-at-p "XTP"))))

(defun dmassign-line-previous-todo () ""
  (interactive)
  (forward-line -1)
  (while (and (not (bobp)) (not (dmassign-line-todo-p)))
    (forward-line -1)))
(defun dmassign-line-next (todo)
  "Forward to next EXE. With prefix arg, only consider TODO items."
  (interactive "P")
  (let ((opos (point)))
    (forward-line)
    (while (and (not (eobp))
                (or (dmassign-line-comment-p)
                    (not (looking-at-p "Exe"))
                    (and
                     todo
                     (not (dmassign-line-todo-p)))))
      (forward-line))
    (when (eobp)
      (goto-char opos)
      (user-error "No more tasks."))))

(defun dmassign-show-info () ""
  (interactive)
  (let* ((task
          (dmassign-task-at-point))
         (conflicts
          (dmassign-show-conflicts task))
         (owner-shortname
          (dmassign-task-get 'owner-shortname task))
         (owner-info
          (if (equal "" owner-shortname)
              "No prof"
            (format "%s (%s): %s eq-th"
                    owner-shortname
                    (dmassign-profs-status-text
                     (dmassign-profs-via-shortname owner-shortname))
                    (dmassign-profs-charge
                     (dmassign-profs-via-shortname owner-shortname))))))
    (display-buffer
     (with-current-buffer (get-buffer-create "*Conflicts*")
       (erase-buffer)
       (insert (format "Charge pour %s\n\n" owner-info))
       (save-excursion
         (insert conflicts))
       (current-buffer)))
    (when (eq dmassign-force-update-data 'next)
      (setq dmassign-force-update-data nil))))

(defun dmassign-show-teacher (teacher) ""
  (interactive (list (dmassign-task-get 'owner-shortname (dmassign-task-at-point))))
  (occur (concat "\\b" teacher "\\b")))

(defun dmassign-yf/request-a-list (collection &optional prompt function)
  (setq prompt (or prompt "Add element to list %s: "))
  (accumulate-body
   (let ((elt (ido-completing-read-with-printfun 
               (format prompt (or
                               (mapcar (or function #'prin1-to-string) (reverse accumulate-body))
                               "[none yet]"))
               collection
               function)))
     (setq collection (delq elt collection))
     elt)))
(defun dmassign-make-re-that-match (status)
  "Make a regexp that matches teachers that do NOT have the given STATUS"
  (interactive (list (mapcar #'cdr (dmassign-yf/request-a-list dmassign-prof-status nil #'car))))
  (mapconcat
   (lambda (x)
     (concat "\\b"
             (regexp-quote (dmassign-profs-shortname x))
             "\\b"))
   (-select
    (lambda (prof)
      (not (memq (dmassign-profs-status prof) status)))
    (dmassign-profs-list))
   "\\|"))

(defun dmassign-totaux-dheures ()
  (let ((ex 0) (tp 0) (curbuf (current-buffer)))
    (mapc
     (lambda (x)
       (when (not (equal "" x)) 
         (let
             ((x
               (mapcar #'string-to-number (split-string x "/"))))
           (incf ex
                 (nth 1 x))
           (incf tp
                 (nth 2 x)))))
     (split-string
      (let ((buf (generate-new-buffer " *temp*")))
        (with-current-buffer curbuf
          (shell-command-on-region
           (point-min)
           (point-max)
           "cut -d\\; -f 4" buf))
        (prog1
            (with-current-buffer buf
              (buffer-string))
          (kill-buffer buf)))
      "\n"))
    (format "Ex: %s\nTp: %s" ex tp)))

;; (insert (mapconcat (lambda (x) (format "%s %s" (dmassign-profs-shortname x) (dmassign-profs-status x))) (sort-according-to #'dmassign-profs-status (dmassign-assistants-list) 'numeric) "\n"))

;; (dmassign-find-assistant)

(defun yf/compare-lists (list1 list2)
  "LIST1 should be what was asked for, LIST2 what was received"
  (let ((l12 (cl-set-difference list1 list2 :test #'equal))
        (l21 (cl-set-difference list2 list1 :test #'equal)))
    (insert (format "Asked, not got: %s\n\nGot, not asked: %s" l12 l21))))
(defun dmassign-remove-comments ()
  (interactive
   (when buffer-file-name
     (user-error "Has a filename, not acting.")))
  (save-excursion
    (goto-char (point-min))
    (flush-lines "^\\(#\\|\\( *$\\)\\)")))
(defun dmassign-buffer-as-pcsv (buffer)
  (with-temp-buffer
    (insert-buffer-substring buffer)
    (goto-char (point-min))
    (dmassign-remove-comments)
    (let ((pcsv-separator ?\;))
      (pcsv-parse-fuffer))))
(defun dmassign-make ()
  (interactive)
  (let* ((dir (locate-dominating-file default-directory "Makefile"))
         (compile-command
          (concat
           "make OPTIONS=\"-3456789\" PROGRAMDIR="
           dir
           " -f "
           dir "/Makefile")))
    (compile compile-command)))

(defun dmassign-grep-old-repartitions (what)
  "Retrouve les enseignements liés à WHAT.

WHAT est un shortname ou un mnémonique.

On suppose être dans le répertoire xxxx-((xxxx+1)) et que les
autres soient des frères de celui-ci."
  (interactive
   (list (completing-read "Grep what (shortname/mnemonic)? "
                          (let ((task (dmassign-task-at-point)))
                            (list (dmassign-task-get 'mnemonicnoquadri task)
                                  (dmassign-profs-shortname
                                   (dmassign-task-get 'owner task)))))))
  (let ((path (expand-file-name ".."))
        (buf (get-buffer-create (format "dmassign: Enseignements pour %s" what))))
    (with-current-buffer buf
      (erase-buffer)
      (when (not (= 0
                    (call-process "find"
                                  nil (get-buffer-create buf) nil
                                  path
                                  "-maxdepth" "2"
                                  "-name" "repartition.txt"
                                  "-exec" "egrep" "-H" (format "^[^#].*\\b%s\\b" what) "{}" ";")
                    ))
        (warn "Could not run ‘find’."))
      (goto-char (point-min))
      (while (re-search-forward "^.*?/\\([0-9]\\{4\\}-[0-9]\\{4\\}\\)/repartition\\.txt:" nil t)
        (replace-match (format "%s:"(match-string 1)))))
    (display-buffer buf)))

(provide 'dmassign)

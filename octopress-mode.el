;;; octopress-mode.el --- A lightweight wrapper for Jekyll and Octopress.

;; Copyright (C) 2015 Aaron Bieber

;; Author: Aaron Bieber <aaron@aaronbieber.com>
;; Version: 1.0
;; Package-Requires ((cl-lib "0.5"))
;; Keywords: octopress, blog, mode
;; URL: https://github.com/aaronbieber/octopress-mode

;;; Commentary:

;; This package provides a lightweight but fluent wrapper around the
;; Octopress 3.0 suite of commands used to generate and manage a blog
;; site. For help using this package, see its README or website as
;; noted in the header above.

;;; Code:

(require 'cl-lib)

(defface om-option-on-face
  '((t (:foreground "#50A652")))
  "An Octopress interactive option when on."
  :group 'octopress-mode)

(defface om-option-off-face
  '((t (:foreground "#CF4C4C")))
  "An Octopress interactive option when off."
  :group 'octopress-mode)

(defface om-highlight-line-face
  '((t (:background "#323878")))
  "Face used to highlight the active line."
  :group 'octopress-mode)

(defvar om-highlight-current-line-overlay
  ;; Dummy initialization
  (make-overlay 1 1)
  "Overlay for highlighting the current line.")

(overlay-put om-highlight-current-line-overlay
	     'face 'om-highlight-line-face)

(defvar octopress-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "?" 'om-toggle-command-window)
    (define-key map "q" 'om-status-quit)
    (define-key map "s" 'om-start-stop-server)
    (define-key map "g" 'om-refresh-status)
    (define-key map "c" 'om-create-thing)
    (define-key map "d" 'om-deploy)
    (define-key map "b" 'om-build)
    (define-key map "$" 'om-show-server)
    (define-key map "!" 'om-show-process)
    (define-key map "n" 'om--move-to-next-thing)
    (define-key map "p" 'om--move-to-previous-thing)
    (define-key map "P" 'om-publish-unpublish)
    (define-key map (kbd "C-n") 'om--move-to-next-heading)
    (define-key map (kbd "C-p") 'om--move-to-previous-heading)
    (define-key map (kbd "<tab>") 'om--maybe-toggle-visibility)
    (define-key map (kbd "<return>") 'om--open-at-point)
    map)
  "Get the keymap for the Octopress status buffer.")

(defvar octopress-server-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "q" 'om-server-quit)
    map)
  "Get the keymap for the Octopress server buffer.")

(defvar octopress-process-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "q" 'om-process-quit)
    map)
  "Get the keymap for the Octopress process buffer.")

;;; Customization
(defcustom octopress-posts-directory
  "_posts"
  "Directory containing posts, relative to /path/to/jekyll-site/"
  :type 'string
  :group 'octopress-mode)

(defcustom octopress-drafts-directory
  "_drafts"
  "Directory containing drafts, relative to /path/to/jekyll-site/"
  :type 'string
  :group 'octopress-mode)

(defcustom octopress-default-build-flags
  '()
  "The default flags to pass to `jekyll build'. Each option is a type of post
that is normally excluded from a Jekyll build. The checked options will be
enabled by default in the interactive prompt."
  :type    '(set (const :tag "Drafts" drafts)
                 (const :tag "Posts with future dates" future)
                 (const :tag "Unpublished posts" unpublished))
  :group   'octopress-mode)

(defcustom octopress-default-server-flags
  '(drafts unpublished)
  "The default flags to pass to `jekyll serve'. Each option is a type of post
that is normally ignored by the Jekyll server. The checked options will be
enabled by default in the interactive prompt to start the server."
  :type    '(set (const :tag "Drafts" drafts)
                 (const :tag "Posts with future dates" future)
                 (const :tag "Unpublished posts" unpublished))
  :group   'octopress-mode)

;;; "Public" functions

;;;###autoload
(defun om-status ()
  "The main entry point into octopress-mode."
  (interactive)
  (let ((om-buffer (om--setup)))
    (if om-buffer
        (progn (om--draw-status om-buffer)
               (pop-to-buffer om-buffer)))))

(defun om-refresh-status ()
  (interactive)
  (om-toggle-command-window t)
  (om--maybe-redraw-status))

(defun om-start-stop-server ()
  (interactive)
  (let* ((config (om--read-char-with-toggles
                  "[s] Server, [k] Kill, [q] Abort"
                  '(?s ?k ?q)
                  octopress-default-server-flags))
         (choice (cdr (assoc 'choice config)))
         (drafts (cdr (assoc 'drafts config)))
         (future (cdr (assoc 'future config)))
         (unpublished (cdr (assoc 'unpublished config))))
    (if choice
        (cond ((eq choice ?s)
               (om-toggle-command-window t)
               (om--start-server-process drafts future unpublished))
              ((eq choice ?k)
               (progn (om-toggle-command-window t)
                      (message "Stopping server...")
                      (om--stop-server-process)))))))

(defun om-restart-server ()
  (interactive))

(defun om-show-server ()
  (interactive)
  (om-toggle-command-window t)
  (pop-to-buffer (om--prepare-server-buffer)))

(defun om-show-process ()
  (interactive)
  (om-toggle-command-window t)
  (pop-to-buffer (om--prepare-process-buffer)))

(defun om-create-thing ()
  "Present a menu through which the user may create a new thing."
  (interactive)
  (let ((choice (read-char-choice
                 "[p] Post, [d] Draft, [g] Page, [q] Abort"
                 '(?p ?d ?g ?q))))
    (cond ((eq choice ?p)
           (om--new-post))
          ((eq choice ?d)
           (om--new-draft))
          ((eq choice ?g)
           (om--new-page))
          ((eq choice ?q)
           (message "Aborted.")))))

(defun om-deploy ()
  (interactive)
  (when (yes-or-no-p "Really deploy your site? ")
    (progn
      (om-toggle-command-window t)
      (om--start-deploy-process))))

(defun om-build ()
  (interactive)
  (let* ((config (om--read-char-with-toggles
                  "[b] Build, [q] Abort"
                  '(?b ?q)
                  octopress-default-build-flags))
         (choice (cdr (assoc 'choice config)))
         (drafts (cdr (assoc 'drafts config)))
         (future (cdr (assoc 'future config)))
         (unpublished (cdr (assoc 'unpublished config))))
    (when (eq choice ?b)
      (progn
        (om-toggle-command-window t)
        (om--start-build-process drafts future unpublished)))))

(defun om-status-quit ()
  "Quit the Octopress Mode window, preserving its buffer."
  (interactive)
  (om-toggle-command-window t)
  (quit-window))

(defun om-server-quit ()
  "Quit the Octopress Server Mode window, preserving its buffer."
  (interactive)
  (quit-window))

(defun om-process-quit ()
  "Quit the Octopress Process Mode window, preserving its buffer."
  (interactive)
  (quit-window))

(defun om-publish-unpublish ()
  (interactive)
  (let* ((thing (om--file-near-point))
         (thing-type (car thing))
         (filename (cdr thing)))
    (if (memq thing-type '(drafts posts))
        (om--publish-unpublish thing-type filename)
      (message "There is no post nor draft on this line."))))

(defun om-insert-post-url ()
  "Prompt for a post and insert a Jekyll URL tag at point.

Assuming that authors typically want to link to newer posts, the
directory list will be sorted in reverse alphabetical order. Provided
that the files are named using the YYYY-MM-DD prefix format, this will
result in newer posts appearing first in the list."
  (interactive)
  (let* ((post-dir (expand-file-name octopress-posts-directory (om--get-root)))
         (posts (sort (directory-files post-dir nil nil t)
                      #'(lambda (s1 s2) (string-lessp s2 s1))))
         (post (file-name-base (completing-read
                                "Link to: "
                                posts
                                '(lambda (f) (and (not (string= f "."))
                                                  (not (string= f ".."))))))))
    (insert (concat "{% post_url " post " %}"))))

(defun om--publish-unpublish (type filename)
  (let ((source-path (cond ((eq type 'posts)
                            (expand-file-name octopress-posts-directory (om--get-root)))
                           ((eq type 'drafts)
                            (expand-file-name octopress-drafts-directory (om--get-root)))))
        (subcommand (cond ((eq type 'posts)
                           "unpublish")
                          ((eq type 'drafts)
                           "publish"))))
    (if (file-exists-p (expand-file-name filename source-path))
        (if (or (eq type 'drafts)
                (yes-or-no-p "Really unpublish this post? "))
            (progn (om-toggle-command-window t)
                   (om--run-octopress-command (concat "octopress " subcommand " " filename))))
      (message "The file `%s' doesn't exist in `%s'. Try refreshing?" filename octopress-posts-directory))))

(defun om-toggle-command-window (&optional hide)
  "Toggle the display of a helpful command window.

If the optional HIDE argument is not nil, hide the command window if
it exists and do nothing otherwise."
  (interactive)
  (let* ((buffer-name (om--buffer-name-for-type "command"))
         (command-buffer (get-buffer-create buffer-name))
         (command-window (get-buffer-window command-buffer)))
    (if command-window
        (delete-window command-window)
      (if (not hide)
          (progn
            (om--draw-command-help command-buffer)
            (split-window-below)
            (set-window-buffer (next-window) command-buffer)
            (fit-window-to-buffer (next-window)))))))

;;; "Private" functions
(defun om--setup ()
  "Stuff that has to happen before anything else can happen."
  ;; Only set up if we have to...
  (let ((om-buffer (get-buffer (om--buffer-name-for-type "status"))))
    (if (om--buffer-is-configured om-buffer)
        om-buffer
      (setq om-root (om--get-root))
      (let* ((om-buffer (om--prepare-status-buffer)))
        (if (and om-buffer om-root)
            (progn (with-current-buffer om-buffer
                     (make-local-variable 'om-root))
                om-buffer)
          (progn (kill-buffer om-buffer)
                 nil))))))

(defun om--draw-command-help (buffer)
  (with-current-buffer buffer
    (setq buffer-read-only t)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert
       (om--legend-item "C-n" "Next section" 18)
       (om--legend-item "C-p" "Prev section" 18)
       (om--legend-item "n" "Next thing" 18)
       (om--legend-item "p" "Prev thing" 18) "\n"
       (om--legend-item "TAB" "Toggle thing" 18)
       (om--legend-item "RET" "Open thing" 18) "\n\n"
       (om--legend-item "c" "Create" 18)
       (om--legend-item "s" "Server" 18)
       (om--legend-item "b" "Build" 18)
       (om--legend-item "P" "[Un]publish" 18) "\n"
       (om--legend-item "d" "Deploy" 18)
       (om--legend-item "g" "Refresh" 18)
       (om--legend-item "!" "Show Process" 18)
       (om--legend-item "$" "Show Server" 18) "\n"
       (om--legend-item "q" "Quit" 18))
      (goto-char (point-min)))))

(defun om--thing-on-this-line ()
  "Determine whether there is a thing on this line."
  (get-text-property (line-beginning-position) 'thing))

(defun om--file-near-point ()
  "Return the filename on the current line (of *om-status*).

Return a single cons cell where the car of the cons is the `thing
type', e.g. 'drafts or 'posts, and the cdr of the cons is the filename.

If the current line of the current buffer does not have a valid thing type, this
function returns nil."
    (let* ((thing-type (get-text-property (line-beginning-position) 'invisible))
           (line (buffer-substring (line-beginning-position) (line-end-position)))
           (found (string-match "^\s*\\([^ ]*\\)" line))
           (filename (match-string 1 line)))
      (if (and thing-type found filename)
          (cons thing-type (om--strip-text-properties filename))
        nil)))

(defun om--read-char-with-toggles (prompt-suffix choices &optional default-to-on)
  "Read a selection from a menu with toggles.

Display a fixed menu of toggles followed by PROMPT-SUFFIX. Accept any of
the default choices (d, f, u, q) as well as the supplied CHOICES, which
should be provided as a list of characters (not strings).

If any of the symbols `drafts', `future', or `unpublished' are present in
the DEFAULT-TO-ON list, those toggles will be turned on initially.

This function returns the char value from CHOICES selected by the user."
  (let ((choices (append choices '(?d ?f ?u ?q)))
        (drafts (memq 'drafts default-to-on))
        (future (memq 'future default-to-on))
        (unpublished (memq 'unpublished default-to-on))
        return done)
    (while (not done)
      (let* ((prompt (concat (propertize "(" 'face 'default)
                             (propertize "[d]rafts " 'face (if drafts 'om-option-on-face 'om-option-off-face))
                             (propertize "[f]uture " 'face (if future 'om-option-on-face 'om-option-off-face))
                             (propertize "[u]npublished" 'face (if unpublished 'om-option-on-face 'om-option-off-face))
                             ") " prompt-suffix))
             (choice (read-char-choice prompt choices)))
        (cond ((eq choice ?d)
               (setq drafts (not drafts)
                     done nil))
              ((eq choice ?f)
               (setq future (not future)
                     done nil))
              ((eq choice ?u)
               (setq unpublished (not unpublished)
                     done nil))
              ((eq choice ?q)
               (setq done t)
               (message "Aborted."))
              (t (setq return `((choice . ,choice)
                                (drafts . ,drafts)
                                (future . ,future)
                                (unpublished . ,unpublished))
                       done t)))))
  return))

(defun om--get-line-type ()
  (save-excursion
    (beginning-of-line)
    (get-text-property (point) 'invisible)))

(defun om--get-line-filename ()
  (save-excursion
    (back-to-indentation)
    (thing-at-point 'filename)))

(defun om--expand-path-for-type (filename type)
  (let ((type-dir (cdr (assoc type `((posts . ,octopress-posts-directory)
                                     (drafts . ,octopress-drafts-directory))))))
    (and filename
         type-dir
         (expand-file-name
          filename (expand-file-name
                    type-dir (om--get-root))))))

(defun om--open-at-point ()
  "Open the file at point, if there is one."
  (interactive)
  (let* ((type (om--get-line-type))
         (filename (om--get-line-filename))
         (full-filename (om--expand-path-for-type filename type)))
    (if (file-exists-p full-filename)
        (pop-to-buffer (find-file full-filename)))))

(defun om--new-post ()
  (om-toggle-command-window t)
  (let ((name (read-string "Post name: ")))
    (om--run-octopress-command (concat "octopress new post \"" name "\""))))

(defun om--new-draft ()
  (om-toggle-command-window t)
  (let ((name (read-string "Draft name: ")))
    (om--run-octopress-command (concat "octopress new draft \"" name "\""))))

(defun om--new-page ()
  (om-toggle-command-window t)
  (let ((name (read-string "Page name: ")))
    (om--run-octopress-command (concat "octopress new page \"" name "\""))))

(defun om--buffer-is-configured (buffer)
  "Return t if BUFFER is configured properly for Octopress Mode."
  (and (bufferp buffer)
       (let ((vars (buffer-local-variables
                    (get-buffer buffer))))
         (and (assoc 'om-root vars)
              (string= (cdr (assoc 'major-mode vars)) "octopress-mode")))))

(defun om--start-deploy-process ()
  (om--setup)
  (let* ((root (om--get-root))
         (command "octopress deploy"))
    (om--run-octopress-command (concat "cd " root " && " command))))

(defun om--start-build-process (&optional with-drafts with-future with-unpublished)
  (om--setup)
  (let* ((process-buffer (om--prepare-process-buffer))
         (drafts-opt (if with-drafts " --drafts" nil))
         (future-opt (if with-future " --future" nil))
         (unpublished-opt (if with-unpublished " --unpublished" nil))
         (root (om--get-root))
         (command (concat "jekyll build" drafts-opt future-opt unpublished-opt)))
    (om--run-octopress-command (concat "cd " root " && " command))))

(defun om--start-server-process (&optional with-drafts with-future with-unpublished)
  (om--setup)
  (let* ((buffer (om--prepare-server-buffer))
         (drafts-opt (if with-drafts " --drafts" nil))
         (future-opt (if with-future " --future" nil))
         (unpublished-opt (if with-unpublished " --unpublished" nil))
         (command (concat "jekyll serve" drafts-opt future-opt unpublished-opt)))
    (if (processp (get-buffer-process (om--buffer-name-for-type "server")))
        (message "Server already running!")
      (with-current-buffer buffer
        (let ((inhibit-read-only t))
          (goto-char (point-max))
          (insert (propertize (format "Running `%s'...\n\n" command) 'face 'font-lock-variable-name-face))))
      (let ((process
            (start-process-shell-command
             "octopress-server"
             buffer
             (concat "cd " (om--get-root) " && " command))))
      (message "Server started!")
      (set-process-sentinel process 'om--server-sentinel)
      (set-process-filter process 'om--generic-process-filter))
      (om--maybe-redraw-status))))

(defun om--stop-server-process ()
  (let ((server-process (get-buffer-process (om--buffer-name-for-type "server"))))
    (if (processp server-process)
        (process-send-string server-process (kbd "C-c")))))

(defun om--buffer-name-for-type (type)
  "Return a buffer name for the provided type."
  (concat "*om-" type "*"))

(defun om--server-sentinel (process event)
  (om--maybe-redraw-status)
  (let ((program (process-name process))
        (event (replace-regexp-in-string "\n$" "" event)))
    (cond ((string-prefix-p "finished" event)
           (progn (message "Jekyll server has finished.")
                  (with-current-buffer (om--prepare-server-buffer)
                    (goto-char (process-mark process))
                    (let ((inhibit-read-only t))
                      (insert (propertize "\nJekyll server has finished.\n\n" 'face 'font-lock-warning-face))
                      (goto-char (point-max)))))))))

(defun om--server-status ()
  (let ((server-process (get-buffer-process (om--buffer-name-for-type "server"))))
    (and (processp server-process)
         (string= (process-status server-process) "run"))))

(defun om--server-status-string ()
  (if (om--server-status)
      "Running"
    "Stopped"))

(defun om--prepare-buffer-for-type (type &optional mode-function)
  "Prepare an empty buffer for TYPE and optionally run MODE-FUNCTION."
  (let ((buffer-name (om--buffer-name-for-type type)))
    (if (bufferp buffer-name)
        (get-buffer buffer-name)
      (let ((buf (get-buffer-create buffer-name)))
        (with-current-buffer buf
          (setq buffer-read-only t)
          (kill-all-local-variables)
          (if (functionp mode-function)
              (funcall mode-function)))
        buf))))

(defun om--prepare-status-buffer ()
  "Return the Octopress Mode (\"status\") buffer.

If the buffer doesn't exist yet, it will be created and prepared."
  (let ((buffer-name (om--buffer-name-for-type "status")))
    (if (get-buffer buffer-name)
        (get-buffer buffer-name)
      (let ((status-buffer (om--prepare-buffer-for-type "status" 'octopress-mode)))
        (with-current-buffer status-buffer
          (add-to-invisibility-spec 'posts))
        status-buffer))))

(defun om--prepare-server-buffer ()
  "Return the Octopress Server Mode buffer.

If the buffer doesn't exist yet, it will be created and prepared."
  (om--prepare-buffer-for-type "server" 'octopress-server-mode))

(defun om--prepare-process-buffer ()
  "Return the Octopress Process Mode buffer.

If the buffer doesn't exist yet, it will be created and prepared."
  (om--prepare-buffer-for-type "process" 'octopress-process-mode))

(defun om--get-root ()
  "Attempt to find the root of the Octopress site.

We assume we are running from a buffer editing a file somewhere within the site.
If we are running from some other kind of buffer, or a buffer with no file, the
user will be prompted to enter the path to an Octopress site."
  (let ((status-buffer (get-buffer (om--buffer-name-for-type "status")))
        (this-dir (if (and (boundp 'dired-directory) dired-directory)
                      dired-directory
                    (if (buffer-file-name (current-buffer))
                        (file-name-directory (buffer-file-name (current-buffer)))))))
    (if (and (bufferp status-buffer)
             (assoc 'om-root (buffer-local-variables status-buffer))
             (buffer-local-value 'om-root status-buffer))
        (buffer-local-value 'om-root status-buffer)
      (or (and this-dir
               (let ((candidate-dir (vc-find-root this-dir "_config.yml")))
                 (if candidate-dir (expand-file-name candidate-dir) nil)))
          (let ((candidate-dir (read-directory-name "Octopress site root: ")))
            (if (file-exists-p (expand-file-name "_config.yml" candidate-dir))
                (expand-file-name candidate-dir)
              (prog2 (message "Could not find _config.yml in `%s'." candidate-dir)
                  nil)))))))

(defun om--maybe-redraw-status ()
  "If the status buffer exists, redraw it with current information."
  (let ((status-buffer (get-buffer (om--buffer-name-for-type "status"))))
    (if (bufferp status-buffer)
        (om--draw-status status-buffer))))

(defun om--get-status-data ()
  (om--setup)
  "Return the status of the Octopress site linked to BUFFER.

This function can only be called after `om-status' has been run and must be
passed the resulting BUFFER."
  (with-current-buffer buffer
    `((posts-count . ,(number-to-string
                       (length
                        (directory-files
                         (expand-file-name octopress-posts-directory (om--get-root))
                         nil
                         "*.md$\\|.*markdown$"))))
      (drafts-count . ,(number-to-string
                        (length
                         (directory-files
                          (expand-file-name octopress-drafts-directory (om--get-root))
                          nil
                          ".*md$\\|.*markdown$"))))
      (server-status . ,(om--server-status-string)))))

(defun om--move-to-next-thing ()
  "Move point to the next item with property 'thing."
  (interactive)
  (om--move-to-next-visible-thing))

(defun om--move-to-next-heading ()
  "Move point to the next item with property 'heading."
  (interactive)
  (om--move-to-next-prop 'heading))

(defun om--move-to-next-visible-thing (&optional reverse)
  "Move point to the next item with property 'thing that is visible.

If REVERSE is not nil, move to the previous visible 'thing."
  (goto-char (or (let ((start (point)))
                   (if reverse
                       (beginning-of-line)
                     (end-of-line))
                   (let* (destination)
                     (while (not destination)
                       (let ((next-candidate (if reverse
                                                 (previous-single-property-change (point) 'thing)
                                               (next-single-property-change (point) 'thing))))
                         (if next-candidate
                             (if (memq (get-text-property next-candidate 'invisible)
                                       buffer-invisibility-spec)
                                 (goto-char next-candidate)
                               (setq destination next-candidate))
                           (setq destination start))))
                     destination))
                 (point)))
  (beginning-of-line))

(defun om--move-to-next-prop (prop-name)
  "Move to the next item with property PROP-NAME."
  (goto-char
   (or (save-excursion
         (goto-char (line-end-position))
         (let ((thing (next-single-property-change (point) prop-name)))
           (if thing
               (let ((type (get-text-property thing 'invisible)))
                 (if (and type (memq type buffer-invisibility-spec))
                     (remove-from-invisibility-spec type))
                 thing))))
       (point))))

(defun om--move-to-previous-thing ()
  "Move to the previous item with property 'thing."
  (interactive)
  (om--move-to-next-visible-thing t))

(defun om--move-to-previous-heading ()
  "Move to the previous item with property 'heading."
  (interactive)
  (om--move-to-previous-prop 'heading))

(defun om--move-to-previous-prop (prop-name)
  "Move to the previous item with property PROP-NAME."
  (goto-char
   (or (save-excursion
         (goto-char (line-beginning-position))
         (let ((thing (previous-single-property-change (point) prop-name)))
           (if thing
               (let ((type (get-text-property thing 'invisible)))
                 (if (or (not type)
                         (not (memq type buffer-invisibility-spec)))
                     thing
                   nil)))))
       (point)))
  (goto-char (line-beginning-position)))

(defun om--maybe-toggle-visibility ()
  (interactive)
  (let ((hidden (get-text-property (line-beginning-position) 'hidden)))
    (if hidden
        (if (memq hidden buffer-invisibility-spec)
            (remove-from-invisibility-spec hidden)
          (add-to-invisibility-spec hidden))))
  (force-window-update (current-buffer)))

(defun om--draw-status (buffer)
  "Draw a display of STATUS in BUFFER.

STATUS is an alist of status names and their printable values."
  (let ((status (om--get-status-data)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t)
            (window (get-buffer-window))
            (pos (point)))
        (erase-buffer)
        (insert
         (propertize "Octopress Status\n" 'face '(:inherit font-lock-constant-face :height 160))
         "\n"
         (propertize " " 'thing t 'heading t)
         (propertize "   Blog root: " 'face 'font-lock-function-name-face)
         om-root "\n"

         (propertize " " 'thing t 'heading t)
         (propertize "      Server: " 'face 'font-lock-function-name-face)
         (cdr (assoc 'server-status status)) "\n"

         (propertize " " 'thing t 'hidden 'drafts 'heading t)
         (propertize "      Drafts: " 'face 'font-lock-function-name-face)
         (cdr (assoc 'drafts-count status)) "\n"
         (om--get-display-list (om--get-drafts) 'drafts)

         (propertize " " 'thing t 'hidden 'posts 'heading t)
         (propertize "       Posts: " 'face 'font-lock-function-name-face)
         (cdr (assoc 'posts-count status)) "\n"
         (om--get-display-list (om--get-posts) 'posts)

         "\n"
         "Press `?' for help.")
        (goto-char (if (< pos (point-max))
                       pos
                     (point-min)))
        (if window
            (force-window-update window))))))

(defun om--get-display-list (things visibility-name)
  (let ((thing-list ""))
    (cl-loop for thing in things do
             (setq thing-list
                   (concat thing-list
                           (propertize " " 'thing t)
                           (make-string 10 ? ) thing "\n")))
    (propertize thing-list 'invisible visibility-name)))

(defun om--legend-item (key label column-width)
  (let ((pad (- column-width (+ (length key) (length label) 2))))
    (concat
     (propertize key 'face 'font-lock-keyword-face) ": "
     label
     (make-string pad ? ))))

(defun om--get-articles-in-dir-by-date-desc (dir)
  "Get files in the blog subdir DIR in descending order by date."
  (mapcar #'car
          (sort (directory-files-and-attributes
                 (expand-file-name dir om-root)
                 nil
                 "*.md$\\|.*markdown$")
                #'(lambda (f1 f2) (time-less-p (nth 6 f2) (nth 6 f1))))))

(defun om--get-posts ()
  (om--setup)
  (om--get-articles-in-dir-by-date-desc octopress-posts-directory))

(defun om--get-drafts ()
  (om--setup)
  (om--get-articles-in-dir-by-date-desc octopress-drafts-directory))

(defun om--run-octopress-command (command)
  "Run an Octopress command, sending output to the process buffer.

Returns the process object."
  (om--setup)
  (let ((pbuffer (om--prepare-process-buffer))
        (root (om--get-root))
        (command (replace-regexp-in-string "'" "\\\\'" command)))
    (with-current-buffer pbuffer
      (let ((inhibit-read-only t))
        (goto-char (point-max))
        (message (concat "Running Octopress..."))
        (insert (propertize (concat "Running `" command "'...\n\n") 'face 'font-lock-variable-name-face))))
    (let ((process (start-process-shell-command
                    "octopress"
                    pbuffer
                    (concat "cd " root " && " command))))
      (set-process-sentinel process 'om--octopress-sentinel)
      (set-process-filter process 'om--generic-process-filter)
      process)))

(defun om--octopress-sentinel (process event)
  (let ((program (process-name process))
        (event (replace-regexp-in-string "\n$" "" event))
        (buffer (get-buffer (om--buffer-name-for-type "process"))))
    (cond ((string-prefix-p "finished" event)
           (progn (om--handle-octopress-output buffer)
                  (with-current-buffer buffer
                    (let ((inhibit-read-only t))
                      (insert (concat (propertize (make-string 80 ?-) 'face 'font-lock-comment-face) "\n\n"))
                      (set-marker (process-mark process) (point))))
                  (message "Octopress has completed.")
                  (om--maybe-redraw-status)))
          ((string-prefix-p "exited" event)
           (message "Octopress exited abnormally; check the process output for information.")
           (om--handle-octopress-output buffer)))))

(defun om--generic-process-filter (proc string)
  (when (buffer-live-p (process-buffer proc))
    (with-current-buffer (process-buffer proc)
      (let ((moving (= (point) (process-mark proc)))
            (window (get-buffer-window))
            (inhibit-read-only t))
        (save-excursion
          ;; Insert the text, advancing the process marker.
          (goto-char (process-mark proc))
          (insert string)
          (set-marker (process-mark proc) (point)))
        (when moving
          (goto-char (process-mark proc))
          (if window
              (with-selected-window window
                (goto-char (process-mark proc)))))))))

(defun om--handle-octopress-output (buffer)
  "Attempt to do something reasonable based on what Octopress said.

This is 'cheater mode' for not having callbacks in elisp and to avoid creating
different output buffers for different operations to figure out what to do with
each kind of output."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-max))
      (re-search-backward "^[A-Z]" (point-min) t)
      (let ((output (buffer-substring (line-beginning-position) (line-end-position))))
        (cond ((or (string-prefix-p "New post:" output)
                   (string-prefix-p "New draft:" output)
                   (string-prefix-p "New page:" output))
               (let* ((filename (om--find-filename-in-output output)))
                 (if (file-exists-p filename)
                     (find-file filename))))
               ((string-prefix-p "Published:" output)
                (let ((draft (om--find-filename-in-output output "_drafts"))
                      (post (om--find-filename-in-output output "_posts")))
                  (if (and draft post)
                      (om--swap-window-files draft post))))
               ((string-prefix-p "Unpublished:" output)
                (let ((draft (om--find-filename-in-output output "_drafts"))
                      (post (om--find-filename-in-output output "_posts")))
                  (if (and draft post)
                      (om--swap-window-files post draft)))))))))

(defun om--swap-window-files (old-filename new-filename)
  "Swap any windows displaying OLD-FILENAME to instead display NEW-FILENAME.

This function creates a buffer for NEW-FILENAME if one does not
already exist, finds any windows currently displaying a buffer
corresponding to OLD-FILENAME, and changes them to instead edit the
NEW-FILENAME buffer. Any buffer visiting OLD-FILENAME is then killed.
This function is called when posts or drafts move between published
and unpublished status."
  (let* ((new-buffer (find-file-noselect new-filename))
         (old-buffer (find-buffer-visiting old-filename))
         (window-visiting-old-file (get-buffer-window old-buffer)))
    (while window-visiting-old-file
      (progn (set-window-buffer window-visiting-old-file new-buffer)
             (setq window-visiting-old-file (get-buffer-window old-buffer))))
    (if old-buffer
        (kill-buffer old-buffer))))

(defun om--find-filename-in-output (output &optional prefix)
  "Find the filename in an Octopress OUTPUT line.

This helper function will extract a filename with preceding path
components, if present, from a single line of Octopress output. Used
by `om--handle-octopress-output'.

If the string PREFIX is given, the filename is assumed to begin with
it. For example, call with '_posts' or '_drafts' to find the
corresponding paths in the output line."
  (let* ((found (if prefix (string-match (concat "\\(" prefix "[^\s]*\\)") output)
                  (string-match ": \\([^\s]*\\)$" output)))
         (filename (and found
                        (expand-file-name (match-string 1 output) (om--get-root)))))
    filename))

(defun om--prop-command (key label)
  "Propertize a command legend item with pretty colors.

Return a propertized string like KEY: LABEL."
  (concat (propertize key 'face 'font-lock-keyword-face) ": " label))

(defun om--strip-text-properties(text)
  "Remove all properties from TEXT and return it."
  (set-text-properties 0 (length text) nil text)
      text)

(defun om--highlight-current-line ()
  (if (om--thing-on-this-line)
      (let ((end (save-excursion
                   (forward-line 1)
                   (point))))
        (move-overlay om-highlight-current-line-overlay (line-beginning-position) end))
    (delete-overlay om-highlight-current-line-overlay)))

(define-derived-mode octopress-mode nil "Octopress"
  "The major mode for interacting with a Jekyll site.

The following keys are available in `octopress-mode':

  \\{octopress-mode-map}"
  (setq truncate-lines t)
  (add-hook 'post-command-hook 'om--highlight-current-line nil t))

(define-derived-mode octopress-server-mode nil "Octopress[Server]"
  "The major mode for interacting with a Jekyll server process.

The following keys are available in `octopress-server-mode':

  \\{octopress-server-mode-map}"
  (setq truncate-lines t))

(define-derived-mode octopress-process-mode nil "Octopress[Process]"
  "The major mode for interacting with Octopress and Jekyll shell commands.

The following keys are available in `octopress-process-mode':

  \\{octopress-server-mode-map}"
  (setq truncate-lines t))

(provide 'octopress-mode)

;;; octopress-mode.el ends here

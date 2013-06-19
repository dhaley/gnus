;;; eww.el --- Emacs Web Wowser

;; Copyright (C) 2013 Free Software Foundation, Inc.

;; Author: Lars Magne Ingebrigtsen <larsi@gnus.org>
;; Keywords: html

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;;; Code:

(eval-when-compile (require 'cl))
(require 'format-spec)
(require 'shr)
(require 'url)
(require 'mm-url)

(defgroup eww nil
  "Emacs Web Wowser"
  :version "24.4"
  :group 'hypermedia
  :prefix "eww-")

(defcustom eww-header-line-format "%t: %u"
  "Header line format.
- %t is replaced by the title.
- %u is replaced by the URL."
  :group 'eww
  :type 'string)

(defface eww-form-submit
  '((((type x w32 ns) (class color))	; Like default mode line
     :box (:line-width 2 :style released-button)
     :background "#808080" :foreground "black"))
  "Face for eww buffer buttons."
  :version "24.4"
  :group 'eww)

(defface eww-form-checkbox
  '((((type x w32 ns) (class color))	; Like default mode line
     :box (:line-width 2 :style released-button)
     :background "lightgrey" :foreground "black"))
  "Face for eww buffer buttons."
  :version "24.4"
  :group 'eww)

(defface eww-form-select
  '((((type x w32 ns) (class color))	; Like default mode line
     :box (:line-width 2 :style released-button)
     :background "lightgrey" :foreground "black"))
  "Face for eww buffer buttons."
  :version "24.4"
  :group 'eww)

(defface eww-form-text
  '((t (:background "#505050"
		    :foreground "white"
		    :box (:line-width 1))))
  "Face for eww text inputs."
  :version "24.4"
  :group 'eww)

(defvar eww-current-url nil)
(defvar eww-current-title ""
  "Title of current page.")
(defvar eww-history nil)

(defvar eww-next-url nil)
(defvar eww-previous-url nil)
(defvar eww-up-url nil)
(defvar eww-home-url nil)
(defvar eww-start-url nil)
(defvar eww-contents-url nil)

;;;###autoload
(defun eww (url)
  "Fetch URL and render the page."
  (interactive "sUrl: ")
  (unless (string-match-p "\\`[a-zA-Z][-a-zA-Z0-9+.]*://" url)
    (setq url (concat "http://" url)))
  (url-retrieve url 'eww-render (list url)))

;;;###autoload
(defun eww-open-file (file)
  "Render a file using EWW."
  (interactive "fFile: ")
  (eww (concat "file://" (expand-file-name file))))

(defun eww-render (status url &optional point)
  (let ((redirect (plist-get status :redirect)))
    (when redirect
      (setq url redirect)))
  (set (make-local-variable 'eww-next-url) nil)
  (set (make-local-variable 'eww-previous-url) nil)
  (set (make-local-variable 'eww-up-url) nil)
  (set (make-local-variable 'eww-home-url) nil)
  (set (make-local-variable 'eww-start-url) nil)
  (set (make-local-variable 'eww-contents-url) nil)
  (let* ((headers (eww-parse-headers))
	 (shr-target-id
	  (and (string-match "#\\(.*\\)" url)
	       (match-string 1 url)))
	 (content-type
	  (mail-header-parse-content-type
	   (or (cdr (assoc "content-type" headers))
	       "text/plain")))
	 (charset (intern
		   (downcase
		    (or (cdr (assq 'charset (cdr content-type)))
			(eww-detect-charset (equal (car content-type)
						   "text/html"))
			"utf8"))))
	 (data-buffer (current-buffer)))
    (unwind-protect
	(progn
	  (cond
	   ((equal (car content-type) "text/html")
	    (eww-display-html charset url))
	   ((string-match "^image/" (car content-type))
	    (eww-display-image))
	   (t
	    (eww-display-raw charset)))
	  (cond
	   (point
	    (goto-char point))
	   (shr-target-id
	    (let ((point (next-single-property-change
			  (point-min) 'shr-target-id)))
	      (when point
		(goto-char (1+ point)))))))
      (kill-buffer data-buffer))))

(defun eww-parse-headers ()
  (let ((headers nil))
    (goto-char (point-min))
    (while (and (not (eobp))
		(not (eolp)))
      (when (looking-at "\\([^:]+\\): *\\(.*\\)")
	(push (cons (downcase (match-string 1))
		    (match-string 2))
	      headers))
      (forward-line 1))
    (unless (eobp)
      (forward-line 1))
    headers))

(defun eww-detect-charset (html-p)
  (let ((case-fold-search t)
	(pt (point)))
    (or (and html-p
	     (re-search-forward
	      "<meta[\t\n\r ]+[^>]*charset=\"?\\([^\t\n\r \"/>]+\\)" nil t)
	     (goto-char pt)
	     (match-string 1))
	(and (looking-at
	      "[\t\n\r ]*<\\?xml[\t\n\r ]+[^>]*encoding=\"\\([^\"]+\\)")
	     (match-string 1)))))

(defun eww-display-html (charset url)
  (unless (eq charset 'utf8)
    (decode-coding-region (point) (point-max) charset))
  (let ((document
	 (list
	  'base (list (cons 'href url))
	  (libxml-parse-html-region (point) (point-max)))))
    (eww-setup-buffer)
    (setq eww-current-url url)
    (eww-update-header-line-format)
    (let ((inhibit-read-only t)
	  (after-change-functions nil)
	  (shr-width nil)
	  (shr-external-rendering-functions
	   '((title . eww-tag-title)
	     (form . eww-tag-form)
	     (input . eww-tag-input)
	     (textarea . eww-tag-textarea)
	     (body . eww-tag-body)
	     (select . eww-tag-select)
	     (link . eww-tag-link)
	     (a . eww-tag-a))))
      (shr-insert-document document))
    (goto-char (point-min))))

(defun eww-handle-link (cont)
  (let* ((rel (assq :rel cont))
  	(href (assq :href cont))
	(where (assoc
		;; The text associated with :rel is case-insensitive.
		(if rel (downcase (cdr rel)))
		      '(("next" . eww-next-url)
			;; Texinfo uses "previous", but HTML specifies
			;; "prev", so recognize both.
			("previous" . eww-previous-url)
			("prev" . eww-previous-url)
			;; HTML specifies "start" but also "contents",
			;; and Gtk seems to use "home".  Recognize
			;; them all; but store them in different
			;; variables so that we can readily choose the
			;; "best" one.
			("start" . eww-start-url)
			("home" . eww-home-url)
			("contents" . eww-contents-url)
			("up" . eww-up-url)))))
    (and href
	 where
	 (set (cdr where) (cdr href)))))

(defun eww-tag-link (cont)
  (eww-handle-link cont)
  (shr-generic cont))

(defun eww-tag-a (cont)
  (eww-handle-link cont)
  (shr-tag-a cont))

(defun eww-update-header-line-format ()
  (if eww-header-line-format
      (setq header-line-format (format-spec eww-header-line-format
                                            `((?u . ,eww-current-url)
                                              (?t . ,eww-current-title))))
    (setq header-line-format nil)))

(defun eww-tag-title (cont)
  (setq eww-current-title "")
  (dolist (sub cont)
    (when (eq (car sub) 'text)
      (setq eww-current-title (concat eww-current-title (cdr sub)))))
  (eww-update-header-line-format))

(defun eww-tag-body (cont)
  (let* ((start (point))
	 (fgcolor (cdr (or (assq :fgcolor cont)
                           (assq :text cont))))
	 (bgcolor (cdr (assq :bgcolor cont)))
	 (shr-stylesheet (list (cons 'color fgcolor)
			       (cons 'background-color bgcolor))))
    (shr-generic cont)
    (eww-colorize-region start (point) fgcolor bgcolor)))

(defun eww-colorize-region (start end fg &optional bg)
  (when (or fg bg)
    (let ((new-colors (shr-color-check fg bg)))
      (when new-colors
	(when fg
	  (add-face-text-property start end
				  (list :foreground (cadr new-colors))
				  t))
	(when bg
	  (add-face-text-property start end
				  (list :background (car new-colors))
				  t))))))

(defun eww-display-raw (charset)
  (let ((data (buffer-substring (point) (point-max))))
    (eww-setup-buffer)
    (let ((inhibit-read-only t))
      (insert data))
    (goto-char (point-min))))

(defun eww-display-image ()
  (let ((data (buffer-substring (point) (point-max))))
    (eww-setup-buffer)
    (let ((inhibit-read-only t))
      (shr-put-image data nil))
    (goto-char (point-min))))

(defun eww-setup-buffer ()
  (pop-to-buffer (get-buffer-create "*eww*"))
  (remove-overlays)
  (let ((inhibit-read-only t))
    (erase-buffer))
  (eww-mode))

(defvar eww-mode-map
  (let ((map (make-sparse-keymap)))
    (suppress-keymap map)
    (define-key map "q" 'eww-quit)
    (define-key map "g" 'eww-reload)
    (define-key map [tab] 'shr-next-link)
    (define-key map [backtab] 'shr-previous-link)
    (define-key map [delete] 'scroll-down-command)
    (define-key map "\177" 'scroll-down-command)
    (define-key map " " 'scroll-up-command)
    (define-key map "l" 'eww-back-url)
    (define-key map "n" 'eww-next-url)
    (define-key map "p" 'eww-previous-url)
    (define-key map "u" 'eww-up-url)
    (define-key map "t" 'eww-top-url)
    map))

(define-derived-mode eww-mode nil "eww"
  "Mode for browsing the web.

\\{eww-mode-map}"
  (set (make-local-variable 'eww-current-url) 'author)
  (set (make-local-variable 'browse-url-browser-function) 'eww-browse-url)
  (set (make-local-variable 'after-change-functions) 'eww-process-text-input)
  ;;(setq buffer-read-only t)
  )

(defun eww-browse-url (url &optional new-window)
  (when (and (equal major-mode 'eww-mode)
	     eww-current-url)
    (push (list eww-current-url (point))
	  eww-history))
  (eww url))

(defun eww-quit ()
  "Exit the Emacs Web Wowser."
  (interactive)
  (setq eww-history nil)
  (kill-buffer (current-buffer)))

(defun eww-back-url ()
  "Go to the previously displayed page."
  (interactive)
  (when (zerop (length eww-history))
    (error "No previous page"))
  (let ((prev (pop eww-history)))
    (url-retrieve (car prev) 'eww-render (list (car prev) (cadr prev)))))

(defun eww-next-url ()
  "Go to the page marked `next'.
A page is marked `next' if rel=\"next\" appears in a <link>
or <a> tag."
  (interactive)
  (if eww-next-url
      (eww-browse-url (shr-expand-url eww-next-url eww-current-url))
    (error "No `next' on this page")))

(defun eww-previous-url ()
  "Go to the page marked `previous'.
A page is marked `previous' if rel=\"previous\" appears in a <link>
or <a> tag."
  (interactive)
  (if eww-previous-url
      (eww-browse-url (shr-expand-url eww-previous-url eww-current-url))
    (error "No `previous' on this page")))

(defun eww-up-url ()
  "Go to the page marked `up'.
A page is marked `up' if rel=\"up\" appears in a <link>
or <a> tag."
  (interactive)
  (if eww-up-url
      (eww-browse-url (shr-expand-url eww-up-url eww-current-url))
    (error "No `up' on this page")))

(defun eww-top-url ()
  "Go to the page marked `top'.
A page is marked `top' if rel=\"start\", rel=\"home\", or rel=\"contents\"
appears in a <link> or <a> tag."
  (interactive)
  (let ((best-url (or eww-start-url
		      eww-contents-url
		      eww-home-url)))
    (if best-url
	(eww-browse-url (shr-expand-url best-url eww-current-url))
      (error "No `top' for this page"))))

(defun eww-reload ()
  "Reload the current page."
  (interactive)
  (url-retrieve eww-current-url 'eww-render
		(list eww-current-url (point))))

;; Form support.

(defvar eww-form nil)

(defvar eww-submit-map
  (let ((map (make-sparse-keymap)))
    (define-key map "\r" 'eww-submit)
    map))

(defvar eww-checkbox-map
  (let ((map (make-sparse-keymap)))
    (define-key map [space] 'eww-toggle-checkbox)
    (define-key map "\r" 'eww-toggle-checkbox)
    map))

(defvar eww-text-map
  (let ((map (make-keymap)))
    (set-keymap-parent map text-mode-map)
    (define-key map "\r" 'eww-submit)
    (define-key map [(control a)] 'eww-beginning-of-text)
    (define-key map [(control e)] 'eww-end-of-text)
    (define-key map [tab] 'shr-next-link)
    (define-key map [backtab] 'shr-previous-link)
    map))

(defvar eww-textarea-map
  (let ((map (make-keymap)))
    (set-keymap-parent map text-mode-map)
    (define-key map "\r" 'forward-line)
    (define-key map [tab] 'shr-next-link)
    (define-key map [backtab] 'shr-previous-link)
    map))

(defvar eww-select-map
  (let ((map (make-sparse-keymap)))
    (define-key map "\r" 'eww-change-select)
    map))

(defun eww-beginning-of-text ()
  "Move to the start of the input field."
  (interactive)
  (goto-char (eww-beginning-of-field)))

(defun eww-end-of-text ()
  "Move to the end of the text in the input field."
  (interactive)
  (goto-char (eww-end-of-field))
  (let ((start (eww-beginning-of-field)))
    (while (and (equal (following-char) ? )
		(> (point) start))
      (forward-char -1))
    (when (> (point) start)
      (forward-char 1))))

(defun eww-beginning-of-field ()
  (cond
   ((bobp)
    (point))
   ((not (eq (get-text-property (point) 'eww-form)
	     (get-text-property (1- (point)) 'eww-form)))
    (point))
   (t
    (previous-single-property-change
     (point) 'eww-form nil (point-min)))))

(defun eww-end-of-field ()
  (1- (next-single-property-change
       (point) 'eww-form nil (point-max))))

(defun eww-tag-form (cont)
  (let ((eww-form
	 (list (assq :method cont)
	       (assq :action cont)))
	(start (point)))
    (shr-ensure-paragraph)
    (shr-generic cont)
    (unless (bolp)
      (insert "\n"))
    (insert "\n")
    (when (> (point) start)
      (put-text-property start (1+ start)
			 'eww-form eww-form))))

(defun eww-form-submit (cont)
  (let ((start (point))
	(value (cdr (assq :value cont))))
    (setq value
	  (if (zerop (length value))
	      "Submit"
	    value))
    (insert value)
    (add-face-text-property start (point) 'eww-form-submit)
    (put-text-property start (point) 'eww-form
		       (list :eww-form eww-form
			     :value value
			     :type "submit"
			     :name (cdr (assq :name cont))))
    (put-text-property start (point) 'keymap eww-submit-map)
    (insert " ")))

(defun eww-form-checkbox (cont)
  (let ((start (point)))
    (if (cdr (assq :checked cont))
	(insert "[X]")
      (insert "[ ]"))
    (add-face-text-property start (point) 'eww-form-checkbox)
    (put-text-property start (point) 'eww-form
		       (list :eww-form eww-form
			     :value (cdr (assq :value cont))
			     :type (downcase (cdr (assq :type cont)))
			     :checked (cdr (assq :checked cont))
			     :name (cdr (assq :name cont))))
    (put-text-property start (point) 'keymap eww-checkbox-map)
    (insert " ")))

(defun eww-form-text (cont)
  (let ((start (point))
	(type (downcase (or (cdr (assq :type cont))
			    "text")))
	(value (or (cdr (assq :value cont)) ""))
	(width (string-to-number
		(or (cdr (assq :size cont))
		    "40"))))
    (insert value)
    (when (< (length value) width)
      (insert (make-string (- width (length value)) ? )))
    (put-text-property start (point) 'face 'eww-form-text)
    (put-text-property start (point) 'local-map eww-text-map)
    (put-text-property start (point) 'inhibit-read-only t)
    (put-text-property start (point) 'eww-form
		       (list :eww-form eww-form
			     :value value
			     :type type
			     :name (cdr (assq :name cont))))
    (insert " ")))

(defun eww-process-text-input (beg end length)
  (let* ((form (get-text-property end 'eww-form))
	(properties (text-properties-at end))
	(type (plist-get form :type)))
    (when (and form
	       (member type '("text" "password" "textarea")))
      (cond
       ((zerop length)
	;; Delete some text
	(save-excursion
	  (goto-char
	   (if (equal type "textarea")
	       (1- (line-end-position))
	     (eww-end-of-field)))
	  (let ((new (- end beg)))
	    (while (and (> new 0)
			(eql (following-char) ? ))
	      (delete-region (point) (1+ (point)))
	      (setq new (1- new))))
	  (set-text-properties beg end properties)))
       ((> length 0)
	;; Add padding.
	(save-excursion
	  (goto-char
	   (if (equal type "textarea")
	       (1- (line-end-position))
	     (eww-end-of-field)))
	  (let ((start (point)))
	    (insert (make-string length ? ))
	    (set-text-properties start (point) properties)))))
      (plist-put form :value (buffer-substring-no-properties
			      (eww-beginning-of-field)
			      (eww-end-of-field))))))

(defun eww-tag-textarea (cont)
  (let ((start (point))
	(value (or (cdr (assq :value cont)) ""))
	(lines (string-to-number
		(or (cdr (assq :rows cont))
		    "10")))
	(width (string-to-number
		(or (cdr (assq :cols cont))
		    "10")))
	end)
    (shr-ensure-newline)
    (insert value)
    (shr-ensure-newline)
    (when (< (count-lines start (point)) lines)
      (dotimes (i (- lines (count-lines start (point))))
	(insert "\n")))
    (setq end (point-marker))
    (goto-char start)
    (while (< (point) end)
      (end-of-line)
      (let ((pad (- width (- (point) (line-beginning-position)))))
	(when (> pad 0)
	  (insert (make-string pad ? ))))
      (add-face-text-property (line-beginning-position)
			      (point) 'eww-form-text)
      (put-text-property (line-beginning-position) (point)
			 'local-map eww-textarea-map)
      (forward-line 1))
    (put-text-property start (point) 'eww-form
		       (list :eww-form eww-form
			     :value value
			     :type "textarea"
			     :name (cdr (assq :name cont))))))

(defun eww-tag-input (cont)
  (let ((type (downcase (or (cdr (assq :type cont))
			     "text")))
	(start (point)))
    (cond
     ((or (equal type "checkbox")
	  (equal type "radio"))
      (eww-form-checkbox cont))
     ((equal type "submit")
      (eww-form-submit cont))
     ((equal type "hidden")
      (let ((form eww-form)
	    (name (cdr (assq :name cont))))
	;; Don't add <input type=hidden> elements repeatedly.
	(while (and form
		    (or (not (consp (car form)))
			(not (eq (caar form) 'hidden))
			(not (equal (plist-get (cdr (car form)) :name)
				    name))))
	  (setq form (cdr form)))
	(unless form
	  (nconc eww-form (list
			   (list 'hidden
				 :name name
				 :value (cdr (assq :value cont))))))))
     (t
      (eww-form-text cont)))
    (unless (= start (point))
      (put-text-property start (1+ start) 'help-echo "Input field"))))

(defun eww-tag-select (cont)
  (shr-ensure-paragraph)
  (let ((menu (list :name (cdr (assq :name cont))
		    :eww-form eww-form))
	(options nil)
	(start (point))
	(max 0))
    (dolist (elem cont)
      (when (eq (car elem) 'option)
	(when (cdr (assq :selected (cdr elem)))
	  (nconc menu (list :value
			    (cdr (assq :value (cdr elem))))))
	(let ((display (or (cdr (assq 'text (cdr elem))) "")))
	  (setq max (max max (length display)))
	  (push (list 'item
		      :value (cdr (assq :value (cdr elem)))
		      :display display)
		options))))
    (when options
      (setq options (nreverse options))
      ;; If we have no selected values, default to the first value.
      (unless (plist-get menu :value)
	(nconc menu (list :value (nth 2 (car options)))))
      (nconc menu options)
      (let ((selected (eww-select-display menu)))
	(insert selected
		(make-string (- max (length selected)) ? )))
      (put-text-property start (point) 'eww-form menu)
      (add-face-text-property start (point) 'eww-form-select)
      (put-text-property start (point) 'keymap eww-select-map)
      (shr-ensure-paragraph))))

(defun eww-select-display (select)
  (let ((value (plist-get select :value))
	display)
    (dolist (elem select)
      (when (and (consp elem)
		 (eq (car elem) 'item)
		 (equal value (plist-get (cdr elem) :value)))
	(setq display (plist-get (cdr elem) :display))))
    display))

(defun eww-change-select ()
  "Change the value of the select drop-down menu under point."
  (interactive)
  (let* ((input (get-text-property (point) 'eww-form))
	 (properties (text-properties-at (point)))
	 (completion-ignore-case t)
	 (options
	  (delq nil
		(mapcar (lambda (elem)
			  (and (consp elem)
			       (eq (car elem) 'item)
			       (cons (plist-get (cdr elem) :display)
				     (plist-get (cdr elem) :value))))
			input)))
	 (display
	  (completing-read "Change value: " options nil 'require-match))
	 (inhibit-read-only t))
    (plist-put input :value (cdr (assoc-string display options t)))
    (goto-char
     (eww-update-field display))))

(defun eww-update-field (string)
  (let ((properties (text-properties-at (point)))
	(start (eww-beginning-of-field))
	(end (1+ (eww-end-of-field))))
    (delete-region start end)
    (insert string
	    (make-string (- (- end start) (length string)) ? ))
    (set-text-properties start end properties)
    start))

(defun eww-toggle-checkbox ()
  "Toggle the value of the checkbox under point."
  (interactive)
  (let* ((input (get-text-property (point) 'eww-form))
	 (type (plist-get input :type)))
    (if (equal type "checkbox")
	(goto-char
	 (1+
	  (if (plist-get input :checked)
	      (progn
		(plist-put input :checked nil)
		(eww-update-field "[ ]"))
	    (plist-put input :checked t)
	    (eww-update-field "[X]"))))
      ;; Radio button.  Switch all other buttons off.
      (let ((name (plist-get input :name)))
	(save-excursion
	  (dolist (elem (eww-inputs (plist-get input :eww-form)))
	    (when (equal (plist-get (cdr elem) :name) name)
	      (goto-char (car elem))
	      (if (not (eq (cdr elem) input))
		  (progn
		    (plist-put input :checked nil)
		    (eww-update-field "[ ]"))
		(plist-put input :checked t)
		(eww-update-field "[X]")))))
	(forward-char 1)))))

(defun eww-inputs (form)
  (let ((start (point-min))
	(inputs nil))
    (while (and start
		(< start (point-max)))
      (when (or (get-text-property start 'eww-form)
		(setq start (next-single-property-change start 'eww-form)))
	(when (eq (plist-get (get-text-property start 'eww-form) :eww-form)
		  form)
	  (push (cons start (get-text-property start 'eww-form))
		inputs))
	(setq start (next-single-property-change start 'eww-form))))
    (nreverse inputs)))

(defun eww-input-value (input)
  (let ((type (plist-get input :type))
	(value (plist-get input :value)))
    (cond
     ((equal type "textarea")
      (with-temp-buffer
	(insert value)
	(goto-char (point-min))
	(while (re-search-forward "^ +\n\\| +$" nil t)
	  (replace-match "" t t))
	(buffer-string)))
     (t
      (if (string-match " +\\'" value)
	  (substring value 0 (match-beginning 0))
	value)))))

(defun eww-submit ()
  "Submit the current form."
  (interactive)
  (let* ((this-input (get-text-property (point) 'eww-form))
	 (form (plist-get this-input :eww-form))
	 values next-submit)
    (dolist (elem (sort (eww-inputs form)
			 (lambda (o1 o2)
			   (< (car o1) (car o2)))))
      (let* ((input (cdr elem))
	     (input-start (car elem))
	     (name (plist-get input :name)))
	(when name
	  (cond
	   ((member (plist-get input :type) '("checkbox" "radio"))
	    (when (plist-get input :checked)
	      (push (cons name (plist-get input :value))
		    values)))
	   ((equal (plist-get input :type) "submit")
	    ;; We want the values from buttons if we hit a button if
	    ;; we hit enter on it, or if it's the first button after
	    ;; the field we did hit return on.
	    (when (or (eq input this-input)
		      (and (not (eq input this-input))
			   (null next-submit)
			   (> input-start (point))))
	      (setq next-submit t)
	      (push (cons name (plist-get input :value))
		    values)))
	   (t
	    (push (cons name (eww-input-value input))
		  values))))))
    (dolist (elem form)
      (when (and (consp elem)
		 (eq (car elem) 'hidden))
	(push (cons (plist-get (cdr elem) :name)
		    (plist-get (cdr elem) :value))
	      values)))
    (if (and (stringp (cdr (assq :method form)))
	     (equal (downcase (cdr (assq :method form))) "post"))
	(let ((url-request-method "POST")
	      (url-request-extra-headers
	       '(("Content-Type" . "application/x-www-form-urlencoded")))
	      (url-request-data (mm-url-encode-www-form-urlencoded values)))
	  (eww-browse-url (shr-expand-url (cdr (assq :action form))
					  eww-current-url)))
      (eww-browse-url
       (concat
	(if (cdr (assq :action form))
	    (shr-expand-url (cdr (assq :action form))
			    eww-current-url)
	  eww-current-url)
	"?"
	(mm-url-encode-www-form-urlencoded values))))))

(provide 'eww)

;;; eww.el ends here

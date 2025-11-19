;;; ibuffer-tabspaces.el --- ibuffer integration for tabspaces -*- lexical-binding: t; -*-

;;; Copyright (C) 2025 Joseph Gangolf

;; Author: Joseph Gangolf <jgangolf1@gmail.com>
;; Keywords: tools
;; URL: https://github.com/jgangolf1/ibuffer-tabspaces
;; Package-Version: 0.1
;; Package-Requires: ((emacs "27.1") (tabspaces "1.0"))

;;; Commentary:

;; This package provides ibuffer integration for tabspaces.
;; Find tabspaces here: https://github.com/mclear-tools/tabspaces
;;
;; Use:
;;
;; To narrow ibuffer to a tab, or a list of tabs:
;;
;;   M-x ibuffer-tabspaces-narrow-to-tab
;;
;; To group buffers by tab:
;;
;;   M-x ibuffer-tabspaces-group-by-tabs
;;
;; These can be made default through `ibuffer-hook':
;;
;;   (add-hook 'ibuffer-hook #'ibuffer-tabspaces-narrow-to-tab)
;;   (add-hook 'ibuffer-hook #'ibuffer-tabspaces-group-by-tab)
;;
;; To open a buffer and switch tabs, `ibuffer-tabspaces-switch-buffer-and-tab'.
;;
;; This package additionally defines two columns which display the tab of a
;; buffer and the total number of tabs a buffer belongs to. The tab column only
;; displays the first tab. Mousing over the column displays all tabs in the echo
;; area.

;;; Code:

(require 'tabspaces)
(require 'ibuffer)
(require 'ibuf-ext)

;;;; helper functions

(defun ibuffer-tabspaces--first-tab-from-buffer (&optional buffer-or-name)
  "Return the name of the first tab which BUFFER-OR-NAME belongs to."
  (unless buffer-or-name
    (setq buffer-or-name (current-buffer)))
  (let ((target-buf (get-buffer buffer-or-name)))
    (cl-loop for tab in (tabspaces--list-tabspaces)
             named "outer"
             do (cl-loop for buf in (tabspaces--buffer-list nil (tab-bar--tab-index-by-name tab))
                         when (eq buf target-buf)
                         do (cl-return-from "outer" tab)))))

(defun ibuffer-tabspaces--tabs-from-buffer (&optional buffer-or-name)
  "Return list of tabs associated with BUFFER-OR-NAME."
  (unless buffer-or-name
    (setq buffer-or-name (current-buffer)))
  (let ((target-buf (get-buffer buffer-or-name))
        tabs)
    (dolist (tab (tabspaces--list-tabspaces))
      (when-let (match
                 (cl-loop for buf in (tabspaces--buffer-list nil (tab-bar--tab-index-by-name tab))
                          when (eq buf target-buf)
                          return tab))
        (push match tabs)))
    (reverse tabs)))


;;;; misc

(defvar-keymap ibuffer-tabspaces-tab-header-map
  "<mouse-1>" #'ibuffer-do-sort-by-tabspace)

(defvar-keymap ibuffer-tabspaces-tab-map
  "<mouse-2>" #'ibuffer-tabspaces-mouse-filter-by-tab)

(add-to-list 'ibuffer-formats '(mark modified read-only locked " "
                                     (name 24 24 :left :elide) " "
                                     (tabspace-count 1 1 :right) " "
                                     (tabspace 8 8 :left) " "
                                     (size 6 -1 :right) " "
                                     (mode 10 10 :left :elide) " "
                                     filename-and-process))

;;;; ibuffer mechanisms

(define-ibuffer-filter tabspace
    "Narrow to tabspace tab."
  ( :description "tabspaces tab"
    :reader  (completing-read-multiple "Filter by tabspace: "
                                       (tabspaces--list-tabspaces)
                                       nil
                                       t)
    :accept-list t)
  (when-let (idx (tab-bar--tab-index-by-name qualifier))
    (memq buf (tabspaces--buffer-list nil idx))))


(define-ibuffer-column tabspace
  ( :name "Tab"
    :header-mouse-map ibuffer-tabspaces-tab-header-map
    :props ('keymap ibuffer-tabspaces-tab-map))
  (propertize
   (format "%s" (ibuffer-tabspaces--first-tab-from-buffer (current-buffer)))
   'mouse-face 'highlight
   ;; 'keymap 'ibuffer-tabspaces-tab-map
   'help-echo `(concat
                "Tabs: "
                (cl-loop for tab in (ibuffer-tabspaces--tabs-from-buffer ,buffer)
                         for i from 0
                         concat (format "%s  " tab)))))

(define-ibuffer-column tabspace-count
  (:name "#")
  (int-to-string (length (ibuffer-tabspaces--tabs-from-buffer (current-buffer)))))

(define-ibuffer-sorter tabspace
  "Sort by tab."
  (:description "sort by tab")
  (string-lessp
   (ibuffer-tabspaces--first-tab-from-buffer (car a))
   (ibuffer-tabspaces--first-tab-from-buffer (car b))))

;;;; main functions

(defun ibuffer-tabspaces-visit-buffer-switch-tab (&optional single)
  "Visit the buffer on this line and switch to tab.
If prefix argument SINGLE is non-nil, then also ensure there is only
one window."
  (interactive "P")
  (let ((buf (ibuffer-current-buffer t)))
    (tabspaces-switch-buffer-and-tab (buffer-name buf))
    (when single
      (delete-other-windows))))

(defun ibuffer-tabspaces-mouse-filter-by-tab (event)
  (interactive "e" ibuffer-mode)
  (save-excursion
    (mouse-set-point event)
    (when-let (tabs (ibuffer-tabspaces--tabs-from-buffer (ibuffer-current-buffer)))
      (if (= 1 (length tabs))
          (ibuffer-filter-by-tabspace (car-safe tabs))
        (ibuffer-filter-by-tabspace (completing-read-multiple "Filter by tabspace: " tabs nil t))))))


(defun ibuffer-tabspaces-narrow-to-tab ()
  "Filters ibuffer to the current tab using ibuffer filters."
  (interactive)
  (ibuffer-filter-by-tabspace (tabspaces--current-tab-name)))

(defun ibuffer-tabspaces--generate-filter-groups ()
  "Generate ibuffer filter group for each tab."
  (mapcar (lambda (tab)
            `(,tab (tabspace . ,tab)))
          (tabspaces--list-tabspaces)))

(defun ibuffer-tabspaces-group-by-tabs (&optional append)
  "Activate an ibuffer filter group for each tab.
Overrides currently active filter groups. With prefix APPEND, appends filters to
the top. Due to ibuffer limitations, buffers will only appear under a single
tab, even if the buffer is actually in multiple tabs."
  (interactive "P")
  (let* ((tab-filters (ibuffer-tabspaces--generate-filter-groups))
         (filters (if append
                      (append tab-filters
                              ibuffer-filter-groups)
                    tab-filters)))
    (setq ibuffer-filter-groups filters))
  (when-let (ibuf (get-buffer "*Ibuffer*"))
    (with-current-buffer ibuf
      (ibuffer-update nil t))))

(provide 'ibuffer-tabspaces)

;;; ibuffer-tabspaces.el ends here

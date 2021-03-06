(module mrmenu mzscheme
  (require mzlib/class
           mzlib/class100
           mzlib/list
           (prefix wx: "kernel.rkt")
           (prefix wx: "wxme/keymap.rkt")
           "lock.rkt"
           "const.rkt"
           "helper.rkt"
           "check.rkt"
           "wx.rkt"
           "app.rkt"
           "wxmenu.rkt"
           "mrtop.rkt"
           "mrmenuintf.rkt"
           "mrpopup.rkt")

  (provide separator-menu-item%
           menu-item%
           checkable-menu-item%
           menu%
           menu-bar%
           get-default-shortcut-prefix
           (protect menu-parent-only
                    menu-or-bar-parent))

  (define root-menu-frame-used? #f)

  ;; Most of the work is in the item. Anything that appears in a menubar or
  ;;  menu has an item. Submenus are created as instances of menu%, but
  ;;  menu% has a get-item method for manipulating the menu w.r.t. the parent
  ;;  (e.g., changing the title or enabled state). A popup menu, created
  ;;  as an instance of popup-menu%, has no item.
  ;;
  ;; A menu bar is created as a menu-bar%, given a frame as its parent. The
  ;;  frame must not already have a menu bar.
  ;;
  ;;  Plain labeled items are created as instances of menu-item% or
  ;;   checkable-menu-item%. The parent must be a menu-item-container<%>,
  ;;   which is a menu%, popup-menu%, or menu-bar%

  (define separator-menu-item%
    (class100* mred% (menu-item<%>) (parent)
      (sequence (menu-parent-only 'separator-menu-item parent))
      (private-field
       [prnt parent]
       [wx #f]
       [shown? #f]
       [wx-parent #f])
      (public
	[get-parent (lambda () prnt)]
	[restore (entry-point
		  (lambda ()
		    (unless shown?
		      (send wx-parent append-separator)
		      (send wx-parent append-item this wx)
		      (set! shown? #t))))]
	[delete (entry-point
		 (lambda ()
		   (when shown?
		     (send wx-parent delete-sep this wx)
		     (set! shown? #f))))]
	[is-deleted? (lambda () (not shown?))])
      (sequence
	(as-entry
	 (lambda ()
	   (set! wx (make-object wx-menu-item% this #f #f))
	   (set! wx-parent (send (mred->wx prnt) get-container))
	   (super-init wx)))
	(restore))))

  (define strip-tab 
    (if (menu-shortcut-in-label?)
	(lambda (s) 
	  (car (regexp-match #rx"^[^\t]*" s)))
	(lambda (s) 
	  (regexp-replace* #rx"&"
			   (regexp-replace* #rx"&(.)" 
					    (regexp-replace*
					     #rx" *[(]&.[)] *"
					     (car (regexp-match #rx"^[^\t]*" s))
					     "")
					    "\\1")
			   "\\&\\&"))))

  (define basic-labelled-menu-item%
    (class100* mred% (labelled-menu-item<%>) (prnt lbl help-str wx-sub chkble? keymap set-wx demand-callback
                                                   on-pre-delete on-post-restore)
      (private-field
       [parent prnt]
       [label lbl]
       [help-string help-str]
       [wx-submenu wx-sub]
       [checkable? chkble?]
       [callback demand-callback]
       [wx #f]
       [wx-parent #f]
       [plain-label (string->immutable-string (wx:label->plain-label label))]
       [in-menu? (is-a? parent internal-menu<%>)]
       [shown? #f]
       [enabled? #t]
       [post-restore on-post-restore]
       [pre-delete on-pre-delete])
      (private
	[do-enable (lambda (on?)
		     (when shown?
		       (if in-menu?
			   (send wx-parent enable wx (send wx id) on?)
			   (send wx-parent enable-top (send wx-parent position-of this) on?)))
		     (set! enabled? (and on? #t)))])
      (public
	[on-demand (lambda () (callback this))]
	[get-parent (lambda () parent)]
	[get-label (lambda () label)]
	[set-label (entry-point
		    (lambda (l)
		      (check-label-string '(method labelled-menu-item<%> set-label) l)
		      (set! label (string->immutable-string l))
		      (set-mcar! (send wx get-menu-data) l)  ; for meta-shortcuts
		      (set! plain-label (string->immutable-string (wx:label->plain-label l)))
		      (when shown?
			(if in-menu?
			    (send wx-parent set-label (send wx id) l)
			    (send wx-parent set-label-top (send wx-parent position-of this) label)))))]
	[get-plain-label (lambda () plain-label)]
	[get-help-string (lambda () help-string)]
	[set-help-string (entry-point
			  (lambda (s) 
			    (check-label-string/false '(method labelled-menu-item<%> set-help-string) s)
			    (set! help-string (and s (string->immutable-string s)))
			    (when in-menu?
			      (send wx-parent set-help-string (send wx id) help-string))))]
	[enable (lambda (on?) (do-enable on?))]
	[is-enabled? (lambda () enabled?)]
	[restore (entry-point
		  (lambda ()
		    (unless shown?
		      (if in-menu?
			  (begin
                            (if wx-submenu
				(send wx-parent append (send wx id) label wx-submenu help-string)
				(send wx-parent append (send wx id) label help-string checkable?))
			    (send wx-parent append-item this wx))
			  (send wx-parent append-item this wx-submenu (strip-tab label)))
		      (send wx set-enabled #t) ; re-added item is initially enabled at wx level
		      (set! shown? #t)
		      (do-enable enabled?)
                      (post-restore))))]
	[delete (entry-point
		 (lambda ()
		   (when shown?
                     (pre-delete)
		     (if in-menu?
			 (send wx-parent delete (send wx id) this)
			 (send wx-parent delete-item this))
		     (set! shown? #f))))]
	[is-deleted? (lambda () (not shown?))])
      (sequence
	(as-entry
	 (lambda ()
	   (when help-string
	     (set! help-string (string->immutable-string help-string)))
	   (set! wx (set-wx (make-object wx-menu-item% this (mcons label #f) #t)))
	   (set! wx-parent (send (mred->wx parent) get-container))
	   (super-init wx)
	   (when keymap (send wx set-keymap keymap))))
	(restore))))

  (define (char-name c print?)
    (case c
      [(#\return) (if (eq? (system-type) 'macos) "Return" "Enter")]
      [(#\tab) "Tab"]
      [(#\space) "Space"]
      [(#\backspace) "Backspace"]
      [(#\rubout) "Delete"]
      [(#\:) (if print? ":" "Colon")]
      [(#\;) (if print? ";" "Semicolon")]
      [else c]))

  (define key-code->keymap-name #hasheq((prior . #"pageup")
					(next . #"pagedown")
					(escape . #"esc")))

  (define (check-shortcut who c)
    (unless (or (not c) 
		(char? c)
		(and (symbol? c)
		     (wx:key-symbol-to-menu-key c)))
      (raise-type-error (who->name who) "character, key-code symbol, or #f" c)))

  (define (check-shortcut-prefix who p)
    (unless (and (list? p)
		 (andmap (lambda (i)
			   (memq i '(meta alt cmd shift option ctl)))
			 p)
		 (let loop ([p p])
		   (cond
		    [(null? p) #t]
		    [(memq (car p) (cdr p)) #f]
		    [else (loop (cdr p))])))
      (raise-type-error (who->name who)
			"list of unique symbols: 'shift, 'meta, 'alt, 'cmd, 'option, and 'ctl" 
			p))
    (let ([disallowed (case (system-type)
			[(unix) '(cmd option)]
			[(windows) '(cmd option meta)]
			[(macosx) '(meta alt)])])
      (for-each (lambda (i)
		  (when (memq i p)
		    (raise-mismatch-error (who->name who)
					  "prefix not supported for the current platform: "
					  i)))
		disallowed)
      (when (eq? 'unix (system-type))
	(when (and (memq 'meta p)
		   (memq 'alt p))
	  (raise-mismatch-error (who->name who)
				"prefix contains both 'meta and 'alt: "
				p)))))

  (define default-prefix
    (case (system-type)
      [(unix) (list default-x-prefix)]
      [(windows) (list 'ctl)]
      [(macosx) (list 'cmd)]))

  (define (get-default-shortcut-prefix)
    default-prefix)

  (define basic-selectable-menu-item%
    (class100* basic-labelled-menu-item% (selectable-menu-item<%>) (lbl checkable? mnu cb shrtcut help-string set-wx 
									demand-callback shrtcut-prefix
                                                                        on-pre-delete on-post-restore)
      (inherit is-enabled?)
      (rename [super-restore restore] [super-set-label set-label]
	      [super-is-deleted? is-deleted?]
	      [super-is-enabled? is-enabled?]
	      [super-get-label get-label])
      (private-field
       [menu mnu]
       [callback cb]
       [label lbl]
       [shortcut shrtcut]
       [wx #f])
      (public
	[command (lambda (e)
		   (check-instance '(method selectable-menu-item<%> command) wx:control-event% 'control-event% #f e)
		   (void (callback this e)))])
      (private-field
        [prefix shrtcut-prefix])
      (private
	[calc-labels (lambda (label)
		       (let* ([new-label (if shortcut
					     (string-append
					      (strip-tab label)
					      (case (system-type)
						[(unix windows)
						 (format "~a~a~a~a~a~a" #\tab 
							 (if (memq 'ctl prefix) "Ctrl+" "")
							 (if (memq 'shift prefix) "Shift+" "")
							 (if (memq 'meta prefix) "Meta+" "")
							 (if (memq 'alt prefix) "Alt+" "")
							 (if (symbol? shortcut)
							     (wx:key-symbol-to-menu-key shortcut)
							     (char-name
							      (char-upcase shortcut)
							      #t)))]
						[(macosx) 
						 (format "\tCut=~a~a"
							 (integer->char
							  (+ (if (memq 'shift prefix) 1 0)
							     (if (memq 'option prefix) 2 0)
							     (if (memq 'ctl prefix) 4 0)
							     (if (memq 'cmd prefix) 0 8)
							     (char->integer #\A)))
							 (if (char? shortcut)
							     (char->integer (char-upcase shortcut))
							     (wx:key-symbol-to-menu-key shortcut)))]))
					     (strip-tab label))]
			      [key-binding (and shortcut
						(let ([base (if (symbol? shortcut)
								(hash-table-get key-code->keymap-name shortcut (lambda () shortcut))
								(char-name (char-downcase shortcut) #f))]
						      [exact (if (or (symbol? shortcut)
								     (and (char-alphabetic? shortcut)
									  ((char->integer shortcut) . < . 128))
								     (char-numeric? shortcut))
								 ":"
								 "")])
						  (case (system-type)
						    [(unix windows) (format "~a~a~a~a?:~a" 
									    exact
									    (if (memq 'shift prefix) "s:" "")
                                                                            (if (or (memq 'meta prefix)
                                                                                    (memq 'alt prefix))
                                                                                "m:" "~m:")
									    (if (memq 'ctl prefix) "c:" "")
									    base)]
						    [(macosx) (format "~a~a~a~a~a?:~a" 
								      exact
								      (if (memq 'shift prefix) "s:" "")
								      (if (memq 'cmd prefix) "d:" "")
								      (if (memq 'ctl prefix) "c:" "")
								      (if (memq 'option prefix) "a:" "")
								      base)])))]
			      [keymap (and key-binding
					   (let ([keymap (make-object wx:keymap%)])
					     (send keymap add-function "menu-item" 
						   ;; keymap function callback already in exit mode:
						   (lambda (edit event)
						     (if (is-enabled?)
                                                         (begin
                                                           (when (this . is-a? . checkable-menu-item%)
                                                             (begin
                                                               (send this check (not (send this is-checked?)))))
                                                           (callback this (make-object wx:control-event% 'menu)))
							 (wx:bell))))
					     (send keymap map-function key-binding "menu-item")
					     keymap))])
			 (values new-label keymap)))])
      (private
	[do-set-label (entry-point
		       (lambda (l)
			 (check-label-string '(method labelled-menu-item<%> set-label) l)
			 (let-values ([(new-label keymap) (calc-labels l)])
			   (set! label (string->immutable-string l))
			   (super-set-label new-label)
			   (if (super-is-deleted?)
			       (send wx set-keymap keymap)
			       (send wx swap-keymap menu keymap)))))])
      (override
	[get-label (lambda () label)]
	[set-label (lambda (s) (do-set-label s))])
      (public
	[set-shortcut (lambda (c) 
			(check-shortcut '(method selectable-menu-item<%> set-shortcut) c)
			(unless (equal? shortcut c)
			  (set! shortcut c) 
			  (do-set-label label)))]
	[get-shortcut (lambda () shortcut)]
	[get-shortcut-prefix (lambda () prefix)]
	[set-shortcut-prefix (lambda (p) 
			       (check-shortcut-prefix '(method selectable-menu-item<%> set-x-shortcut-prefix) p)
			       (set! prefix p) (do-set-label label))])
      (sequence
	(set! label (string->immutable-string label))
	(let-values ([(new-label keymap) (calc-labels label)])
	  (super-init menu new-label help-string #f checkable? keymap (lambda (x) (set! wx x) (set-wx x)) demand-callback
                      on-pre-delete on-post-restore)))))

  (define (check-shortcut-args who label menu callback shortcut help-string demand-callback shortcut-prefix)
    (let ([cwho `(constructor ,who)])
      (check-label-string cwho label)
      (menu-parent-only who menu)
      (check-callback cwho callback)
      (check-shortcut cwho shortcut)
      (check-label-string/false cwho help-string)
      (check-callback1 cwho demand-callback)
      (check-shortcut-prefix cwho shortcut-prefix)))

  (define menu-item%
    (class100 basic-selectable-menu-item% (label parent callback [shortcut #f] [help-string #f] [demand-callback void] 
						 [shortcut-prefix default-prefix])
      (sequence 
	(check-shortcut-args 'menu-item label parent callback shortcut help-string demand-callback shortcut-prefix)
	(super-init label #f parent callback shortcut help-string (lambda (x) x) demand-callback shortcut-prefix
                    void void))))

  (define checkable-menu-item%
    (class100 basic-selectable-menu-item% (label parent callback [shortcut #f] [help-string #f] [demand-callback void] 
						 [checked #f] [shortcut-prefix default-prefix])
      (sequence
	(check-shortcut-args 'checkable-menu-item label parent callback shortcut help-string demand-callback shortcut-prefix))
      (private-field
       [mnu parent]
       [wx #f]
       [was-checked? #f])
      (public
	[check (entry-point (lambda (on?) (send (send (mred->wx mnu) get-container) check (send wx id) on?)))]
	[is-checked? (entry-point (lambda () (send (send (mred->wx mnu) get-container) checked? (send wx id))))])
      (sequence
	(super-init label #t mnu callback shortcut help-string (lambda (x) (set! wx x) x) demand-callback shortcut-prefix
                    (lambda () (set! was-checked? (is-checked?)))
                    (lambda () (check was-checked?)))
	(when checked (check #t)))))

  (define menu%
    (class100* basic-labelled-menu-item% (menu-item-container<%> internal-menu<%>) (label parent [help-string #f] [demand-callback void])
      (private-field 
       [callback demand-callback])
      (sequence 
	(check-label-string '(constructor menu) label)
	(menu-or-bar-parent 'menu parent)
	(check-label-string/false '(constructor menu) help-string)
	(check-callback1 '(constructor menu) demand-callback))
      (public
	[get-items (entry-point (lambda () (send wx-menu get-items)))])
      (override
	[on-demand (lambda ()
		     (callback this)
		     (for-each
		      (lambda (i) 
			(when (is-a? i labelled-menu-item<%>)
			  (send i on-demand)))
		      (send wx-menu get-items)))])
      (private-field
       [wx-menu #f])
      (sequence
	(as-entry
	 (lambda () 
	   (set! wx-menu (make-object wx-menu% this #f void #f))
	   (super-init parent label help-string wx-menu #f (send wx-menu get-keymap) (lambda (x) x) void void void)
	   (let ([wx-item (mred->wx this)])
	     (set-mcdr! (send wx-item get-menu-data) wx-menu) ; for meta-shortcuts
	     (send wx-item set-wx-menu wx-menu)))))))

  (define menu-bar%
    (class100* mred% (menu-item-container<%>) (parent [demand-callback void])
      (sequence 
	(unless (or (is-a? parent frame%) (eq? parent 'root))
	  (raise-type-error (constructor-name 'menu-bar) "frame% object or 'root" parent))
	(check-callback1 '(constructor menu-bar) demand-callback)
	(if (eq? parent 'root)
	    (unless (current-eventspace-has-menu-root?)
	      (raise-mismatch-error (constructor-name 'menu-bar) "no menu bar allowed in the current eventspace for: " parent))
	    (when (as-entry (lambda () (send (mred->wx parent) get-the-menu-bar)))
	      (raise-mismatch-error (constructor-name 'menu-bar) "the specified frame already has a menu bar: " parent))))
      (private-field 
       [callback demand-callback]
       [prnt (if (eq? parent 'root)
		 (begin
		   (as-entry
		    (lambda ()
		      (when root-menu-frame-used?
			(raise-mismatch-error (constructor-name 'menu-bar) "already has a menu bar: " parent))
		      (set! root-menu-frame-used? #t)))
		   root-menu-frame)
		 parent)]
       [wx #f]
       [wx-parent #f]
       [shown? #f])
      (public
	[get-frame (lambda () prnt)]
	[get-items (entry-point (lambda () (send wx get-items)))]
	[enable (entry-point (lambda (on?) (send wx enable-all on?)))]
	[is-enabled? (entry-point (lambda () (send wx all-enabled?)))]
	[on-demand (lambda ()
		     (callback this)
		     (for-each
		      (lambda (i) (send i on-demand))
		      (send wx get-items)))])
      (sequence
	(as-entry
	 (lambda ()
	   (set! wx (make-object wx-menu-bar% this))
	   (set! wx-parent (mred->wx prnt))
	   (super-init wx)
	   (send wx-parent set-menu-bar wx)
	   (send wx-parent self-redraw-request))))))

  (define (menu-parent-only who p)
    (unless (is-a? p internal-menu<%>)
      (raise-type-error (constructor-name who) "parent menu% or popup-menu% object" p)))

  (define (menu-or-bar-parent who p)
    (unless (or (is-a? p internal-menu<%>) (is-a? p menu-bar%))
      (raise-type-error (constructor-name who) "built-in menu-item-container<%> object" p))))

culture
=======

How To Ask Questions The Smart Way
https://zhuanlan.zhihu.com/p/19779979

The Cathedral and the Bazaar
https://www.ruanyifeng.com/blog/2008/02/notes_on_the_cathedral_and_the_bazaar.html
http://www.catb.org/~esr/writings/cathedral-bazaar/cathedral-bazaar/

ruby
====

## introduction
man pry  # for trying out code snippets below
https://learnxinyminutes.com/docs/ruby/
https://github.com/ThibaultJanBeyer/cheatsheets/blob/master/Ruby-Cheatsheet.md
https://www.vikingcodeschool.com/professional-development-with-ruby/ruby-cheat-sheet
http://www.cheat-sheets.org/saved-copy/RubyCheat.pdf  # skip the cryptic "Predefined Variables" and "Ruby arguments" tables
http://www.testingeducation.org/conference/wtst3_pettichord9.pdf

https://www.ruby-lang.org/en/documentation/ruby-from-other-languages/to-ruby-from-python/

## API
man ri
http://overapi.com/ruby

### example: ri system
	=== Implementation from Kernel
	------------------------------------------------------------------------
	  system([env,] command... [,options])    -> true, false or nil

	------------------------------------------------------------------------

	Executes command... in a subshell.
	command... is one of following forms.

	  commandline                 : command line string which is passed to the standard shell
	  cmdname, arg1, ...          : command name and one or more arguments (no shell)
	  [cmdname, argv0], arg1, ... : command name, argv[0] and zero or more arguments (no shell)

	system returns true if the command gives zero exit status, false for non
	zero exit status. Returns nil if command execution fails. An error
	status is available in $?. The arguments are processed in the same way
	as for Kernel.spawn.

	The hash arguments, env and options, are same as exec and spawn. See
	Kernel.spawn for details.

	  system("echo *")
	  system("echo", "*")

	produces:

	  config.h main.rb
	  *

	See Kernel.exec for the standard shell.
	......

## coding style
https://rubystyle.guide/
https://ruby-china.org/wiki/coding-style

## resources
https://github.com/markets/awesome-ruby

## debug
https://github.com/deivid-rodriguez/pry-byebug
https://github.com/JoshCheek/seeing_is_believing


crystal
=======

https://getgood.at/in-a-day/crystal
https://crystal-lang.org/2018/01/08/top-5-reasons-for-ruby-ists-to-use-crystal.htmL

/c/crystal/crystal/src/
https://crystal-lang.org/api
https://crystal-lang.org/reference

https://github.com/veelenga/awesome-crystal
https://github.com/DocSpring/ruby_crystal_codemod


shell
=====

Linux 的概念与体系
https://www.cnblogs.com/vamei/archive/2012/10/10/2718229.html

man bash
https://devhints.io/bash
https://github.com/denysdovhan/bash-handbook/blob/master/translations/zh-CN/README.md

https://juejin.im/post/5e4123e3e51d45271515501f
https://juejin.im/post/5e42858de51d45270d53022e

https://shellmagic.xyz/
https://ngte-ac.gitbook.io/i/infrastructure/linux-command-cheatsheet
https://github.com/jlevy/the-art-of-command-line/blob/master/README-zh.md

https://google.github.io/styleguide/shellguide.html

## zsh keys (customized)

	ctrl-p		history-beginning-search-backward
	ctrl-n		history-beginning-search-forwardd
	alt-p		history-search-backward
	alt-n		history-search-forward
	alt-.		insert-last-word
	alt-<space>	vi-cmd-mode

	alt-f		forward-word
	alt-b		backward-word
	ctrl-a		beginning-of-line
	ctrl-e		end-of-line

	bindkey		show all key bindings

python
======

https://learnxinyminutes.com/docs/python/


Vim
===

https://www.jianshu.com/p/bcbe916f97e1
https://coolshell.cn/articles/5426.html
https://devhints.io/vim

## vim keys (customized)

	F2  		toggle number/cursorline
	F3  		toggle spell check
	F4  		toggle paste/nowrap
	F10/F11  	prev/next color scheme
	g.		search in subdir
	g/		search whole git repo
	alt-n/p		next/prev search result
	ctrl-n/p	next/prev file
	ctrl-j/k	left/right buffer
	<Tab>     	next buffer
	alt-c		toggle comment

Tmux
====

## tmux keys (customized)

	ctrl-s ?	list-keys
	ctrl-s c	create new window
	ctrl-s x	kill-pane
	alt-j/k		switch to left/right window
	alt-1/2/3... 	switch to the 1st, 2nd, 3rd, ... window
	ctrl-s ctrl-u   page up (press ctrl-u to continue paging up, <Enter> to exit)
	ctrl-s [/]	copy-mode/paste-buffer
	shift-(left mouse button/right mouse button) copy/paste to/from system clipboard

Mutt
====

http://www.ctex.org/documents/shredder/mutt_frame.html  # enough to read the 1st section

## mutt keys (customized)

Check /etc/mutt/key.muttrc for our customized key bindings.
Type "?" in mutt will show you the complete key bindings.
The most used ones are:

	g       	reply to all recipients
	m       	compose a new mail message
	j/k		move up/down one line
	-/<space>	move up/down one page
	ctrl-u/ctrl-d	move up/down half page
	9/G		move to bottom
	0		move to top
	<Tab>		next-unread
	/		search
	l		limit
	i		limit: toggle to me/all

	# for committer
	a		apply patch
	p		apply patch + git push


Regular Expression
==================

Regular expression is powerful but cryptic.
The right way is to learn by examples:
https://www.rubyguides.com/2015/06/ruby-regex/

ri Regexp
https://cheatography.com/davechild/cheat-sheets/regular-expressions/


Docker
======

https://ngte-ac.gitbook.io/i/infrastructure/docker-cheatsheet


Git
===

http://justinhileman.info/article/git-pretty/git-pretty.png
https://github.com/k88hudson/git-flight-rules/blob/master/README_zh-CN.md
https://github.com/521xueweihan/git-tips
https://github.com/arslanbilal/git-cheat-sheet/blob/master/other-sheets/git-cheat-sheet-zh.md
https://www.codementor.io/@citizen428/git-tutorial-10-common-git-problems-and-how-to-fix-them-aajv0katd
http://www.columbia.edu/~zjn2101/intermediate-git/
https://git-scm.com/book/zh/v2

## resolve conflicts

https://githowto.com/resolving_conflicts
https://easyengine.io/tutorials/git/git-resolve-merge-conflicts/

## edit emailed patch then apply

in mutt: alt-e to open full email in vim

in vim: modify the raw patch and save it
        ctrl-g to show the full file name (at bottom line)

in shell: copy & paste the full file name to command

        git am /tmp/FILE

btw, quilt and wiggle are also good patch tools.

Markdown
========

https://guides.github.com/pdfs/markdown-cheatsheet-online.pdf
https://shd101wyy.github.io/markdown-preview-enhanced/#/zh-cn/
http://support.typora.io/Draw-Diagrams-With-Markdown/


YAML
====

https://yaml.org/YAML_for_ruby.html
https://alexharv074.github.io/puppet/2020/03/06/why-erb-should-be-preferred-to-jinja2-for-devops-templating.html

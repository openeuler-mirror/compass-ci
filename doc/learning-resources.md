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

man bash
https://devhints.io/bash
https://github.com/denysdovhan/bash-handbook/blob/master/translations/zh-CN/README.md

https://shellmagic.xyz/
https://ngte-ac.gitbook.io/i/infrastructure/linux-command-cheatsheet
https://github.com/jlevy/the-art-of-command-line/blob/master/README-zh.md
https://github.com/macrozheng/mall/blob/master/document/reference/linux.md


python
======

https://learnxinyminutes.com/docs/python/


Vim
===

https://devhints.io/vim


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

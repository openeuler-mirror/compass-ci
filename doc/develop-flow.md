document-driven development
===========================

For trivial ideas that take less than 1 day to implement, feel free to just
do it and submit patches.

For unsure/larger ideas, please announce and discuss it first:
- submit RFC idea/patch with document, comment and/or skeleton code;
- submit TODO which can be implemented by anyone

It's also possible to embed TODO/FIXME items in comments, so that others may
jump in and help with your current work.

Sometimes test specs serve as good document, too.

All in all, we encourage document-driven development. It's a good way to make
sure ealy design ideas are valid, clear enough, and everyone are aligned with
the plan. They also serve as good resources for the community to understand
core ideas behind current code, what's going on and where to contribute.

todo repo
=========

	git clone file:///c/todo.git

The formal TODOs shall be committed to the above "todo" repo.
Anyone can create TODO items in markdown doc format for review and implement by others.

- top level directory holds TODOs for the whole team
- dirs data/ deploy/ lkp/ scheduler/ tests/ hold TODOs for specific areas

- to take a TODO for implementation, one should

	git pull --rebase
	git mv some_todo.md people/myname/todo/
	git commit -a
	gmail

- to mark a TODO as done

	git pull --rebase
	git mv people/myname/todo/some_todo.md people/myname/done/some_todo.md
	git commit people/myname
	gmail

To make "--rebase" the default behavior:

	git config --global pull.rebase true

review process
==============

The above "gmail" command is a wrapper for "git send-email".
It submits your patch for review. The patch subject and changelog
should be well written according to suggestions here:

	https://github.com/thoughtbot/dotfiles/blob/master/gitmessage
	https://www.cnblogs.com/cpselvis/p/6423874.html

	http://www.ozlabs.org/~akpm/stuff/tpp.txt
	2: Subject:
	3: Attribution
	4: Changelog

	https://www.kernel.org/doc/html/latest/translations/zh_CN/process/submitting-patches.html#cn-describe-changes
	2) 描述你的改动
	3) 拆分你的改动
	8）回复评审意见

Everyone is encouraged to review others' patches. In particular, these 2 roles
are obliged to give review comments:

- pair programming teammate
- subsystem committer

A patch may undergo several rounds of revisions and reviews before being
considered OK. It's up to the subsystem committer to apply and push code
to the mainline.

tech discussions
================

Technical discussions can happen in 2 main ways
- text messages
- voice talks

All text based discussions shall happen in mailing list. Prefer mutt email
client over outlook. Prefer point-to-point bottom-posting. Every point should
have clear and informative response.

Phone meeting links should better be posted publicly, so that anyone interested
can take part in. It's good to have text meeting minutes published if important
decisions are made in the phone call. Meetings should be effective, with
written minutes and actions.

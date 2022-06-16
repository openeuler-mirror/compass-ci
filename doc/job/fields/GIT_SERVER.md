# meaning
use $GIT_SERVER direct to new git remote repo 

# how to use it
on Compass-CI, git remote repo service is provided by git-daemon container.

user should use $GIT_SERVER direct to git remote repo at lkp-tests/(tests/setup/daemon, and pkg/*/PKGBUILD) script.
```
you can use it like this：

    cat >> /etc/gitconfig <<-EOF
        [url "git://$GIT_SERVER/gitee.com"]
            insteadOf=https://gitee.com
    EOF

or
    git config --system url."git://${GIT_SERVER}/".insteadOf https://

or directly download by
    git clone git://$GIT_SERVER/**.git
```

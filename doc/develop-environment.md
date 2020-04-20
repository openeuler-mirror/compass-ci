# ssh

```bash
# in your local laptop
cat >> ~/.ssh/config <<EOF
Host crystal
  Hostname 124.90.34.227
  Port 22113
EOF

[ -f ~/.ssh/id_rsa.pub ] || ssh-keygen
ssh-copy-id crystal
```

```bash
# in crystal server
cat >> ~/.ssh/config <<EOF
Host alpine
  Hostname localhost
  Port 2200
  User team

Host debian
  Hostname localhost
  Port 2201
  User team
EOF
```

# vim

```bash
git clone https://github.com/rhysd/vim-crystal
cd vim-crystal
cp -R autoload ftdetect ftplugin indent plugin syntax ~/.vim/
```

# vscode

plugins
- crystal
- crystal language server
  https://github.com/crystal-lang-tools/scry.git
- markdown
  https://shd101wyy.github.io/markdown-preview-enhanced/

# crystal
 
## arm build environment in docker
We created an alpine docker for running crystal compiler.
It's the only convenient way to use crystal in aarch64.
Usage:
```
ssh crystal # the devops Kunpeng server
ssh alpine  # the docker
```

## development tips

Ruby => Crystal code conversion
https://github.com/DocSpring/ruby_crystal_codemod

Interactive console like Ruby's irb/pry
https://github.com/crystal-community/icr

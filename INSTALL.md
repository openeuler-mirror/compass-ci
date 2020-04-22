
# debian packages

```bash
sudo apt-get install docker.io
```

# openEuler packages

```bash
sudo dnf install docker
```

# Common setup (per-user)

```bash
# git clone https://gitee.com/openeuler/crystal-ci.git
# For now, hosted in crystal server:
git clone file:///c/crystal-ci.git
# or clone from your laptop:
git clone ssh://crystal/c/crystal-ci.git

cd crystal-ci
echo "export CCI_SRC=$PWD" >> $HOME/.${SHELL##*/}rc
```

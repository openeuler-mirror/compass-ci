# Install lkp-tests and its depends in container.
# With docker container, will suit most of the linux OSes.
# Avoid much repetitive testing work to adapt various OSes.

Prepare work:
  apply account
  config default yaml
  generate ssh keys

Installation:
  git clone https://gitee.com/openeuler/compass-ci.git

    cd compass-ci/container/submit
    ./build

  Add soft link for executable file 'submit' to $PATH:

    ln -s $PWD/submit /usr/bin/submit

Usage:
  You can directly use the command 'submit' to submit jobs.
  It's the same as you install the lkp-tests at your local host.

  Example:

    submit -c -m testbox=vm-2p8g borrow-1h.yaml

# Preface

We provide a docker container to suit various of Linux OS(es).
In this case you do not need to install the lkp-tests to your local server.
Also you can avoid installation failures from undesired dependency package(s).

# Prepare

  Do on your local server:

    - install docker
    - apply account and config default yaml
    - generate ssh key(s)

# build container

## 1. download resource

    Download lkp-tests and compass-ci to your local server.

    Command(s):

        git clone https://gitee.com/wu_fengguang/compass-ci.git
        git clone https://gitee.com/wu_fengguang/lkp-tests.git

## 2. add environment variable(s)

    Command(s):

        echo "export LKP_SRC=$PWD/lkp-tests" >> ~/.${SHELL##*/}rc
        echo "export CCI_SRC=$PWD/compass-ci" >> ~/.${SHELL##*/}rc
        source ~/.${SHELL##*/}rc

## 3. build docker image

    Command(s):

        cd compass-ci/container/submit
        ./build

## 4. add executable file

    Command(s):

        ln -s $CCI_SRC/container/submit/submit /usr/bin/submit

# try it

    instruction:

        You can directly use the command 'submit' to submit jobs.
        It is the same as you install the lkp-tests on your own server.
        It will start a disposable container to submit your job.
        The container will attach the directory lkp-tests to the container itself.
        You can edit the job yaml(s) in lkp-tests/jobs and it will take effect when you submit jobs.

    Example:

        submit -c -m testbox=vm-2p8g borrow-1h.yaml

    About submit:

        For detailed usage for command submit, please reference to: [submit user manual](https://gitee.com/wu_fengguang/compass-ci/blob/master/doc/manual/submit-job.en.md)

#!/bin/bash

check() {
    return 0
}

depends() {
    # We do not depend on any modules - just some root
    return 0
}

# called by dracut
installkernel() {
    return 0
}

install() {
    inst_hook pre-pivot 10 "$moddir/lkp-deploy.sh"
}

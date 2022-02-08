# nix

Nix is a powerful package manager for Linux and other Unix systems, making package management reliable and reproducible.

It provides upgrades and rollbacks, parallel installation of multiple versions of packages, and multi-user package management, and easy setup of build environments.

The installation is only allowed for non-root user.
For single-user mode installation, the nix related commands will be only allowed for the installation user, also the installed command will only be available for the installation user.

For multi-user mode installation, any user can run the nix related commands. The command nix related are allowed for all user. Commands installed by root are allowed for all user, but commands installed by non-root user are allowed only for themself.

For more detailed usage for nix, reference the official document website:
  https://nixos.org/manual/nix/stable

## nix deployment prepare

add sudo permission for the installation user:
  It is forbidden to use root to install the nix, we need a common user to install it with sudo, to use an existing user or create a new one and add it to the sudo list.

## Installation

Use domestic software website instead of the official website:
  use: https://mirrors.tuna.tsinghua.edu.cn/nix/latest/install
  instead of: https://nixos.org/nix/install
  
  for multi-user mode:
    command: sh <(curl https://mirrors.tuna.tsinghua.edu.cn/nix/latest/install) --daemon

  for single-user mode:
    command: sh <(curl https://mirrors.tuna.tsinghua.edu.cn/nix/latest/install)

Case meet nix installation failures, do some clean before the next installation:

clean command:
  - find /etc | grep backup-before-nix | xargs rm -rf
  - rm -rf /nix

## Add new channel for installing packages
Add demotic nixpkgs channel:
  new channel: 
    - https://mirrors.tuna.tsinghua.edu.cn/nix-channels/nixpkgs-unstable/
    - https://mirrors.ustc.edu.cn/nix-channels/nixpkgs-unstable/

  add channel command:
    nix-channel --add channel_url channel_name
    example:
      - nix-channel --add https://mirrors.tuna.tsinghua.edu.cn/nix-channels/nixpkgs-unstable nixpkgs
      - nix-channel --update

  check current channels command:
    - nix-channel --list

## installing packages

Case you use the default channel, use:
  nix-env -i package_name
  example:
    nix-env -i shellcheck

Case you use the added channel, use:
  nix-env -iA channel_name.package_name
  example:
    - nix-env -iA nixpkgs.shellcheck

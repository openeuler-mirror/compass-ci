#!/usr/bin/env bash

# Function to check if the user is root
is_root() {
    [ "$(id -u)" -eq 0 ]
}

# Detect the Linux distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}

# Detect the available package manager
detect_pkg_manager() {
    if command -v apt-get > /dev/null 2>&1; then
        echo "apt-get"
    elif command -v dnf > /dev/null 2>&1; then
        echo "dnf"
    elif command -v yum > /dev/null 2>&1; then
        echo "yum"
    elif command -v pacman > /dev/null 2>&1; then
        echo "pacman"
    elif command -v zypper > /dev/null 2>&1; then
        echo "zypper"
    else
        echo "unknown"
    fi
}

# Install dependencies based on the distribution or detected package manager
install_dependencies() {
    local distro=$1
    local pkg_manager=""
    local install_cmd=""

    shift
    local packages="$@"

    case $distro in
        debian|ubuntu)
            pkg_manager="apt-get"
            install_cmd="install -y"
            ;;
        openEuler|fedora)
            pkg_manager="dnf"
            install_cmd="install -y"
            ;;
        arch)
            pkg_manager="pacman"
            install_cmd="-S --noconfirm"
            ;;
        opensuse-leap|opensuse-tumbleweed|sles)
            pkg_manager="zypper"
            install_cmd="install -y"
            ;;
        *)
            echo "Unsupported Linux distribution: $distro"
            echo "Attempting to auto-detect package manager..."
            pkg_manager=$(detect_pkg_manager)
            if [ "$pkg_manager" = "unknown" ]; then
                echo "No known package manager found. Please install dependencies manually."
                exit 1
            else
                echo "Detected package manager: $pkg_manager"
                case $pkg_manager in
                    apt-get|dnf|yum|zypper)
                        install_cmd="install -y"
                        ;;
                    pacman)
                        install_cmd="-S --noconfirm"
                        ;;
                esac
            fi
            ;;
    esac

    # Use sudo if the user is not root
    if ! is_root; then
        SUDO="sudo"
    else
        SUDO=""
    fi

    # Install packages
    echo "Installing $packages using $pkg_manager $install_cmd"
    $SUDO $pkg_manager $install_cmd $packages

    if [ $? -eq 0 ]; then
        echo "Successfully installed $packages"
    else
        echo "Failed to install $packages"
        exit 1
    fi
}

# Main script logic
DISTRO=$(detect_distro)
install_dependencies "$DISTRO" crystal shards cscope

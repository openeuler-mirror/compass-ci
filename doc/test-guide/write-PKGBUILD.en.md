# PKGBUILD

A PKGBUILD is a shell script. makepkg uses the instructions contained in PKGBUILD to generate a software package that incorporates binary files and installation instructions.

# What Does PKGBUILD Include?

PKGBUILD includes variables and functions.

## Defining a Variable

- pkgname: Mandatory. It indicates the name of a software package.
- pkgver: Mandatory. It indicates the version of a software package.
- pkgrel: Mandatory. It indicates the release number of a software package.
- arch: Mandatory. It indicates the architecture sequence of a software package.
- depends: Optional. It indicates the name of the dependency package required for running a software test.
- makedepends: Optional. It indicates the name of the dependency package required for building a software package.
- source: Optional. It indicates the list of files required for building a software package.
- md5sums: Optional. It indicates the MD5 hash value of each source file to verify the integrity of the source file during the build process.

## Defining a Function

- package function

  Mandatory. It is used for installing files to the directory that will be the root directory of the build package.

- prepare function

  Optional. It is used for executing the operation of building source code.

- build function

  Optional. It is used for compiling and/or building source code.

- check function

  Optional. It is used for running the test suite of the program package.

> ![](../icons/icon-notice.gif) **Notice**
>
> **srcdir** is the directory for extracting or copying source files. All packaging functions run in the **srcdir** directory. **pkgdir** is the root directory for building software packages and is used only in the package function.

# How do i write PKGBUILD?

1. Read official documents:

- [PKGBUILD(5) Manual Page](https://www.archlinux.org/pacman/PKGBUILD.5.html)
- [pkgbuild demo](https://git.archlinux.org/pacman.git/plain/proto/PKGBUILD.proto)

2. Create **PKGBUILD** file with vim or other editor. The following is an example of the **PKGBUILD** file:

```shell
pkgname=zstd
pkgver=1.4.4
pkgrel=2
arch=('i686' 'x86_64' 'aarch64')
url='https://github.com/facebook/zstd'
license=('custom:BSD3' 'GPL2')
depends=('xz' 'zlib' 'lz4')
makedepends=('git')
source=('git://github.com/facebook/zstd.git#branch=dev')
md5sums=('SKIP')

pkgver() {
	cd "$srcdir/$pkgname"
	git describe --long --tags | sed 's/\([^-]*-g\)/r\1/;s/-/./g;s/^v//g'
}

build() {
	cd "$srcdir/$pkgname"
	make
	make -C contrib/pzstd
}

package() {
	cd "$srcdir/$pkgname"
	make PREFIX="/usr" DESTDIR="$pkgdir/" install
	install -D -m755 contrib/pzstd/pzstd "$pkgdir/usr/bin/pzstd"
	install -D -m644 LICENSE "${pkgdir}/usr/share/licenses/${pkgname}/LICENSE"
}
```

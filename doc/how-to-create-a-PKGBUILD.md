# 如何编写PKGBUILD

## PKGBUILD是什么？

   PKGBUILD是一个shell脚本，makepkg通过PKGBUILD中包含的指令，生成包含二进制文件和安装指令的软件包。

## PKGBUILD包含什么？

   PKGBUILD包含两部分内容：变量和函数

   1）、定义变量

	- pkgname: 必须定义，表示软件包的名称;
	- pkgver: 必须定义，表示软件包的版本号；
	- pkgrel: 必须定义，表示软件包的发布号；
	- arch: 必须定义，表示软件包使用的架构序列；
	- depends: 可选字段，软件测试运行时需要的依赖包名称；
	- makedepends: 可选字段，构建软件包时需要的文件列表；
	- source: 可选字段，指定每个源文件的MD5哈希值，用于构建过程中验证源文件的完整性。

   2）、定义函数

	- package函数
	  package函数必须定义，此函数用于将文件安装到将成为构建包的根目录的目录中；
	- prepare函数
	  定义可选的prepare函数，在其中执行用于准备构建源码的操作；
	- build函数
	  定义可选的build函数，用于编译和/或构建源码；
	- check函数
	  定义可选的check函数，用于运行程序包的测试套件。

   注意：srcdir 和 pkgdir

	- srcdir: 提取或复制源文件的目录，所有打包功能都在srcdir目录内部运行；
	- pkgdir: 构建软件包的根目录，仅在package函数中使用。

## 如何编写PKGBUILD？

   1）、创建PKGBUILD，文件名必须以“PKGBUILD”命名。

   `touch PKGBUILD`

   2）、使用vim打开PKGBUILD，编写PKGBUILD文件内容。

   如下我们给出一个PKGBUILD例子：

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

## 参考

   https://www.archlinux.org/pacman/PKGBUILD.5.html
   https://git.archlinux.org/pacman.git/plain/proto/PKGBUILD.proto

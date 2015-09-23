# Maintainer: %s <%s>
pkgname=%s
pkgver=1
pkgrel=1
pkgdesc=\"\"
arch=('i686' 'x86_64')
url=\"\"
license=('GPL')
groups=()
depends=()
makedepends=('git')
provides=()
conflicts=()
replaces=()
backup=()
options=()
install=
source=(\"GITURL\")
noextract=()
_gitname=\"MODENAME\"

pkgver() {
  cd \"$_gitname\"
  printf \"r%s.%s\" $(git rev-list --count HEAD) $(git rev-parse --short HEAD)
}

build() {
  cd \"$srcdir\"/\"$_gitname\"
  ./autogen.sh
  ./configure --prefix=/usr
  make
}

package() {
  cd \"$srcdir/$_gitname\"
  make DESTDIR=\"$pkgdir/\" install
}

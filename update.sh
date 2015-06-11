#!/bin/bash
set -e

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

stage3="$(wget -qO- 'http://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64.txt' | tail -n1 | awk '{print $1}' | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g" )"

if [ -z "$stage3" ]; then
	echo >&2 'wtf failure'
	exit 1
fi

url="http://distfiles.gentoo.org/releases/amd64/autobuilds/$stage3"
name="$(basename "$stage3")"

( set -x; wget -N "$url" )

base="${name%%.*}"
image="gentoo-temp:$base"
container="gentoo-temp-$base"

if [ ! -x /usr/bin/pbzip2 ]; then sudo emerge pbzip2; fi
if [ ! -x /usr/bin/pv ]; then sudo emerge pb; fi
( set -x; pbzip2 -dck "$name" | pv -p | docker import - "$image" )

docker rm -f "$container" > /dev/null 2>&1 || true
( set -x; docker run -t  -e "MAKEOPTS=-j$(( $( nproc ) +1))" -e "EMERGE_DEFAULT_OPTS='--jobs=3'" -v /usr/portage:/usr/portage:ro -v /usr/portage/distfiles:/usr/portage/distfiles --name "$container" "$image" bash -exc $'
	export MAKEOPTS="-j$(nproc)"
	pythonTarget="$(emerge --info | sed -n \'s/.*PYTHON_TARGETS="\\([^"]*\\)".*/\\1/p\')"
	pythonTarget="${pythonTarget##* }"
	echo \'PYTHON_TARGETS="\'$pythonTarget\'"\' >> /etc/portage/make.conf
	echo \'PYTHON_SINGLE_TARGET="\'$pythonTarget\'"\' >> /etc/portage/make.conf
  emerge --newuse --deep --with-bdeps=y @system @world
  emerge -C editor ssh man man-pages openrc e2fsprogs texinfo service-manager
	emerge --depclean
' )

bz2="$base.tar.bz2"
( set -x; docker export "$container" | pbzip2 -z -9 > "$bz2" )

docker rm "$container"
docker rmi "$image"

echo 'FROM scratch' > Dockerfile
echo "ADD $bz2 /" >> Dockerfile
echo 'RUN echo MAKEOPTS=-j$(( $( nproc ) +1)) >> /etc/portage/make.conf' >> Dockerfile
echo 'CMD ["/bin/bash"]' >> Dockerfile

user="$(docker info | awk '/^Username:/ { print $2 }')"
[ -z "$user" ] || user="$user/"
( set -x; docker build -t "${user}gentoo-stage3" . )

( set -x; git add Dockerfile "$bz2" )

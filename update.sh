#!/bin/bash
set -e

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

stage3="$(wget -qO- 'http://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64.txt' | tail -n1)"

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

# bzcat thanks to https://code.google.com/p/go/issues/detail?id=7279
( set -x; bzcat -p "$name" | docker import - "$image" )

docker rm -f "$container" > /dev/null 2>&1 || true
( set -x; docker run -v /usr/portage:/usr/portage:ro --name "$container" "$image" bash -c 'emerge -C editor ssh man man-pages openrc e2fsprogs texinfo service-manager && emerge --depclean' )

xz="$base.tar.xz"
( set -x; docker export "$container" | xz -9 > "$xz" )

docker rm "$container"
docker rmi "$image"

echo 'FROM scratch' > Dockerfile
echo "ADD $xz /" >> Dockerfile
echo 'CMD ["/bin/bash"]' >> Dockerfile

user="$(docker info | awk '/^Username:/ { print $2 }')"
[ -z "$user" ] || user="$user/"
( set -x; docker build -t "${user}gentoo-stage3" . )

( set -x; git add Dockerfile "$xz" )

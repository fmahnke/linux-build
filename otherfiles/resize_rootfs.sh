#!/bin/sh

set -e

if [ "$(id -u)" -ne "0" ]; then
	echo "This script requires root."
	exit 1
fi

set -x

DEVICE=$(df -P $0 | tail -1 | cut -d' ' -f 1 | sed 's/..$//')

resize() {
	set +e
	fdisk ${DEVICE} <<EOF
p
d
n
p
1
2048

a
w
EOF
	set -e

	partx -u ${DEVICE}
	resize2fs ${DEVICE}p1
}

resize

if [ -f /usr/lib/systemd/system/multi-user.target.wants/resize_rootfs.service ]; then
	rm /usr/lib/systemd/system/multi-user.target.wants/resize_rootfs.service
fi

echo "Done!"

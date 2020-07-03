#!/bin/sh

set -e

if [ "$(id -u)" -ne "0" ]; then
	echo "This script requires root."
	exit 1
fi

set -x

DEVICE=$(df -P $0 | tail -1 | cut -d' ' -f 1 | sed 's/..$//')
PART="2"

resize() {
	start=$(fdisk -l ${DEVICE} | grep ${DEVICE}p${PART} | sed 's/*//' | awk '{print $2}')
	echo $start

	set +e
	fdisk ${DEVICE} <<EOF
p
d
2
n
p
2
$start

a
2
w
EOF
	set -e

	partx -u ${DEVICE}
	resize2fs ${DEVICE}p${PART}
}

resize

if [ -f /usr/lib/systemd/system/multi-user.target.wants/resize_rootfs.service ]; then
	rm /usr/lib/systemd/system/multi-user.target.wants/resize_rootfs.service
fi

echo "Done!"

#!/bin/sh

set -x 
set -e

IMAGE_NAME="$1"
IMAGE_SIZE=6000M
SWAP_SIZE=2048 # M

if [ -z "$IMAGE_NAME" ]; then
	echo "Usage: $0 <image name>"
	exit 1
fi

if [ "$(id -u)" -ne "0" ]; then
	echo "This script requires root (not really - but make_image.sh will fail later without root)"
	exit 1
fi

fallocate -l $IMAGE_SIZE $IMAGE_NAME

cat << EOF | fdisk $IMAGE_NAME
o
n
p
1
2048
+${SWAP_SIZE}M
t
82
n
p
2
$((2048+SWAP_SIZE*1024*2))

t
2
83
a
2
w
EOF

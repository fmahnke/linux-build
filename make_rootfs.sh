#!/bin/bash

set -e

BUILD="build"
OTHERDIR="otherfiles"
DEST="$1"
OUT_TARBALL="$2"
BUILD_ARCH=arm64

export LC_ALL=C

if [ -z "$DEST" ] || [ -z "$OUT_TARBALL" ]; then
	echo "Usage: $0 <destination-folder> <destination-tarball>"
	exit 1
fi

if [ "$(id -u)" -ne "0" ]; then
	echo "This script requires root."
	exit 1
fi

DEST=$(readlink -f "$DEST")

if [ ! -d "$DEST" ]; then
	mkdir -p $DEST
fi

if [ "$(ls -A -Ilost+found $DEST)" ]; then
	echo "Destination $DEST is not empty. Aborting."
	exit 1
fi

TEMP=$(mktemp -d)
cleanup() {
	if [ -e "$DEST/proc/cmdline" ]; then
		umount "$DEST/proc"
	fi
	if [ -d "$DEST/sys/kernel" ]; then
		umount "$DEST/sys"
	fi
	umount "$DEST/dev" || true
	umount "$DEST/tmp" || true
	if [ -d "$TEMP" ]; then
		rm -rf "$TEMP"
	fi
}
trap cleanup EXIT

ROOTFS="http://archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"
TAR_OPTIONS=""

mkdir -p $BUILD
TARBALL="$BUILD/$(basename $ROOTFS)"

mkdir -p "$BUILD"
if [ ! -e "$TARBALL" ]; then
	echo "Downloading $DISTRO rootfs tarball ..."
	wget -O "$TARBALL" "$ROOTFS"
fi

# Extract with BSD tar
echo -n "Extracting ... "
set -x
bsdtar -xpf $TAR_OPTIONS "$TARBALL" -C "$DEST"
echo "OK"

# Add qemu emulation.
cp /usr/bin/qemu-aarch64-static "$DEST/usr/bin"
cp /usr/bin/qemu-arm-static "$DEST/usr/bin"

do_chroot() {
	cmd="$@"
	mount -o bind /tmp "$DEST/tmp"
	mount -o bind /dev "$DEST/dev"
	chroot "$DEST" mount -t proc proc /proc
	chroot "$DEST" mount -t sysfs sys /sys
	chroot "$DEST" $cmd
	chroot "$DEST" umount /sys
	chroot "$DEST" umount /proc
	umount "$DEST/dev"
	umount "$DEST/tmp"
}

mv "$DEST/etc/resolv.conf" "$DEST/etc/resolv.conf.dist"
cp /etc/resolv.conf "$DEST/etc/resolv.conf"

cat $OTHERDIR/pacman.conf > "$DEST/etc/pacman.conf"

cp $OTHERDIR/locale.gen "$DEST/etc/locale.gen-all"

mv "$DEST/etc/pacman.d/mirrorlist" "$DEST/etc/pacman.d/mirrorlist.default"

echo "Server = http://sg.mirror.archlinuxarm.org/\$arch/\$repo" > "$DEST/etc/pacman.d/mirrorlist"

echo "danctnix" > "$DEST/etc/hostname"

cat > "$DEST/second-phase" <<EOF
#!/bin/sh
pacman-key --init
pacman-key --populate archlinuxarm
killall -KILL gpg-agent
pacman -Rsn --noconfirm linux-aarch64
pacman -Syu --noconfirm --overwrite=*
pacman -S --noconfirm --overwrite=* --disable-download-timeout --needed dosfstools curl xz iw rfkill netctl dialog wpa_supplicant pv networkmanager device-pine64-pinetab bootsplash-theme-danctnix v4l-utils sudo f2fs-tools zramswap

pacman -S --noconfirm --overwrite=* --disable-download-timeout --needed mesa-git danctnix-phosh-ui-meta xdg-user-dirs noto-fonts-emoji gst-plugins-good

pacman -S --noconfirm --overwrite=* --disable-download-timeout --needed lollypop gedit evince-mobile mobile-config-firefox gnome-calculator gnome-clocks gnome-maps megapixels gnome-usage-mobile gtherm geary-mobile purple-matrix purple-telegram portfolio-fm

systemctl disable sshd

systemctl disable systemd-networkd
systemctl disable systemd-resolved

systemctl enable zramswap
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable phosh
usermod -a -G network,video,audio,optical,storage,input,scanner,games,lp,rfkill,wheel alarm

sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers

cp /etc/locale.gen-all /etc/locale.gen
cd /usr/share/i18n/charmaps
# locale-gen can't spawn gzip when running under qemu-user, so ungzip charmap before running it
# and then gzip it back
gzip -d UTF-8.gz
locale-gen
gzip UTF-8
echo "LANG=en_US.UTF-8" > /etc/locale.conf
yes | pacman -Scc
EOF
chmod +x "$DEST/second-phase"
cp $OTHERDIR/change-alarm $DEST/
do_chroot /second-phase
do_chroot /change-alarm
rm $DEST/second-phase
rm $DEST/change-alarm

# Final touches
rm "$DEST/usr/bin/qemu-aarch64-static"
rm "$DEST/usr/bin/qemu-arm-static"
rm "$DEST/etc/locale.gen-all"
rm -f "$DEST"/*.core
rm "$DEST/etc/resolv.conf.dist" "$DEST/etc/resolv.conf"
touch "$DEST/etc/resolv.conf"

rm "$DEST/etc/pacman.d/mirrorlist"
mv "$DEST/etc/pacman.d/mirrorlist.default" "$DEST/etc/pacman.d/mirrorlist"

sed -e '/default-sample-rate/idefault-sample-rate = 48000' -i "$DEST/etc/pulse/daemon.conf"
sed -e '/alternate-sample-rate/ialternate-sample-rate = 8000' -i "$DEST/etc/pulse/daemon.conf"

cp $OTHERDIR/first_time_setup.sh $DEST/usr/local/sbin/
cp $OTHERDIR/81-blueman.rules $DEST/etc/polkit-1/rules.d/

cp -r $OTHERDIR/systemd/* $DEST/usr/lib/systemd/

mkdir -p $DEST/etc/gtk-3.0
cp $OTHERDIR/gtk3-settings.ini $DEST/etc/gtk-3.0/settings.ini

do_chroot /usr/bin/glib-compile-schemas /usr/share/glib-2.0/schemas

# Replace Arch's with our own mkinitcpio
rm $DEST/etc/mkinitcpio.conf
cp $OTHERDIR/mkinitcpio.conf $DEST/etc/mkinitcpio.conf
cp $OTHERDIR/mkinitcpio-hooks/resizerootfs-hooks $DEST/usr/lib/initcpio/hooks/resizerootfs
cp $OTHERDIR/mkinitcpio-hooks/resizerootfs-install $DEST/usr/lib/initcpio/install/resizerootfs
do_chroot mkinitcpio -p linux-pine64

# Shiny MOTD
cp $OTHERDIR/motd $DEST/etc/motd

echo "Installed rootfs to $DEST"

# Create tarball with BSD tar
echo -n "Creating tarball ... "
pushd .
cd $DEST && bsdtar -czpf ../$OUT_TARBALL .
popd
rm -rf $DEST

set -x
echo "Done"

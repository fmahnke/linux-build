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
sed -i 's|CheckSpace|#CheckSpace|' "$DEST/etc/pacman.conf"

cat >> "$DEST/etc/pacman.conf" <<EOF
[pine64]
SigLevel = Never
Server = https://p64.arikawa-hi.me/pine64/aarch64/

[phosh]
SigLevel = Never
Server = https://p64.arikawa-hi.me/phosh/aarch64/
EOF

cat > "$DEST/second-phase" <<EOF
#!/bin/sh
pacman-key --init
pacman-key --populate archlinuxarm
killall -KILL gpg-agent
pacman -Sy --noconfirm
pacman -Rsn --noconfirm linux-aarch64
pacman -S --noconfirm --disable-download-timeout --needed dosfstools curl xz iw rfkill netctl dialog wpa_supplicant \
	alsa-ucm-pinephone alsa-utils pv linux-pine64 networkmanager uboot-pinephone bootsplash-theme-danctnix \
	rtl8723bt-firmware danctnix-usb-tethering danctnix-eg25-misc dhcp

pacman -S --noconfirm --disable-download-timeout --needed gtk3-mobile mesa-git feedbackd calls chatty phoc phosh kgx \
	squeekboard lollypop gedit gnome-clocks gnome-software-mobile sound-theme-librem5 epiphany gnome-control-center-mobile \
	gnome-keyring purple-matrix gnome-contacts

systemctl disable sshd

systemctl enable usb-tethering
systemctl enable dhcpd4
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable eg25_power
systemctl enable eg25_audio_routing
systemctl enable ModemManager
systemctl enable phosh
usermod -a -G network,video,audio,optical,storage,input,scanner,games,lp,rfkill alarm

sed -i 's|^#en_US.UTF-8|en_US.UTF-8|' /etc/locale.gen
cd /usr/share/i18n/charmaps
# locale-gen can't spawn gzip when running under qemu-user, so ungzip charmap before running it
# and then gzip it back
gzip -d UTF-8.gz
locale-gen
gzip UTF-8
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
rm -f "$DEST"/*.core
mv "$DEST/etc/resolv.conf.dist" "$DEST/etc/resolv.conf"

cp $OTHERDIR/resize_rootfs.sh $DEST/usr/local/sbin/
cp $OTHERDIR/81-blueman.rules $DEST/etc/polkit-1/rules.d/
# Probing gdk pixbuf modules fails on qemu with:
# (process:30790): GLib-ERROR **: 20:53:40.468: getauxval () failed: No such file or directory
# qemu: uncaught target signal 5 (Trace/breakpoint trap) - core dumped
#cp $OTHERDIR/loaders.cache $DEST//usr/lib/gdk-pixbuf-2.0/2.10.0/

# Hide some weird apps that we don't care
mkdir -p $DEST/usr/share/danctnix/applications
cp $OTHERDIR/hidden-apps/* $DEST/usr/share/danctnix/applications/
cp $OTHERDIR/profile.d/danctnix.sh $DEST/etc/profile.d/

cp -r $OTHERDIR/systemd/* $DEST/usr/lib/systemd/system/

mkdir -p $DEST/etc/gtk-3.0
cp $OTHERDIR/gtk3-settings.ini $DEST/etc/gtk-3.0/settings.ini

mkdir -p $DEST/usr/share/glib-2.0/schemas
cp $OTHERDIR/000-archmobile.gschema.override $DEST/usr/share/glib-2.0/schemas
cp $OTHERDIR/osk-wayland $DEST/usr/bin/
cp $OTHERDIR/profile.d/gtk-qt-tweaks.sh $DEST/etc/profile.d/
do_chroot /usr/bin/glib-compile-schemas /usr/share/glib-2.0/schemas

# Replace Arch's with our own mkinitcpio
rm $DEST/etc/mkinitcpio.conf
cp $OTHERDIR/mkinitcpio.conf $DEST/etc/mkinitcpio.conf
do_chroot mkinitcpio -p linux-pine64 || true

cp $OTHERDIR/adwaita-phone.jpg $DEST/usr/share/danctnix

# TODO: probably build for pinetab
# Maybe a first time script that detects if the system model is X and set this?
echo "CHASSIS=\"handset\"" > $DEST/etc/machine-info

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

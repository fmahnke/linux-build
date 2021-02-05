#!/bin/bash

set -e

BUILD="build"
OTHERDIR="otherfiles"
DEST="$1"
OUT_TARBALL="$2"
ROOTFS_PRESET="$3"
BUILD_ARCH=arm64

HOSTNAME="${HOSTNAME:-danctnix}"
PACMAN_MIRROR="${PACMAN_MIRROR:-http://sg.mirror.archlinuxarm.org/\$arch/\$repo}"

# All the presets
if [ "$ROOTFS_PRESET" = "pinephone-phosh" ]; then
	PACKAGES_BASE="dosfstools curl xz iw rfkill netctl dialog wpa_supplicant pv networkmanager device-pine64-pinephone bootsplash-theme-danctnix v4l-utils sudo f2fs-tools zramswap"
	PACKAGES_UI="mesa-git danctnix-phosh-ui-meta xdg-user-dirs noto-fonts-emoji gst-plugins-good lollypop gedit evince-mobile mobile-config-firefox gnome-calculator gnome-clocks gnome-maps megapixels gnome-usage-mobile gtherm geary-mobile purple-matrix purple-telegram portfolio-fm calls chatty kgx gnome-software-mobile gnome-contacts-mobile gnome-initial-setup-mobile"
	SERVICES_ENABLED="${PINEPHONE_PHOSH_SERVICES_ENABLED:-bluetooth eg25_power eg25_audio_routing ModemManager phosh}"

elif [ "$ROOTFS_PRESET" = "pinetab-phosh" ]; then
	PACKAGES_BASE="dosfstools curl xz iw rfkill netctl dialog wpa_supplicant pv networkmanager device-pine64-pinetab bootsplash-theme-danctnix v4l-utils sudo f2fs-tools zramswap"
	PACKAGES_UI="mesa-git danctnix-phosh-ui-meta xdg-user-dirs noto-fonts-emoji gst-plugins-good lollypop gedit evince-mobile mobile-config-firefox gnome-calculator gnome-clocks gnome-maps megapixels gnome-usage-mobile gtherm geary-mobile purple-matrix purple-telegram portfolio-fm chatty kgx gnome-software-mobile gnome-contacts-mobile gnome-initial-setup-mobile"
	SERVICES_ENABLED="${PINETAB_PHOSH_SERVICES_ENABLED:-bluetooth phosh}"

elif [ "$ROOTFS_PRESET" = "pinephone-barebone" ]; then
	PACKAGES_BASE="dosfstools curl xz iw rfkill netctl dialog wpa_supplicant pv networkmanager device-pine64-pinephone danctnix-usb-tethering dhcp sudo f2fs-tools zramswap"
	SERVICES_ENABLED="${PINEPHONE_BAREBONE_SERVICES_ENABLED:-usb-tethering dhcpd4 sshd eg25_power eg25_audio_routing}"

elif [ "$ROOTFS_PRESET" = "pinetab-barebone" ]; then
	PACKAGES_BASE="dosfstools curl xz iw rfkill netctl dialog wpa_supplicant pv networkmanager device-pine64-pinetab danctnix-usb-tethering dhcp sudo f2fs-tools zramswap"
	SERVICES_ENABLED="${PINETAB_BAREBONE_SERVICES_ENABLED:-usb-tethering dhcpd4 sshd}"
fi

for i in $SERVICES_ENABLED; do
    POST_INSTALL="$POST_INSTALL""systemctl enable $i"$'\n'
done

export LC_ALL=C

if [ -z "$DEST" ] || [ -z "$OUT_TARBALL"  ] || [ -z "$ROOTFS_PRESET"  ]; then
	echo "Usage: $0 <destination-folder> <destination-tarball> <rootfs-preset>"
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
	mount -o bind /tmp "$DEST/tmp"
	mount -o bind /dev "$DEST/dev"
	chroot "$DEST" mount -t proc proc /proc
	chroot "$DEST" mount -t sysfs sys /sys
	chroot "$DEST" "$@"
	chroot "$DEST" umount /sys
	chroot "$DEST" umount /proc
	umount "$DEST/dev"
	umount "$DEST/tmp"
}

mv "$DEST/etc/resolv.conf" "$DEST/etc/resolv.conf.dist"
cp /etc/resolv.conf "$DEST/etc/resolv.conf"

cat $OTHERDIR/pacman.conf > "$DEST/etc/pacman.conf"

if [[ "$ROOTFS_PRESET" = *"barebone"* ]]; then
	# Barebone doesn't need more than en_US.
	echo "en_US.UTF-8 UTF-8" > "$DEST/etc/locale.gen-all"
else
	if [ -z "$LOCALE_GEN" ]; then
		cp $OTHERDIR/locale.gen "$DEST/etc/locale.gen-all"
	else
		echo "$LOCALE_GEN" > "$DEST/etc/locale.gen-all"
	fi
fi

mv "$DEST/etc/pacman.d/mirrorlist" "$DEST/etc/pacman.d/mirrorlist.default"

echo "Server = $PACMAN_MIRROR" > "$DEST/etc/pacman.d/mirrorlist"

echo "$HOSTNAME" > "$DEST/etc/hostname"

cat > "$DEST/second-phase" <<EOF
#!/bin/sh
pacman-key --init
pacman-key --populate archlinuxarm
killall -KILL gpg-agent
pacman -Rsn --noconfirm linux-aarch64
pacman -Syu --noconfirm --overwrite=*
pacman -S --noconfirm --overwrite=* --disable-download-timeout --needed $PACKAGES_BASE $PACKAGES_UI

systemctl disable sshd

systemctl disable systemd-networkd
systemctl disable systemd-resolved

systemctl enable zramswap
systemctl enable NetworkManager
usermod -a -G network,video,audio,optical,storage,input,scanner,games,lp,rfkill,wheel alarm

$POST_INSTALL

sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers

cp /etc/locale.gen-all /etc/locale.gen
cd /usr/share/i18n/charmaps
# locale-gen can't spawn gzip when running under qemu-user, so ungzip charmap before running it
# and then gzip it back
gzip -d UTF-8.gz
locale-gen
gzip UTF-8
echo "LANG=en_US.UTF-8" > /etc/locale.conf
EOF

chmod +x "$DEST/second-phase"
cp $OTHERDIR/change-alarm $DEST/

[ -z "$PACMAN_CACHE" ] || mkdir -p "$PACMAN_CACHE" && \
    ls "$PACMAN_CACHE" | \
    xargs -I {} cp "$PACMAN_CACHE/{}" "$DEST/var/cache/pacman/pkg"

do_chroot /second-phase

[ -z "$PACMAN_CACHE" ] || cp "$DEST"/var/cache/pacman/pkg/* "$PACMAN_CACHE"

do_chroot /bin/sh -c "yes | pacman -Scc"

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

cp $OTHERDIR/first_time_setup.sh $DEST/usr/local/sbin/
cp $OTHERDIR/81-blueman.rules $DEST/etc/polkit-1/rules.d/

cp -r $OTHERDIR/systemd/* $DEST/usr/lib/systemd/

install -Dm644 /dev/stdin "$DEST/etc/gtk-3.0/settings.ini" <<END
[Settings]
gtk-application-prefer-dark-theme=1
END

do_chroot /usr/bin/glib-compile-schemas /usr/share/glib-2.0/schemas

# Replace Arch's with our own mkinitcpio
rm $DEST/etc/mkinitcpio.conf
cp $OTHERDIR/mkinitcpio.conf $DEST/etc/mkinitcpio.conf
cp $OTHERDIR/mkinitcpio-hooks/resizerootfs-hooks $DEST/usr/lib/initcpio/hooks/resizerootfs
cp $OTHERDIR/mkinitcpio-hooks/resizerootfs-install $DEST/usr/lib/initcpio/install/resizerootfs

if [[ "$ROOTFS_PRESET" = *"barebone"* ]]; then
	# Barebone does not come with splash.
	sed -i 's/bootsplash-danctnix//g' $DEST/etc/mkinitcpio.conf
fi

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

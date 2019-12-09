export RELEASE_NAME ?= $(shell date +%Y%m%d)

rootfs-$(RELEASE_NAME).tar.gz:
	./make_rootfs.sh rootfs-$(RELEASE_NAME) $@

archlinux-lxqt-pinetab-$(RELEASE_NAME).img: rootfs-$(RELEASE_NAME).tar.gz
	./make_empty_image.sh $@
	./make_image.sh $@ $< u-boot-sunxi-with-spl-pinetab.bin

.PHONY: archlinux-lxqt-pinetab
archlinux-lxqt-pinetab: archlinux-lxqt-pinetab-$(RELEASE_NAME).img

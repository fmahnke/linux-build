export RELEASE_NAME ?= $(shell date +%Y%m%d)

rootfs-$(RELEASE_NAME).tar.gz:
	./make_rootfs.sh rootfs-$(RELEASE_NAME) $@

archlinux-pinetab-$(RELEASE_NAME).img: rootfs-$(RELEASE_NAME).tar.gz
	./make_empty_image.sh $@
	./make_image.sh $@ $< u-boot-sunxi-with-spl-pinetab.bin

archlinux-pinephone-$(RELEASE_NAME).img: rootfs-$(RELEASE_NAME).tar.gz
	./make_empty_image.sh $@
	./make_image.sh $@ $< u-boot-sunxi-with-spl-pinephone.bin

.PHONY: archlinux-pinetab archlinux-pinephone
archlinux-pinetab: archlinux-pinetab-$(RELEASE_NAME).img
archlinux-pinephone: archlinux-pinephone-$(RELEASE_NAME).img

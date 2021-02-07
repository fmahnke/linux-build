This repository builds a distribution of Arch Linux ARM on mobile for the
PinePhone and PineTab. See also the [PKGBUILD repository](https://github.com/dreemurrs-embedded/Pine64-Arch).

# Prerequisites

Configure an x86_64 Arch Linux system with the following packages installed from
the official repositories:

```
arch-install-scripts gcc git f2fs-tools fakeroot make pkgconfig
```

And the following packages from the AUR:

```
glib2-static pcre-static qemu-user-static binfmt-qemu-static
```

*Note:* binfmt-qemu-static must be installed *after* qemu-user-static.

# Building an image

After the prerequisites are satisfied, clone the repository and run one of the
make targets.

```
git clone https://github.com/Danct12/linux-build.git
cd linux-build
make archlinux-pinephone-barebone
```

Flash the finished image to the device as usual.

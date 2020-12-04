#!/bin/bash

# Copyright 2020 - Dreemurrs Embedded Labs

# This is a first time boot script, it is supposed to self destruct after the script has finished.


# IF YOU'RE MEGI THEN.. hey! I doubt you'll see this but if you do please keep in mind
# that I have switched to offline resizing because of F2FS.

# You can defuse the suicide bomb by removing "resizerootfs" from initram hooks.
# Then you can do a further clean up by read this script.

# If you need anything else, please @ me on pinedev IRC/Matrix.

DT_MODEL=$(< /sys/firmware/devicetree/base/model)

if [[ $DT_MODEL =~ "PinePhone" ]]; then
	echo "This is a PinePhone"
	echo "CHASSIS=\"handset\"" > /etc/machine-info
elif [[ $DT_MODEL =~ "PineTab" ]]; then
	echo "This is a PineTab."
	echo "CHASSIS=\"tablet\"" > /etc/machine-info
else
	echo "Cannot identify this device, this might not be a PinePhone/PineTab."
	exit 1 # End the script, because the user is probably running it on a x86 computer
fi

# Resize the rootfs
sed -i 's/resizerootfs//g' /etc/mkinitcpio.conf
mkinitcpio -p linux-pine64

# Bye, and I hope to not see you again until the next reinstall.
rm /usr/local/sbin/first_time_setup.sh
rm /usr/lib/systemd/system/first_time_setup.service
rm /usr/lib/systemd/system/multi-user.target.wants/first_time_setup.service
rm /usr/lib/initcpio/hooks/resizerootfs
rm /usr/lib/initcpio/install/resizerootfs

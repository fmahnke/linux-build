#!/bin/bash

# Copyright 2020 - Dreemurrs Embedded Labs

# This is a first time boot script, it is supposed to self destruct after the script has finished.

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
/usr/local/sbin/resize_rootfs.sh

# Bye, and I hope to not see you again until the next reinstall.
rm /usr/local/sbin/first_time_setup.sh
rm /usr/lib/systemd/system/first_time_setup.service
rm /usr/lib/systemd/system/multi-user.target.wants/first_time_setup.service

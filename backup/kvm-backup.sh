#!/bin/bash

# Set the language to English so virsh does it's output
# in English as well
LANG=en_US

# Define the script name, this is used with systemd-cat to
# identify this script in the journald output
SCRIPTNAME=kvm-backup

# List domains
DOMAINS=$(virsh list | tail -n +3 | awk '{print $2}')

# Loop over the domains found above and do the
# actual backup

for DOMAIN in $DOMAINS; do

	echo "Starting backup for $DOMAIN on $(date +'%d-%m-%Y %H:%M:%S')" | systemd-cat -t $SCRIPTNAME

	# Generate the backup folder URI - this is something you should
	# change/check
	BACKUPFOLDER=/mnt/$DOMAIN/$(date +%d-%m-%Y)
	mkdir -p $BACKUPFOLDER

	# Get the target disk
	TARGETS=$(virsh domblklist $DOMAIN --details | grep disk | grep -v 'cdrom' | grep -v 'floppy' | awk '{print $3}')

	# Get the image page
	IMAGES=$(virsh domblklist $DOMAIN --details | grep disk | grep -v 'cdrom' | grep -v 'floppy' | awk '{print $4}')

	# Create the snapshot/disk specification
	DISKSPEC=""

	for TARGET in $TARGETS; do
		DISKSPEC="$DISKSPEC --diskspec $TARGET,snapshot=external"
	done

	virsh snapshot-create-as --domain $DOMAIN --name "backup-$DOMAIN" --no-metadata --atomic --disk-only $DISKSPEC 1>/dev/null 2>&1

	if [ $? -ne 0 ]; then
		echo "Failed to create snapshot for $DOMAIN" | systemd-cat -t $SCRIPTNAME
		exit 1
	fi

	# Copy disk image
	for IMAGE in $IMAGES; do
		NAME=$(basename $IMAGE)
		cp $IMAGE $BACKUPFOLDER/$NAME
	done

	# Merge changes back
	BACKUPIMAGES=$(virsh domblklist $DOMAIN --details | grep disk | awk '{print $4}')

	for TARGET in $TARGETS; do
		virsh blockcommit $DOMAIN $TARGET --active --pivot 1>/dev/null 2>&1

		if [ $? -ne 0 ]; then
			echo "Could not merge changes for disk of $TARGET of $DOMAIN. VM may be in invalid state." | systemd-cat -t $SCRIPTNAME
			exit 1
		fi
	done

	# Cleanup left over backups
	for BACKUP in $BACKUPIMAGES; do
		rm -f $BACKUP
	done

	# Dump the configuration information.
	virsh dumpxml $DOMAIN > $BACKUPFOLDER/$DOMAIN.xml 1>/dev/null 2>&1

	echo "Finished backup of $DOMAIN at $(date +'%d-%m-%Y %H:%M:%S')" | systemd-cat -t $SCRIPTNAME
done

exit 0

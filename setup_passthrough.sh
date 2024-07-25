###############################################################################
#                                                                             #
# WARNING!! Use at your own risk.                                             #
#                                                                             #
# A single purpose (destructive) helper bash script (it works on my machine!) #
# to enable GPU Passthrough.                                                  #
#                                                                             #
# Elevated priviledges required to run                                        #
#                                                                             #
# Author:   David A. Cummings                                                 #
# Date:     07/2024                                                           #
#                                                                             #
#                                                                             #
###############################################################################

#!/bin/bash

## Ticker function to show system has not stalled during long commands
ticker(){
	"$@" &

	while kill -0 $!; do
	    echo -n '.' > /dev/tty
	    sleep 1
	done

	echo -n  > /dev/tty
}

# Check ids against lspci output, for validity.
check_ids(){
	COUNT=0
	IDS=( $(lspci -nn | grep $1 | grep -E -o '[A-Za-z0-9]{4}[:][A-Za-z0-9]{4}') )
	LENGTH=${#IDS[@]}

	while [ $COUNT -le $LENGTH ]
	do
		if test "$2" = "${IDS[$COUNT]}" ; then
			echo -n " ...OK!" ;
			echo ""
			break
		fi

		COUNT=$(( $COUNT+1 ))

		if [ "$LENGTH" = $COUNT ] ; then
			echo -n " ...id unavailable. Quiting."
			echo ""
			exit 1
		fi
	done
}

read -p "Virtualization vendor [amd/intel]: " VENDOR # amd or intel

echo ""

VENDOR=${VENDOR,,}	# Reset variable to be lowercase
if test "$VENDOR" != "amd" && test "$VENDOR" != "intel"; then
	echo "Unknown vendor. Quiting..."
	echo ""
	exit 1
fi

echo "`lspci -nn | grep VGA`"
echo ""
read -p "Device id: " GFX_ID
check_ids VGA $GFX_ID

echo ""
echo "`lspci -nn | grep Audio`"
echo ""
read -p "Device id: " HDA_ID
check_ids Audio $HDA_ID

echo ""
read -p "Driver blacklist (separated by space:) " BLACKLIST

## Update GRUB
GRUBLN='GRUB_CMDLINE_LINUX_DEFAULT="loglevel=4 '$VENDOR'_iommu=on iommu=pt rd.driver.pre=vfio-pci video=efifb:off vfio-pci.ids='$GFX_ID,$HDA_ID'"'

sed -i "/GRUB_CMDLINE_LINUX_DEFAULT/c\\$GRUBLN" /etc/default/grub
echo -n "Updating GRUB"
ticker update-grub > /dev/tty2 2>&1

## Add IDs to modprobe
touch /etc/modprobe.d/vfio.conf
echo 'options vfio-pci ids='$GFX_ID','$HDA_ID | tee /etc/modprobe.d/vfio.conf > /dev/tty2 2>&1
## And, blacklist any drivers
touch /etc/modprobe.d/blacklist.conf
truncate -s 0 /etc/modprobe.d/blacklist.conf # Clear previous contents
for ARG in $BLACKLIST; do
   echo "blacklist "$ARG | tee -a /etc/modprobe.d/blacklist.conf > /dev/tty2 2>&1;
done

## Add drivers to dracut
touch /etc/dracut.conf.d/vfio.conf
echo 'add_drivers+=" vfio_pci vfio vfio_iommu_type1 "' | tee /etc/dracut.conf.d/vfio.conf > /dev/tty2 2>&1

 
## Regenerate initramfs
echo ""
echo -n "Regenerating initramfs"
ticker dracut -f > /dev/tty2 2>&1
echo ""

exit 0

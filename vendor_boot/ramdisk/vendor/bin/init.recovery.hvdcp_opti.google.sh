#! /system/bin/sh

find /sys/class/power_supply/battery/ -type f -maxdepth 1 | xargs chown system.system
find /sys/class/power_supply/bms/ -type f -maxdepth 1 | xargs chown system.system
find /sys/class/power_supply/usb/ -type f -maxdepth 1 | xargs chown system.system
find /sys/class/qcom-battery/ -type f -maxdepth 1 | xargs chown system.system
find /sys/class/qbg/qbg_context -type f -maxdepth 1 | xargs chown system.system

for i in 0 1 2 3 4 5 6 7 8 9
do
  devname=`cat /sys/bus/iio/devices/iio:device$i/name`
  if [[ "$devname" == *smb* ]] || [[ "$devname" == *qg* ]] || [[ "$devname" == *div2_cp* ]] || [[ "$devname" == *div2-cp* ]]; then
    find /sys/bus/iio/devices/iio:device$i/ -type f -maxdepth 1 | xargs chown system.system
  fi
done

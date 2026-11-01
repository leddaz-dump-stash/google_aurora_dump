#=============================================================================
# Copyright (c) 2019-2023 Qualcomm Technologies, Inc.
# All Rights Reserved.
# Confidential and Proprietary - Qualcomm Technologies, Inc.
#
# Copyright (c) 2009-2012, 2014-2019, The Linux Foundation. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of The Linux Foundation nor
#       the names of its contributors may be used to endorse or promote
#       products derived from this software without specific prior written
#       permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NON-INFRINGEMENT ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
# OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
# OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
# ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#=============================================================================

function configure_zram_parameters() {
	# Skip if mmd is configured to set up ZRAM
	mmd_zram_enabled=`getprop vendor.mmd.zram.enabled`
	if [ "$mmd_zram_enabled" == "true" ]; then
		return
	fi

	MemTotalStr=`cat /proc/meminfo | grep MemTotal`
	MemTotal=${MemTotalStr:16:8}

	low_ram=`getprop ro.config.low_ram`

	# Zram disk - 75% for Go and < 2GB devices .
	# For >2GB Non-Go devices, size = 50% of RAM size. Limit the size to 4GB.
	# And enable lz4 zram compression for Go targets.

	let RamSizeGB="( $MemTotal / 1048576 ) + 1"
	diskSizeUnit=M
	if [ $RamSizeGB -le 2 ]; then
		let zRamSizeMB="( $RamSizeGB * 1024 ) * 3 / 4"
	else
		let zRamSizeMB="( $RamSizeGB * 1024 ) / 2"
	fi

	# use MB avoid 32 bit overflow
	if [ $zRamSizeMB -gt 4096 ]; then
		let zRamSizeMB=4096
	fi

	if [ "$low_ram" == "true" ]; then
		echo lz4 > /sys/block/zram0/comp_algorithm
	fi

	if [ -f /sys/block/zram0/disksize ]; then
		if [ -f /sys/block/zram0/use_dedup ]; then
			echo 1 > /sys/block/zram0/use_dedup
		fi
		echo "$zRamSizeMB""$diskSizeUnit" > /sys/block/zram0/disksize

		# ZRAM may use more memory than it saves if SLAB_STORE_USER
		# debug option is enabled.
		if [ -e /sys/kernel/slab/zs_handle ]; then
			echo 0 > /sys/kernel/slab/zs_handle/store_user
		fi
		if [ -e /sys/kernel/slab/zspage ]; then
			echo 0 > /sys/kernel/slab/zspage/store_user
		fi

		mkswap /dev/block/zram0
		swapon /dev/block/zram0 -p 32758
	fi
}

verify_pasr_support()
{
	ddr_type=`od -An -tx /proc/device-tree/memory/ddr_device_type`
	ddr_type5="08"

	if [ -d /sys/kernel/mem-offline ]; then
		#only LPDDR5 supports PAAR
		if [ ${ddr_type:4:2} != $ddr_type5 ]; then
			setprop vendor.pasr.activemode.enabled false
		fi

		setprop vendor.pasr.enabled true
	fi
}

function configure_read_ahead_kb_values() {
	MemTotalStr=`cat /proc/meminfo | grep MemTotal`
	MemTotal=${MemTotalStr:16:8}

	dmpts=$(ls /sys/block/*/queue/read_ahead_kb | grep -e dm -e mmc -e sd)
	# dmpts holds below read_ahead_kb nodes if exists:
	# /sys/block/dm-0/queue/read_ahead_kb to /sys/block/dm-10/queue/read_ahead_kb
	# /sys/block/sda/queue/read_ahead_kb to /sys/block/sdh/queue/read_ahead_kb

	# Set 128 for <= 4GB &
	# set 512 for >= 5GB targets.
	if [ $MemTotal -le 4194304 ]; then
		ra_kb=128
	else
		ra_kb=512
	fi
	if [ -f /sys/block/mmcblk0/bdi/read_ahead_kb ]; then
		echo $ra_kb > /sys/block/mmcblk0/bdi/read_ahead_kb
	fi
	if [ -f /sys/block/mmcblk0rpmb/bdi/read_ahead_kb ]; then
		echo $ra_kb > /sys/block/mmcblk0rpmb/bdi/read_ahead_kb
	fi
	for dm in $dmpts; do
		echo $ra_kb > $dm
	done
}

function configure_thp()
{
	## Goal is to allow all allocations to use THP whilst minimizing allocaiton delays
	# Allow all eligibe page faults to use THP
	echo always > /sys/kernel/mm/transparent_hugepage/enabled
	# Prevent page faults on THP-elgible VMAs from causing reclaim or compaction
	echo never > /sys/kernel/mm/transparent_hugepage/defrag

        ## Goal is to make khugepaged as inert as possible using the below settings
	# Prevent khugepaged from doing reclaim or compaction
	echo 0 > /sys/kernel/mm/transparent_hugepage/khugepaged/defrag
	# Minimize the number of pages that khugepaged will scan
	echo 1 > /sys/kernel/mm/transparent_hugepage/khugepaged/pages_to_scan
	# Maximize the amount of time that khugepaged is asleep for
	echo 4294967295 > /sys/kernel/mm/transparent_hugepage/khugepaged/scan_sleep_millisecs
	echo 4294967295 > /sys/kernel/mm/transparent_hugepage/khugepaged/alloc_sleep_millisecs
	# Restrict khugepaged promotions as much as possible. Only allow khugepaged to promote
	# if all pages in a VMA are (1) not invalid PTEs, (2) not swapped out PTEs, (3) not
	# shared PTEs.
	echo 0 > /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none
	echo 0 > /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_swap
	echo 0 > /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_shared
}

function configure_min_free_kbytes()
{
	MemTotalStr=`cat /proc/meminfo | grep MemTotal`
	MemTotal=${MemTotalStr:16:8}
	let RamSizeGB="( $MemTotal / 1048576 ) + 1"
	# Set the min_free_kbytes to standard kernel value
	if [ $RamSizeGB -ge 12 ]; then
		# 12GB, 16GB
		MinFreeKbytes=11584
	elif [ $RamSizeGB -ge 8 ]; then
		# 8GB
		MinFreeKbytes=11584
		WatermarkScale=65
		echo $WatermarkScale > /proc/sys/vm/watermark_scale_factor

	elif [ $RamSizeGB -ge 4 ]; then
		MinFreeKbytes=8192
	elif [ $RamSizeGB -ge 2 ]; then
		MinFreeKbytes=5792
	else
		MinFreeKbytes=4096
	fi

	# We store min_free_kbytes into a vendor property so that the PASR
	# HAL can read and set the value for it.
	echo $MinFreeKbytes > /proc/sys/vm/min_free_kbytes
	setprop vendor.memory.min_free_kbytes $MinFreeKbytes

}

function configure_memory_parameters() {
	# Set Memory parameters.
	#
	# Set per_process_reclaim tuning parameters
	# All targets will use vmpressure range 50-70,
	# All targets will use 512 pages swap size.
	#
	# Set Low memory killer minfree parameters
	# 32 bit Non-Go, all memory configurations will use 15K series
	# 32 bit Go, all memory configurations will use uLMK + Memcg
	# 64 bit will use Google default LMK series.
	#
	# Set ALMK parameters (usually above the highest minfree values)
	# vmpressure_file_min threshold is always set slightly higher
	# than LMK minfree's last bin value for all targets. It is calculated as
	# vmpressure_file_min = (last bin - second last bin ) + last bin
	#
	# Set allocstall_threshold to 0 for all targets.
	#

	configure_zram_parameters
	configure_read_ahead_kb_values
	configure_thp

	# Enabling or disabling thp will reset the value of min_free_kbytes
        # Call configure_min_free_kbytes after
        configure_min_free_kbytes
	echo 100 > /proc/sys/vm/swappiness

	# Disable wsf for all targets beacause we are using efk.
	# wsf Range : 1..1000 So set to bare minimum value 1.
	# Removing this override allows the default watermark_scale_factor
	# configured in init.memory.rc to take effect.
	# Normal wsf = 100, OTA wsf = 300(check init.memory.rc for actual wsf)
	# echo 1 > /proc/sys/vm/watermark_scale_factor

	echo 1 > /proc/sys/vm/reap_mem_on_sigkill

	# Disable periodic kcompactd wakeups. We do not use THP, so having many
	# huge pages is not as necessary.
	echo 0 > /proc/sys/vm/compaction_proactiveness

	MemTotalStr=`cat /proc/meminfo | grep MemTotal`
	MemTotal=${MemTotalStr:16:8}
	let RamSizeGB="( $MemTotal / 1048576 ) + 1"

	verify_pasr_support
}

configure_memory_parameters

if [ -f /sys/devices/soc0/soc_id ]; then
	platformid=`cat /sys/devices/soc0/soc_id`
fi

case "$platformid" in
	"486"|"517")
		/vendor/bin/sh /vendor/bin/init.kernel.post_boot-monaco.sh
		;;
	*)
		echo "***WARNING***: Invalid SoC ID\n\t No postboot settings applied!!\n"
		;;
esac


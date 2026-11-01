#! /vendor/bin/sh
#=============================================================================
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# All rights reserved.
# Confidential and Proprietary - Qualcomm Technologies, Inc.
#=============================================================================

LOG_TAG="strongbox_init"
log -p i -t $LOG_TAG "eSE initialization script started"

# Get SoC name
soc_id=$(cat /sys/devices/soc0/soc_id 2>/dev/null)
if [ -z "$soc_id" ]; then
    log -p e -t $LOG_TAG "Failed to get SoC ID"
    soc_id=0
fi

soc_supported=false
vintf_enabled=false
sku_name=""

if [ "$soc_id" -eq 685 ] || [ "$soc_id" -eq 727 ]; then
    soc_supported=true
    sku_name=alor
    log -p i -t $LOG_TAG "Detected SoC: Alor"
elif [ "$soc_id" -eq 724 ] || [ "$soc_id" -eq 744 ]; then
    soc_supported=true
    sku_name=chora
    log -p i -t $LOG_TAG "Detected SoC: Chora"
elif [ "$soc_id" -eq 733 ] || [ "$soc_id" -eq 757 ]; then
    soc_supported=true
    sku_name=malabar
    log -p i -t $LOG_TAG "Detected SoC: Malabar"
elif [ "$soc_id" -eq 669 ]; then
    soc_supported=true
    log -p i -t $LOG_TAG "Detected SoC: Vienna"
fi

if (grep -rq 'IKeyMintDevice/strongbox' /vendor/etc/vintf/manifest/); then
    vintf_enabled=true
    log -p i -t $LOG_TAG "IKeyMintDevice/strongbox VINTF enabled."
fi

if [ "$sku_name" != "" ]; then
    if (grep -q 'IKeyMintDevice/strongbox' /vendor/etc/vintf/manifest_${sku_name}.xml); then
        vintf_enabled=true
        log -p i -t $LOG_TAG "IKeyMintDevice/strongbox VINTF enabled for SKU."
    fi
fi

if [ "$soc_supported" = "true" ] && [ "$vintf_enabled" = "true" ]; then
    if [ -e /proc/device-tree/soc/st54spi_gpio ]; then
        log -p i -t $LOG_TAG "enabling STM services"
        setprop vendor.ese.strongbox STM
    else
        log -p i -t $LOG_TAG "enabling NXP services"
        setprop vendor.ese.strongbox NXP
    fi
else
    log -p i -t $LOG_TAG "Strongbox service is not getting enabled"
fi

log -p i -t $LOG_TAG "eSE initialization script completed"

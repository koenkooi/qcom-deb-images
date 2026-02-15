#!/bin/bash

handle_no_soundcard() {
    logger -t remoteproc-check "No sound cards found via alsaucm. Attempting remoteproc restart..."
    if cat /sys/class/remoteproc/remoteproc1/state | grep -q "running"; then
        logger -t remoteproc-check "Remoteproc is currently running. Stopping it before restart."
        echo stop > /sys/class/remoteproc/remoteproc1/state
    else
    echo -n qcom/qcm2290/adsp.mbn > /sys/class/remoteproc/remoteproc1/firmware
    fi
    echo start > /sys/class/remoteproc/remoteproc1/state
}

if alsaucm listcards 2>/dev/null | grep -q "list is empty"; then
    handle_no_soundcard
else
    logger -t remoteproc-check "Sound cards found via alsaucm. No need to restart remoteproc."
fi
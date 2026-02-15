#!/bin/bash

function check_key()
{
    device=$1
    event=$2
    keycode=$3

    evtest --query ${device} ${event} ${keycode}

    ret_val=$?
    echo $ret_val
}

exec_path_vold="/opt/arduino/scripts/volumedown.sh"
exec_path_volu="/opt/arduino/scripts/volumeup.sh"

volumedown=$(check_key /dev/input/event0 EV_KEY KEY_VOLUMEDOWN)
volumeup=$(check_key /dev/input/event0 EV_KEY KEY_VOLUMEUP)

echo "Volume Down status: ${volumedown}"
echo "Volume Up status: ${volumeup}"

if [ $volumeup -ne 0 ] && [ $volumedown -ne 0 ]; then
    echo "Both Volume Up and Volume Down keys are pressed. Ignoring both."
    exit 0
fi

if [ ${volumedown} -ne 0 ]; then
    bash ${exec_path_vold}
elif [ ${volumeup} -ne 0 ]; then
    bash ${exec_path_volu}
fi

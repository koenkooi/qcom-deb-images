#!/bin/bash

# SPDX-FileCopyrightText: Copyright (C) Arduino s.r.l. and/or its affiliated companies
#
# SPDX-License-Identifier: BSD-3-Clause

INSTALL_PATH=$(dirname "$(readlink -f $0)")/..
CMDS="reset_config srst_only srst_push_pull; init; reset; shutdown"

$INSTALL_PATH/bin/openocd -d2 -s ${INSTALL_PATH} -f openocd_gpiod.cfg -c "$CMDS"

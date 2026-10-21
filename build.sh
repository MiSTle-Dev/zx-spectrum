#!/bin/bash
BOARD=nano20k
if [ "$#" -eq 1 ]; then
    BOARD=$1
fi

# run through grc to highlight NOTEs, WARNings and ERRORs
grc --config=gw_sh.grc gw_sh build.tcl ${BOARD}

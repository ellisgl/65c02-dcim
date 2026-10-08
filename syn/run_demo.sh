#!/bin/sh
# usage: run_demo.sh <name>
n=$1
OSS=/home/ellis/oss-cad-suite/bin
$OSS/yosys -q -l $n.yosys.log \
    -p "read_verilog -DSYNTH \
        ../rtl/ALU.v \
        ../rtl/decode_65c02.v \
        ../rtl/zp_dcim.v \
        ../rtl/cpu_65c02_dcim.v \
        ../rtl/video_timing.v \
        ../rtl/tmds_encoder.v \
        top_demo.v; \
        synth_gowin -family gw2a -top top_demo -json $n.json" || exit 1
$OSS/nextpnr-himbaechel \
    --json $n.json \
    --device GW2AR-LV18QN88C8/I7 \
    --vopt family=GW2A-18C \
    --vopt cst=nano20k_demo.cst \
    --freq 27 \
    --write $n.pnr.json \
    --report $n.report.json \
    > $n.pnr.log 2>&1 || { echo "PNR failed"; exit 1; }
$OSS/gowin_pack -d GW2A-18C -o $n.fs $n.pnr.json || exit 1
echo "$n.fs ready"

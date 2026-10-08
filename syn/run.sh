#!/bin/sh
# usage: run.sh <name>
n=$1
VENV=/home/ellis/Projects/FPGA/xsynth/.venv/bin
$VENV/yowasp-yosys -q -l $n.yosys.log -p "read_verilog -DSYNTH ../rtl/ALU.v ../rtl/decode_65c02.v ../rtl/zp_dcim.v ../rtl/cpu_65c02_dcim.v top.v; synth_gowin -family gw2a -top top -json $n.json" || exit 1
$VENV/yowasp-nextpnr-himbaechel-gowin --json $n.json --device GW2AR-LV18QN88C8/I7 --vopt family=GW2A-18C --vopt cst=nano20k.cst --freq 27 --write $n.pnr.json --report $n.report.json > $n.pnr.log 2>&1
echo "$n exit=$?"

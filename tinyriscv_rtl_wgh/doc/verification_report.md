# tinyriscV Project Modification Review

Date: 2026-05-02

## Summary

The previously failing top-level off-chip `lw` regression has been reproduced,
root-caused, fixed, and re-run.  The detailed requirement-to-design evidence is
now maintained in the root-level `readme.me`.

## Root Cause Of The Previous Failure

`tb_soc_load` originally failed because the RIB could start the next instruction
fetch immediately after returning the current instruction.  When that current
instruction was a load, it reached EX while the off-chip bridge was already
owned by the next fetch, so the data load request was not accepted by the
bridge.  In addition, the original tinyriscV execute stage assumed same-cycle
load data, which is invalid for the 8-bit multi-cycle off-chip bridge.

## Fixes Applied

- Replaced `core/rib.v` with an explicit off-chip transaction FSM:
  `ST_IDLE -> ST_ISSUE -> ST_WAIT -> ST_RESP`.
- Added owner-locked response routing in `core/rib.v`, so bridge return data is
  delivered only to the master that issued the transaction.
- Added a one-cycle `defer_fetch` after fetch response in `core/rib.v`, allowing
  the fetched instruction to enter EX before the next fetch can occupy the
  off-chip bridge.
- Added delayed off-chip load writeback in `core/tinyriscv.v`, including
  `LB/LH/LW/LBU/LHU` data formatting.
- Kept earlier fixes:
  - custom instruction busy participates in pipeline hold;
  - I2C `done` status is sticky until the next request;
  - JTAG `tx_idle` is explicitly declared.

## Simulations Run

All commands were run from the project root with Icarus Verilog.

```powershell
iverilog -g2012 -Wall -o .\sim_project.vvp -s tinyriscv_soc_top -f filelist_project.f
```

Result: PASS elaboration.

```powershell
iverilog -g2012 -Wall -I core -o .\sim_custom_unit.vvp sim\tb_custom_unit.v core\custom_unit.v
vvp .\sim_custom_unit.vvp
```

Result: PASS.

```powershell
iverilog -g2012 -Wall -I core -o .\sim_pwm.vvp sim\tb_pwm.v perips\pwm.v
vvp .\sim_pwm.vvp
```

Result: PASS.

```powershell
iverilog -g2012 -Wall -I core -o .\sim_i2c.vvp sim\tb_i2c_lm75.v perips\i2c_lm75.v
vvp .\sim_i2c.vvp
```

Result: PASS.

```powershell
iverilog -g2012 -Wall -I core -o .\sim_mem_bridge.vvp sim\tb_mem_bridge.v perips\chip_mem_bridge.v fpga\fpga_mem_bridge.v
vvp .\sim_mem_bridge.vvp
```

Result: PASS.

```powershell
iverilog -g2012 -Wall -I core -o .\sim_soc_load.vvp -f filelist_project.f sim\tb_soc_load.v fpga\fpga_mem_bridge.v
vvp .\sim_soc_load.vvp
```

Result: PASS.

```powershell
iverilog -g2012 -Wall -I core -o .\sim_soc_mem_ops.vvp -f filelist_project.f sim\tb_soc_mem_ops.v fpga\fpga_mem_bridge.v
vvp .\sim_soc_mem_ops.vvp
```

Result: PASS.  Covers `lw/lb/lbu/lh/lhu/sw` through off-chip RAM.

```powershell
iverilog -g2012 -Wall -I core -o .\sim_chip_sel.vvp -f filelist_project.f sim\tb_chip_sel.v fpga\fpga_mem_bridge.v
vvp .\sim_chip_sel.vvp
```

Result: PASS.

## Remaining Non-RTL Signoff Items

- FPGA board validation with the TA-provided flow has not been run in this
  local environment.
- Synthesis, STA, place and route, DRC/LVS, and GDS are not present in this RTL
  repository.
- Actual student ID bytes in `core/custom_unit.v` still need to be replaced
  before final personal submission.
- The multi-chip shared IO-ring pad wrapper/mux is not included in this
  single-chip RTL top.


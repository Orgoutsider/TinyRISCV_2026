# CHANGELOG

## rev_project_1

- Add project memory map and custom instruction definitions in `core/defines.v`.
- Modify `core/id.v` and `core/ex.v` for custom opcode `0101111`.
- Add `core/custom_unit.v` for sID/rT/if multi-cycle operations.
- Modify `core/tinyriscv.v` to connect UART/I2C sideband.
- Replace original RIB with reduced memory map in `core/rib.v`.
- Replace SoC top with area-reduced `soc/tinyriscv_soc_top.v`.
- Add `perips/pwm.v`.
- Add `perips/i2c_lm75.v`.
- Add `perips/uart_shared.v`.
- Rewrite `perips/uart_debug.v` to use 35 x 8-bit RX buffer.
- Add chip-side and FPGA-side off-chip memory bridge modules.

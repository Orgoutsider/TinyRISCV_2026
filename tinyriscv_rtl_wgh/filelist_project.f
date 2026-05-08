+incdir+./core
+incdir+./utils
+incdir+./debug
+incdir+./perips
+incdir+./soc

./utils/gen_dff.v
./utils/gen_buf.v
./utils/full_handshake_rx.v
./utils/full_handshake_tx.v

./core/clint.v
./core/csr_reg.v
./core/ctrl.v
./core/div.v
./core/regs.v
./core/pc_reg.v
./core/if_id.v
./core/id.v
./core/id_ex.v
./core/ex.v
./core/custom_unit.v
./core/rib.v
./core/tinyriscv.v

./debug/jtag_driver.v
./debug/jtag_dm.v
./debug/jtag_top.v

./perips/uart_shared.v
./perips/uart_debug.v
./perips/chip_mem_bridge.v
./perips/pwm.v
./perips/i2c_lm75.v

./soc/tinyriscv_soc_top.v

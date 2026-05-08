/*
 * tinyriscv project configuration and common definitions.
 * Modified for RISC-V processor design project:
 *   - off-chip ROM/RAM bridge
 *   - PWM/I2C peripherals
 *   - custom instructions sID/rT/if
 */

`ifndef TINYRISCV_DEFINES_V // header guard start
`define TINYRISCV_DEFINES_V // header guard define

`define CpuResetAddr 32'h0000_0000 // CPU reset address

`define RstEnable  1'b0 // reset active level
`define RstDisable 1'b1 // reset inactive level
`define ZeroWord   32'h0000_0000 // 32-bit zero
`define ZeroReg    5'h00 // register x0
`define WriteEnable  1'b1 // write enable
`define WriteDisable 1'b0 // write disable
`define ReadEnable   1'b1 // read enable
`define ReadDisable  1'b0 // read disable
`define True  1'b1 // boolean true
`define False 1'b0 // boolean false
`define ChipEnable  1'b1 // chip enable
`define ChipDisable 1'b0 // chip disable
`define JumpEnable  1'b1 // jump enable
`define JumpDisable 1'b0 // jump disable
`define DivResultNotReady 1'b0 // divider not ready
`define DivResultReady    1'b1 // divider ready
`define DivStart 1'b1 // divider start
`define DivStop  1'b0 // divider stop
`define HoldEnable  1'b1 // pipeline hold enable
`define HoldDisable 1'b0 // pipeline hold disable
`define Stop   1'b1 // stop flag
`define NoStop 1'b0 // no stop flag
`define RIB_ACK  1'b1 // RIB ack
`define RIB_NACK 1'b0 // RIB nack
`define RIB_REQ  1'b1 // RIB request
`define RIB_NREQ 1'b0 // RIB no request
`define INT_ASSERT   1'b1 // interrupt assert
`define INT_DEASSERT 1'b0 // interrupt deassert

`define INT_BUS 7:0 // interrupt bus width
`define INT_NONE 8'h00 // no interrupt
`define INT_RET  8'hff // interrupt return
`define INT_TIMER0 8'b0000_0001 // timer0 interrupt
`define INT_TIMER0_ENTRY_ADDR 32'h0000_0004 // timer0 vector

`define Hold_Flag_Bus 2:0 // hold flag bus width
`define Hold_None 3'b000 // no hold
`define Hold_Pc   3'b001 // hold PC
`define Hold_If   3'b010 // hold IF
`define Hold_Id   3'b011 // hold ID

// -----------------------------------------------------------------------------
// Memory map after project modification
// -----------------------------------------------------------------------------
// 0x0000_0000 - 0x0fff_ffff: off-chip ROM window, actual depth 256 x 32-bit
// 0x1000_0000 - 0x1fff_ffff: off-chip RAM window, actual depth 16 x 32-bit
// 0x3000_0000 - 0x3fff_ffff: UART
// 0x6000_0000 - 0x6fff_ffff: PWM
// 0x7000_0000 - 0x7fff_ffff: I2C
`define ROM_BASE_ADDR 32'h0000_0000 // ROM base address
`define RAM_BASE_ADDR 32'h1000_0000 // RAM base address
`define UART_BASE_ADDR 32'h3000_0000 // UART base address
`define PWM_BASE_ADDR 32'h6000_0000 // PWM base address
`define I2C_BASE_ADDR 32'h7000_0000 // I2C base address

`define RomNum 256 // ROM depth
`define MemNum 16 // RAM depth
`define MemBus 31:0 // memory data bus
`define MemAddrBus 31:0 // memory address bus

`define InstBus 31:0 // instruction bus
`define InstAddrBus 31:0 // instruction address bus

`define RegAddrBus 4:0 // register address bus
`define RegBus 31:0 // register data bus
`define DoubleRegBus 63:0 // double-width bus
`define RegWidth 32 // register width
`define RegNum 32 // register count
`define RegNumLog2 5 // register index width

// I type inst
`define INST_TYPE_I 7'b0010011 // I-type opcode
`define INST_ADDI   3'b000 // ADDI funct3
`define INST_SLTI   3'b010 // SLTI funct3
`define INST_SLTIU  3'b011 // SLTIU funct3
`define INST_XORI   3'b100 // XORI funct3
`define INST_ORI    3'b110 // ORI funct3
`define INST_ANDI   3'b111 // ANDI funct3
`define INST_SLLI   3'b001 // SLLI funct3
`define INST_SRI    3'b101 // SRLI/SRAI funct3

// L type inst
`define INST_TYPE_L 7'b0000011 // L-type opcode
`define INST_LB     3'b000 // LB funct3
`define INST_LH     3'b001 // LH funct3
`define INST_LW     3'b010 // LW funct3
`define INST_LBU    3'b100 // LBU funct3
`define INST_LHU    3'b101 // LHU funct3

// S type inst
`define INST_TYPE_S 7'b0100011 // S-type opcode
`define INST_SB     3'b000 // SB funct3
`define INST_SH     3'b001 // SH funct3
`define INST_SW     3'b010 // SW funct3

// R and M type inst
`define INST_TYPE_R_M 7'b0110011 // R/M-type opcode
`define INST_ADD_SUB 3'b000 // ADD/SUB funct3
`define INST_SLL    3'b001 // SLL funct3
`define INST_SLT    3'b010 // SLT funct3
`define INST_SLTU   3'b011 // SLTU funct3
`define INST_XOR    3'b100 // XOR funct3
`define INST_SR     3'b101 // SRL/SRA funct3
`define INST_OR     3'b110 // OR funct3
`define INST_AND    3'b111 // AND funct3
`define INST_MUL    3'b000 // MUL funct3
`define INST_MULH   3'b001 // MULH funct3
`define INST_MULHSU 3'b010 // MULHSU funct3
`define INST_MULHU  3'b011 // MULHU funct3
`define INST_DIV    3'b100 // DIV funct3
`define INST_DIVU   3'b101 // DIVU funct3
`define INST_REM    3'b110 // REM funct3
`define INST_REMU   3'b111 // REMU funct3

`define INST_TYPE_B 7'b1100011 // B-type opcode
`define INST_BEQ    3'b000 // BEQ funct3
`define INST_BNE    3'b001 // BNE funct3
`define INST_BLT    3'b100 // BLT funct3
`define INST_BGE    3'b101 // BGE funct3
`define INST_BLTU   3'b110 // BLTU funct3
`define INST_BGEU   3'b111 // BGEU funct3

`define INST_JAL    7'b1101111 // JAL opcode
`define INST_JALR   7'b1100111 // JALR opcode
`define INST_LUI    7'b0110111 // LUI opcode
`define INST_AUIPC  7'b0010111 // AUIPC opcode
`define INST_NOP    32'h0000_0001 // NOP instruction
`define INST_NOP_OP 7'b0000001 // NOP opcode
`define INST_MRET   32'h30200073 // MRET instruction
`define INST_RET    32'h00008067 // RET instruction
`define INST_FENCE  7'b0001111 // FENCE opcode
`define INST_ECALL  32'h00000073 // ECALL instruction
`define INST_EBREAK 32'h00100073 // EBREAK instruction

// CSR inst
`define INST_CSR    7'b1110011 // CSR opcode
`define INST_CSRRW  3'b001 // CSRRW funct3
`define INST_CSRRS  3'b010 // CSRRS funct3
`define INST_CSRRC  3'b011 // CSRRC funct3
`define INST_CSRRWI 3'b101 // CSRRWI funct3
`define INST_CSRRSI 3'b110 // CSRRSI funct3
`define INST_CSRRCI 3'b111 // CSRRCI funct3

// Project custom instructions: opcode = 0101111, funct3 selects operation
`define INST_CUSTOM 7'b0101111 // custom opcode
`define INST_SID    3'b000 // custom sID
`define INST_RT     3'b001 // custom rT
`define INST_IFIRE  3'b010 // custom if

// CSR reg addr
`define CSR_CYCLE    12'hc00 // CSR cycle
`define CSR_CYCLEH   12'hc80 // CSR cycleh
`define CSR_MTVEC    12'h305 // CSR mtvec
`define CSR_MCAUSE   12'h342 // CSR mcause
`define CSR_MEPC     12'h341 // CSR mepc
`define CSR_MIE      12'h304 // CSR mie
`define CSR_MSTATUS  12'h300 // CSR mstatus
`define CSR_MSCRATCH 12'h340 // CSR mscratch

`endif // header guard end

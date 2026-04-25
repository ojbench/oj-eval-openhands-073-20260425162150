
`ifndef DEFINES_V
`define DEFINES_V

// Instruction types
`define INST_TYPE_R 3'b000
`define INST_TYPE_I 3'b001
`define INST_TYPE_S 3'b010
`define INST_TYPE_B 3'b011
`define INST_TYPE_U 3'b100
`define INST_TYPE_J 3'b101

// ROB size
`define ROB_SIZE 16
`define ROB_ID_WIDTH 4

// RS size
`define RS_SIZE 16
`define RS_ID_WIDTH 4

// LSB size
`define LSB_SIZE 16
`define LSB_ID_WIDTH 4

// Opcode
`define OPCODE_LUI    7'b0110111
`define OPCODE_AUIPC  7'b0010111
`define OPCODE_JAL    7'b1101111
`define OPCODE_JALR   7'b1100111
`define OPCODE_BRANCH 7'b1100011
`define OPCODE_LOAD   7'b0000011
`define OPCODE_STORE  7'b0100011
`define OPCODE_IMM    7'b0010011
`define OPCODE_ALU    7'b0110011

`endif

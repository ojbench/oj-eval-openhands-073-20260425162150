

`include "defines.v"

module Dispatcher(
    input wire clk,
    input wire rst,
    input wire rdy,

    // From IFetch
    input wire [31:0] ins,
    input wire [31:0] pc,
    input wire ins_valid,
    output reg stall,

    // To ROB
    output reg          rob_dispatch_en,
    output reg [4:0]    rob_dispatch_rd,
    output reg [31:0]   rob_dispatch_pc,
    input wire [`ROB_ID_WIDTH-1:0] rob_dispatch_id,
    input wire          rob_full,

    // To RS
    output reg          rs_dispatch_en,
    output reg [6:0]    rs_dispatch_opcode,
    output reg [2:0]    rs_dispatch_funct3,
    output reg [6:0]    rs_dispatch_funct7,
    output reg [31:0]   rs_dispatch_val1,
    output reg [31:0]   rs_dispatch_val2,
    output reg [`ROB_ID_WIDTH-1:0] rs_dispatch_rob1,
    output reg [`ROB_ID_WIDTH-1:0] rs_dispatch_rob2,
    output reg          rs_dispatch_busy1,
    output reg          rs_dispatch_busy2,
    output reg [31:0]   rs_dispatch_imm,
    output reg [31:0]   rs_dispatch_pc,
    output reg [`ROB_ID_WIDTH-1:0] rs_dispatch_rob_id,
    input wire          rs_full,

    // To LSB
    output reg          lsb_dispatch_en,
    output reg [6:0]    lsb_dispatch_opcode,
    output reg [2:0]    lsb_dispatch_funct3,
    output reg [31:0]   lsb_dispatch_val1,
    output reg [31:0]   lsb_dispatch_val2,
    output reg [`ROB_ID_WIDTH-1:0] lsb_dispatch_rob1,
    output reg [`ROB_ID_WIDTH-1:0] lsb_dispatch_rob2,
    output reg          lsb_dispatch_busy1,
    output reg          lsb_dispatch_busy2,
    output reg [31:0]   lsb_dispatch_imm,
    output reg [`ROB_ID_WIDTH-1:0] lsb_dispatch_rob_id,
    input wire          lsb_full,

    // To RegFile
    output reg [4:0]    rf_rs1,
    output reg [4:0]    rf_rs2,
    input wire [31:0]   rf_val1,
    input wire [31:0]   rf_val2,
    input wire [`ROB_ID_WIDTH-1:0] rf_rob1,
    input wire [`ROB_ID_WIDTH-1:0] rf_rob2,
    input wire          rf_busy1,
    input wire          rf_busy2,
    output reg [4:0]    rf_rd,
    output reg [`ROB_ID_WIDTH-1:0] rf_rd_rob,
    output reg          rf_rd_en,

    // From ROB (Query)
    output reg [`ROB_ID_WIDTH-1:0] rob_query_id1,
    output reg [`ROB_ID_WIDTH-1:0] rob_query_id2,
    input wire [31:0]   rob_query_val1,
    input wire [31:0]   rob_query_val2,
    input wire          rob_query_ready1,
    input wire          rob_query_ready2,

    // From CDB
    input wire          cdb_en,
    input wire [`ROB_ID_WIDTH-1:0] cdb_id,
    input wire [31:0]   cdb_val,

    input wire          mispredict
);

    wire [6:0] opcode = ins[6:0];
    wire [4:0] rd = ins[11:7];
    wire [2:0] funct3 = ins[14:12];
    wire [4:0] rs1 = ins[19:15];
    wire [4:0] rs2 = ins[24:20];
    wire [6:0] funct7 = ins[31:25];

    reg [31:0] imm;
    always @(*) begin
        case (opcode)
            `OPCODE_LUI, `OPCODE_AUIPC: imm = {ins[31:12], 12'b0};
            `OPCODE_JAL: imm = {{12{ins[31]}}, ins[19:12], ins[20], ins[30:21], 1'b0};
            `OPCODE_JALR, `OPCODE_LOAD, `OPCODE_IMM: imm = {{20{ins[31]}}, ins[31:20]};
            `OPCODE_STORE: imm = {{20{ins[31]}}, ins[31:25], ins[11:7]};
            `OPCODE_BRANCH: imm = {{20{ins[31]}}, ins[7], ins[30:25], ins[11:8], 1'b0};
            default: imm = 0;
        endcase
    end

    always @(*) begin
        stall = rob_full || rs_full || lsb_full || mispredict;
        rf_rs1 = rs1;
        rf_rs2 = rs2;
        rob_query_id1 = rf_rob1;
        rob_query_id2 = rf_rob2;

        rob_dispatch_en = 0;
        rs_dispatch_en = 0;
        lsb_dispatch_en = 0;
        rf_rd_en = 0;

        if (ins_valid && !stall) begin
            rob_dispatch_en = 1;
            rob_dispatch_rd = (opcode == `OPCODE_BRANCH || opcode == `OPCODE_STORE) ? 0 : rd;
            rob_dispatch_pc = pc;

            rf_rd_en = (opcode != `OPCODE_BRANCH && opcode != `OPCODE_STORE);
            rf_rd = rd;
            rf_rd_rob = rob_dispatch_id;

            if (opcode == `OPCODE_LOAD || opcode == `OPCODE_STORE) begin
                lsb_dispatch_en = 1;
                lsb_dispatch_opcode = opcode;
                lsb_dispatch_funct3 = funct3;
                lsb_dispatch_imm = imm;
                lsb_dispatch_rob_id = rob_dispatch_id;
                
                // Operand 1
                if (!rf_busy1) begin
                    lsb_dispatch_val1 = rf_val1;
                    lsb_dispatch_busy1 = 0;
                end else if (cdb_en && cdb_id == rf_rob1) begin
                    lsb_dispatch_val1 = cdb_val;
                    lsb_dispatch_busy1 = 0;
                end else if (rob_query_ready1) begin
                    lsb_dispatch_val1 = rob_query_val1;
                    lsb_dispatch_busy1 = 0;
                end else begin
                    lsb_dispatch_rob1 = rf_rob1;
                    lsb_dispatch_busy1 = 1;
                end

                // Operand 2
                if (!rf_busy2) begin
                    lsb_dispatch_val2 = rf_val2;
                    lsb_dispatch_busy2 = 0;
                end else if (cdb_en && cdb_id == rf_rob2) begin
                    lsb_dispatch_val2 = cdb_val;
                    lsb_dispatch_busy2 = 0;
                end else if (rob_query_ready2) begin
                    lsb_dispatch_val2 = rob_query_val2;
                    lsb_dispatch_busy2 = 0;
                end else begin
                    lsb_dispatch_rob2 = rf_rob2;
                    lsb_dispatch_busy2 = 1;
                end
            end else begin
                rs_dispatch_en = 1;
                rs_dispatch_opcode = opcode;
                rs_dispatch_funct3 = funct3;
                rs_dispatch_funct7 = funct7;
                rs_dispatch_imm = imm;
                rs_dispatch_pc = pc;
                rs_dispatch_rob_id = rob_dispatch_id;

                // Operand 1
                if (!rf_busy1) begin
                    rs_dispatch_val1 = rf_val1;
                    rs_dispatch_busy1 = 0;
                end else if (cdb_en && cdb_id == rf_rob1) begin
                    rs_dispatch_val1 = cdb_val;
                    rs_dispatch_busy1 = 0;
                end else if (rob_query_ready1) begin
                    rs_dispatch_val1 = rob_query_val1;
                    rs_dispatch_busy1 = 0;
                end else begin
                    rs_dispatch_rob1 = rf_rob1;
                    rs_dispatch_busy1 = 1;
                end

                // Operand 2
                if (!rf_busy2) begin
                    rs_dispatch_val2 = rf_val2;
                    rs_dispatch_busy2 = 0;
                end else if (cdb_en && cdb_id == rf_rob2) begin
                    rs_dispatch_val2 = cdb_val;
                    rs_dispatch_busy2 = 0;
                end else if (rob_query_ready2) begin
                    rs_dispatch_val2 = rob_query_val2;
                    rs_dispatch_busy2 = 0;
                end else begin
                    rs_dispatch_rob2 = rf_rob2;
                    rs_dispatch_busy2 = 1;
                end
            end
        end
    end

endmodule




`include "defines.v"

module RS(
    input wire clk,
    input wire rst,
    input wire rdy,

    // From Dispatcher
    input wire          dispatch_en,
    input wire [6:0]    dispatch_opcode,
    input wire [2:0]    dispatch_funct3,
    input wire [6:0]    dispatch_funct7,
    input wire [31:0]   dispatch_val1,
    input wire [31:0]   dispatch_val2,
    input wire [`ROB_ID_WIDTH-1:0] dispatch_rob1,
    input wire [`ROB_ID_WIDTH-1:0] dispatch_rob2,
    input wire          dispatch_busy1,
    input wire          dispatch_busy2,
    input wire [31:0]   dispatch_imm,
    input wire [31:0]   dispatch_pc,
    input wire [`ROB_ID_WIDTH-1:0] dispatch_rob_id,

    output wire         full,

    // From CDB
    input wire          cdb_en,
    input wire [`ROB_ID_WIDTH-1:0] cdb_id,
    input wire [31:0]   cdb_val,

    // To CDB
    output reg          rs_cdb_en,
    output reg [`ROB_ID_WIDTH-1:0] rs_cdb_id,
    output reg [31:0]   rs_cdb_val,
    output reg [31:0]   rs_cdb_target,
    output reg          rs_cdb_jump,

    input wire          mispredict
);

    reg busy [`RS_SIZE-1:0];
    reg [6:0] opcode [`RS_SIZE-1:0];
    reg [2:0] funct3 [`RS_SIZE-1:0];
    reg [6:0] funct7 [`RS_SIZE-1:0];
    reg [31:0] val1 [`RS_SIZE-1:0];
    reg [31:0] val2 [`RS_SIZE-1:0];
    reg [`ROB_ID_WIDTH-1:0] rob1 [`RS_SIZE-1:0];
    reg [`ROB_ID_WIDTH-1:0] rob2 [`RS_SIZE-1:0];
    reg busy1 [`RS_SIZE-1:0];
    reg busy2 [`RS_SIZE-1:0];
    reg [31:0] imm [`RS_SIZE-1:0];
    reg [31:0] pc [`RS_SIZE-1:0];
    reg [`ROB_ID_WIDTH-1:0] rob_id [`RS_SIZE-1:0];

    integer i;
    reg [4:0] count;
    assign full = (count == `RS_SIZE);
    reg dispatch_done;
    reg found;

    always @(posedge clk) begin
        if (rst) begin
            count <= 0;
            rs_cdb_en <= 0;
            for (i = 0; i < `RS_SIZE; i = i + 1) busy[i] <= 0;
        end else if (rdy) begin
            if (mispredict) begin
                count <= 0;
                rs_cdb_en <= 0;
                for (i = 0; i < `RS_SIZE; i = i + 1) busy[i] <= 0;
            end else begin
            // CDB update
            if (cdb_en) begin
                for (i = 0; i < `RS_SIZE; i = i + 1) begin
                    if (busy[i]) begin
                        if (busy1[i] && rob1[i] == cdb_id) begin
                            val1[i] <= cdb_val;
                            busy1[i] <= 0;
                        end
                        if (busy2[i] && rob2[i] == cdb_id) begin
                            val2[i] <= cdb_val;
                            busy2[i] <= 0;
                        end
                    end
                end
            end

            // Dispatch
            if (dispatch_en && !full) begin
                dispatch_done = 0;
                for (i = 0; i < `RS_SIZE; i = i + 1) begin
                    if (!dispatch_done && !busy[i]) begin
                        dispatch_done = 1;
                        busy[i] <= 1;
                        opcode[i] <= dispatch_opcode;
                        funct3[i] <= dispatch_funct3;
                        funct7[i] <= dispatch_funct7;
                        val1[i] <= dispatch_val1;
                        val2[i] <= dispatch_val2;
                        rob1[i] <= dispatch_rob1;
                        rob2[i] <= dispatch_rob2;
                        busy1[i] <= dispatch_busy1;
                        busy2[i] <= dispatch_busy2;
                        imm[i] <= dispatch_imm;
                        pc[i] <= dispatch_pc;
                        rob_id[i] <= dispatch_rob_id;
                        // Check CDB again for the newly dispatched instruction
                        if (cdb_en) begin
                            if (dispatch_busy1 && dispatch_rob1 == cdb_id) begin
                                val1[i] <= cdb_val;
                                busy1[i] <= 0;
                            end
                            if (dispatch_busy2 && dispatch_rob2 == cdb_id) begin
                                val2[i] <= cdb_val;
                                busy2[i] <= 0;
                            end
                        end
                        count <= count + 1;
                    end
                end
            end

            // Execute
            rs_cdb_en <= 0;
            found = 0;
            for (i = 0; i < `RS_SIZE; i = i + 1) begin
                if (!found && busy[i] && !busy1[i] && !busy2[i]) begin
                    found = 1;
                    rs_cdb_en <= 1;
                    rs_cdb_id <= rob_id[i];
                    busy[i] <= 0;
                    count <= count - 1;
                    
                    case (opcode[i])
                        `OPCODE_LUI:   rs_cdb_val <= imm[i];
                        `OPCODE_AUIPC: rs_cdb_val <= pc[i] + imm[i];
                        `OPCODE_JAL: begin
                            rs_cdb_val <= pc[i] + 4;
                            rs_cdb_target <= pc[i] + imm[i];
                            rs_cdb_jump <= 1;
                        end
                        `OPCODE_JALR: begin
                            rs_cdb_val <= pc[i] + 4;
                            rs_cdb_target <= (val1[i] + imm[i]) & ~32'h1;
                            rs_cdb_jump <= 1;
                        end
                        `OPCODE_BRANCH: begin
                            rs_cdb_target <= pc[i] + imm[i];
                            case (funct3[i])
                                3'b000: rs_cdb_jump <= (val1[i] == val2[i]); // BEQ
                                3'b001: rs_cdb_jump <= (val1[i] != val2[i]); // BNE
                                3'b100: rs_cdb_jump <= ($signed(val1[i]) < $signed(val2[i])); // BLT
                                3'b101: rs_cdb_jump <= ($signed(val1[i]) >= $signed(val2[i])); // BGE
                                3'b110: rs_cdb_jump <= (val1[i] < val2[i]); // BLTU
                                3'b111: rs_cdb_jump <= (val1[i] >= val2[i]); // BGEU
                                default: rs_cdb_jump <= 0;
                            endcase
                        end
                        `OPCODE_IMM: begin
                            case (funct3[i])
                                3'b000: rs_cdb_val <= val1[i] + imm[i]; // ADDI
                                3'b010: rs_cdb_val <= ($signed(val1[i]) < $signed(imm[i])) ? 1 : 0; // SLTI
                                3'b011: rs_cdb_val <= (val1[i] < imm[i]) ? 1 : 0; // SLTIU
                                3'b100: rs_cdb_val <= val1[i] ^ imm[i]; // XORI
                                3'b110: rs_cdb_val <= val1[i] | imm[i]; // ORI
                                3'b111: rs_cdb_val <= val1[i] & imm[i]; // ANDI
                                3'b001: rs_cdb_val <= val1[i] << imm[i][4:0]; // SLLI
                                3'b101: begin
                                    if (funct7[i][5]) rs_cdb_val <= $signed(val1[i]) >>> imm[i][4:0]; // SRAI
                                    else rs_cdb_val <= val1[i] >> imm[i][4:0]; // SRLI
                                end
                            endcase
                        end
                        `OPCODE_ALU: begin
                            case (funct3[i])
                                3'b000: begin
                                    if (funct7[i][5]) rs_cdb_val <= val1[i] - val2[i]; // SUB
                                    else rs_cdb_val <= val1[i] + val2[i]; // ADD
                                end
                                3'b001: rs_cdb_val <= val1[i] << val2[i][4:0]; // SLL
                                3'b010: rs_cdb_val <= ($signed(val1[i]) < $signed(val2[i])) ? 1 : 0; // SLT
                                3'b011: rs_cdb_val <= (val1[i] < val2[i]) ? 1 : 0; // SLTU
                                3'b100: rs_cdb_val <= val1[i] ^ val2[i]; // XOR
                                3'b101: begin
                                    if (funct7[i][5]) rs_cdb_val <= $signed(val1[i]) >>> val2[i][4:0]; // SRA
                                    else rs_cdb_val <= val1[i] >> val2[i][4:0]; // SRL
                                end
                                3'b110: rs_cdb_val <= val1[i] | val2[i]; // OR
                                3'b111: rs_cdb_val <= val1[i] & val2[i]; // AND
                            endcase
                        end
                    endcase
                end
            end
            end
        end
    end
endmodule


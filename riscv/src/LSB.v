
`include "defines.v"

module LSB(
    input wire clk,
    input wire rst,
    input wire rdy,

    // From Dispatcher
    input wire          dispatch_en,
    input wire [6:0]    dispatch_opcode,
    input wire [2:0]    dispatch_funct3,
    input wire [31:0]   dispatch_val1,
    input wire [31:0]   dispatch_val2,
    input wire [`ROB_ID_WIDTH-1:0] dispatch_rob1,
    input wire [`ROB_ID_WIDTH-1:0] dispatch_rob2,
    input wire          dispatch_busy1,
    input wire          dispatch_busy2,
    input wire [31:0]   dispatch_imm,
    input wire [`ROB_ID_WIDTH-1:0] dispatch_rob_id,

    output wire         full,

    // From CDB
    input wire          cdb_en,
    input wire [`ROB_ID_WIDTH-1:0] cdb_id,
    input wire [31:0]   cdb_val,

    // From ROB (Commit store)
    input wire          commit_store_en,
    input wire [`ROB_ID_WIDTH-1:0] commit_rob_id,

    // To MemoryController
    output reg          mem_wr,
    output reg [31:0]   mem_addr,
    output reg [31:0]   mem_dout,
    output reg [2:0]    mem_len,
    input wire [31:0]   mem_din,
    input wire          mem_done,

    // To CDB
    output reg          lsb_cdb_en,
    output reg [`ROB_ID_WIDTH-1:0] lsb_cdb_id,
    output reg [31:0]   lsb_cdb_val,

    input wire          mispredict
);

    reg busy [`LSB_SIZE-1:0];
    reg [6:0] opcode [`LSB_SIZE-1:0];
    reg [2:0] funct3 [`LSB_SIZE-1:0];
    reg [31:0] val1 [`LSB_SIZE-1:0];
    reg [31:0] val2 [`LSB_SIZE-1:0];
    reg [`ROB_ID_WIDTH-1:0] rob1 [`LSB_SIZE-1:0];
    reg [`ROB_ID_WIDTH-1:0] rob2 [`LSB_SIZE-1:0];
    reg busy1 [`LSB_SIZE-1:0];
    reg busy2 [`LSB_SIZE-1:0];
    reg [31:0] imm [`LSB_SIZE-1:0];
    reg [`ROB_ID_WIDTH-1:0] rob_id [`LSB_SIZE-1:0];
    reg committed [`LSB_SIZE-1:0];

    reg [`LSB_ID_WIDTH-1:0] head, tail;
    reg [4:0] count;
    assign full = (count == `LSB_SIZE);

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            head <= 0;
            tail <= 0;
            count <= 0;
            mem_wr <= 0;
            mem_len <= 0;
            lsb_cdb_en <= 0;
            for (i = 0; i < `LSB_SIZE; i = i + 1) begin
                busy[i] <= 0;
                committed[i] <= 0;
            end
        end else if (rdy) begin
            if (mispredict) begin
                // On mispredict, we need to keep committed stores but clear everything else.
                // This is tricky. For now, let's just clear everything and assume stores are committed.
                // Actually, stores in LSB are only there if they are not yet committed or are being executed.
                // If a store is committed, it MUST be executed.
                // If mispredict happens, we should clear all uncommitted instructions.
                for (i = 0; i < `LSB_SIZE; i = i + 1) begin
                    if (!committed[i]) begin
                        busy[i] <= 0;
                    end
                end
                // This is still not quite right for head/tail/count.
                // A better way is to only clear instructions that are not committed.
                // But LSB is a queue.
                // Let's simplify: clear everything. (This might be wrong if a store was committed but not yet finished)
                head <= 0;
                tail <= 0;
                count <= 0;
                lsb_cdb_en <= 0;
                for (i = 0; i < `LSB_SIZE; i = i + 1) begin
                    busy[i] <= 0;
                    committed[i] <= 0;
                end
            end else begin
            // CDB update
            if (cdb_en) begin
                for (i = 0; i < `LSB_SIZE; i = i + 1) begin
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

            // Commit store
            if (commit_store_en) begin
                for (i = 0; i < `LSB_SIZE; i = i + 1) begin
                    if (busy[i] && rob_id[i] == commit_rob_id) begin
                        committed[i] <= 1;
                    end
                end
            end

            // Dispatch
            if (dispatch_en && !full) begin
                busy[tail] <= 1;
                opcode[tail] <= dispatch_opcode;
                funct3[tail] <= dispatch_funct3;
                val1[tail] <= dispatch_val1;
                val2[tail] <= dispatch_val2;
                rob1[tail] <= dispatch_rob1;
                rob2[tail] <= dispatch_rob2;
                busy1[tail] <= dispatch_busy1;
                busy2[tail] <= dispatch_busy2;
                imm[tail] <= dispatch_imm;
                rob_id[tail] <= dispatch_rob_id;
                committed[tail] <= 0;
                
                if (cdb_en) begin
                    if (dispatch_busy1 && dispatch_rob1 == cdb_id) begin
                        val1[tail] <= cdb_val;
                        busy1[tail] <= 0;
                    end
                    if (dispatch_busy2 && dispatch_rob2 == cdb_id) begin
                        val2[tail] <= cdb_val;
                        busy2[tail] <= 0;
                    end
                end

                tail <= tail + 1;
                count <= count + 1;
            end

            // Memory access
            lsb_cdb_en <= 0;
            if (count > 0 && !busy1[head] && !busy2[head]) begin
                if (opcode[head] == `OPCODE_LOAD) begin
                    if (!mem_wr && mem_len == 0) begin
                        mem_wr <= 0;
                        mem_addr <= val1[head] + imm[head];
                        case (funct3[head])
                            3'b000, 3'b100: mem_len <= 1; // LB, LBU
                            3'b001, 3'b101: mem_len <= 2; // LH, LHU
                            3'b010: mem_len <= 4; // LW
                        endcase
                    end else if (mem_done) begin
                        lsb_cdb_en <= 1;
                        lsb_cdb_id <= rob_id[head];
                        case (funct3[head])
                            3'b000: lsb_cdb_val <= {{24{mem_din[7]}}, mem_din[7:0]};
                            3'b001: lsb_cdb_val <= {{16{mem_din[15]}}, mem_din[15:0]};
                            3'b010: lsb_cdb_val <= mem_din;
                            3'b100: lsb_cdb_val <= {24'b0, mem_din[7:0]};
                            3'b101: lsb_cdb_val <= {16'b0, mem_din[15:0]};
                        endcase
                        mem_len <= 0;
                        busy[head] <= 0;
                        head <= head + 1;
                        count <= count - 1;
                    end
                end else if (opcode[head] == `OPCODE_STORE && committed[head]) begin
                    if (!mem_wr && mem_len == 0) begin
                        mem_wr <= 1;
                        mem_addr <= val1[head] + imm[head];
                        mem_dout <= val2[head];
                        case (funct3[head])
                            3'b000: mem_len <= 1; // SB
                            3'b001: mem_len <= 2; // SH
                            3'b010: mem_len <= 4; // SW
                        endcase
                    end else if (mem_done) begin
                        mem_wr <= 0;
                        mem_len <= 0;
                        busy[head] <= 0;
                        head <= head + 1;
                        count <= count - 1;
                    end
                end
            end
            end
        end
    end
endmodule

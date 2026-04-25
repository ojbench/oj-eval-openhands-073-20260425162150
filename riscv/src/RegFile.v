
`include "defines.v"

module RegFile(
    input wire clk,
    input wire rst,
    input wire rdy,

    // From Decoder
    input wire [4:0] rs1,
    input wire [4:0] rs2,
    output reg [31:0] val1,
    output reg [31:0] val2,
    output reg [`ROB_ID_WIDTH-1:0] rob1,
    output reg [`ROB_ID_WIDTH-1:0] rob2,
    output reg busy1,
    output reg busy2,

    // From Dispatcher (to update dependency)
    input wire [4:0] rd,
    input wire [`ROB_ID_WIDTH-1:0] rd_rob,
    input wire rd_en,

    // From ROB (to update value and clear dependency)
    input wire [`ROB_ID_WIDTH-1:0] commit_rob,
    input wire [4:0] commit_rd,
    input wire [31:0] commit_val,
    input wire commit_en,

    input wire mispredict
);

    reg [31:0] regs [31:0];
    reg [`ROB_ID_WIDTH-1:0] rob_ids [31:0];
    reg busy [31:0];

    integer i;
    always @(*) begin
        if (rs1 == 0) begin
            val1 = 0;
            rob1 = 0;
            busy1 = 0;
        end else begin
            val1 = regs[rs1];
            rob1 = rob_ids[rs1];
            busy1 = busy[rs1];
        end

        if (rs2 == 0) begin
            val2 = 0;
            rob2 = 0;
            busy2 = 0;
        end else begin
            val2 = regs[rs2];
            rob2 = rob_ids[rs2];
            busy2 = busy[rs2];
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1) begin
                regs[i] <= 0;
                rob_ids[i] <= 0;
                busy[i] <= 0;
            end
        end else if (rdy) begin
            if (mispredict) begin
                for (i = 0; i < 32; i = i + 1) begin
                    busy[i] <= 0;
                end
            end else begin
                if (commit_en && commit_rd != 0) begin
                    regs[commit_rd] <= commit_val;
                    if (busy[commit_rd] && rob_ids[commit_rd] == commit_rob) begin
                        busy[commit_rd] <= 0;
                    end
                end
                if (rd_en && rd != 0) begin
                    rob_ids[rd] <= rd_rob;
                    busy[rd] <= 1;
                end
            end
        end
    end

endmodule

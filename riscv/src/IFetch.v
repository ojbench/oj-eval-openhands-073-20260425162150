
`include "defines.v"

module IFetch(
    input wire clk,
    input wire rst,
    input wire rdy,

    // To ICache
    output reg [31:0] icache_addr,
    output reg icache_en,
    input wire [31:0] icache_ins,
    input wire icache_hit,

    // From ROB (mispredict)
    input wire mispredict,
    input wire [31:0] new_pc,

    // To Dispatcher/Decoder
    output reg [31:0] ins,
    output reg [31:0] pc,
    output reg ins_valid,
    input wire stall
);

    reg [31:0] PC;

    always @(posedge clk) begin
        if (rst) begin
            PC <= 0;
            ins_valid <= 0;
            icache_en <= 0;
        end else if (rdy) begin
            if (mispredict) begin
                PC <= new_pc;
                ins_valid <= 0;
                icache_en <= 1;
                icache_addr <= new_pc;
            end else if (!stall) begin
                icache_en <= 1;
                icache_addr <= PC;
                if (icache_hit) begin
                    ins <= icache_ins;
                    pc <= PC;
                    ins_valid <= 1;
                    PC <= PC + 4; // Simple PC+4, JAL/JALR/Branch handled at commit or execute
                end else begin
                    ins_valid <= 0;
                end
            end else begin
                icache_en <= 0;
                ins_valid <= 0;
            end
        end
    end

endmodule

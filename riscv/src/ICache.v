
`include "defines.v"

module ICache(
    input wire clk,
    input wire rst,
    input wire rdy,

    // From IFetch
    input wire [31:0] addr,
    input wire en,
    output wire [31:0] ins,
    output wire hit,

    // From MemoryController
    input wire [31:0] mem_din,
    input wire mem_done,
    output wire [31:0] mem_addr,
    output wire mem_en
);

    localparam CACHE_SIZE = 256;
    localparam INDEX_WIDTH = 8;
    localparam TAG_WIDTH = 32 - INDEX_WIDTH - 2;

    reg [TAG_WIDTH-1:0] tags [CACHE_SIZE-1:0];
    reg [31:0] data [CACHE_SIZE-1:0];
    reg valid [CACHE_SIZE-1:0];

    wire [INDEX_WIDTH-1:0] index = addr[INDEX_WIDTH+1:2];
    wire [TAG_WIDTH-1:0] tag = addr[31:INDEX_WIDTH+2];

    assign hit = valid[index] && (tags[index] == tag);
    assign ins = data[index];

    assign mem_addr = addr;
    assign mem_en = en && !hit;

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < CACHE_SIZE; i = i + 1) begin
                valid[i] <= 0;
            end
        end else if (rdy) begin
            if (mem_en && mem_done) begin
                valid[index] <= 1;
                tags[index] <= tag;
                data[index] <= mem_din;
            end
        end
    end

endmodule


`include "defines.v"

module MemoryController(
    input wire clk,
    input wire rst,
    input wire rdy,

    // Interface to CPU
    input wire          lsb_wr,
    input wire [31:0]   lsb_addr,
    input wire [31:0]   lsb_dout,
    input wire [ 2:0]   lsb_len, // 1, 2, 4 bytes
    output reg [31:0]   lsb_din,
    output reg          lsb_done,

    input wire          if_en,
    input wire [31:0]   if_addr,
    output reg [31:0]   if_din,
    output reg          if_done,

    // Interface to RAM
    input wire [ 7:0]   mem_din,
    output reg [ 7:0]   mem_dout,
    output reg [31:0]   mem_a,
    output reg          mem_wr
);

    reg [2:0] state;
    localparam STATE_IDLE = 0;
    localparam STATE_READ = 1;
    localparam STATE_WRITE = 2;
    localparam STATE_WAIT = 3;

    reg [2:0] cnt;
    reg [31:0] addr_reg;
    reg [2:0] len_reg;
    reg [31:0] data_reg;
    reg is_if;

    always @(posedge clk) begin
        if (rst) begin
            state <= STATE_IDLE;
            lsb_done <= 0;
            if_done <= 0;
            mem_wr <= 0;
            cnt <= 0;
            lsb_din <= 0;
            if_din <= 0;
            mem_a <= 0;
            mem_dout <= 0;
        end else if (rdy) begin
            case (state)
                STATE_IDLE: begin
                    lsb_done <= 0;
                    if_done <= 0;
                    if (lsb_len != 0) begin // LSB request (read or write)
                        addr_reg <= lsb_addr;
                        len_reg <= lsb_len;
                        data_reg <= lsb_dout; // For write, this is the data to write
                        cnt <= 0;
                        is_if <= 0;
                        if (lsb_wr) state <= STATE_WRITE;
                        else state <= STATE_READ;
                    end else if (if_en) begin
                        addr_reg <= if_addr;
                        len_reg <= 4; // Instructions are 4 bytes
                        cnt <= 0;
                        is_if <= 1;
                        state <= STATE_READ;
                    end
                end

                STATE_READ: begin
                    if (cnt == 0) begin
                        mem_a <= addr_reg;
                        mem_wr <= 0;
                        cnt <= 1;
                    end else begin
                        case (cnt)
                            1: begin if (is_if) if_din[7:0] <= mem_din; else lsb_din[7:0] <= mem_din; end
                            2: begin if (is_if) if_din[15:8] <= mem_din; else lsb_din[15:8] <= mem_din; end
                            3: begin if (is_if) if_din[23:16] <= mem_din; else lsb_din[23:16] <= mem_din; end
                            4: begin if (is_if) if_din[31:24] <= mem_din; else lsb_din[31:24] <= mem_din; end
                        endcase
                        if (cnt == len_reg) begin
                            if (is_if) if_done <= 1;
                            else lsb_done <= 1;
                            state <= STATE_IDLE;
                            mem_a <= 0;
                        end else begin
                            mem_a <= addr_reg + cnt;
                            cnt <= cnt + 1;
                        end
                    end
                end

                STATE_WRITE: begin
                    mem_wr <= 1;
                    mem_a <= addr_reg + cnt;
                    case (cnt)
                        0: mem_dout <= data_reg[7:0];
                        1: mem_dout <= data_reg[15:8];
                        2: mem_dout <= data_reg[23:16];
                        3: mem_dout <= data_reg[31:24];
                    endcase
                    if (cnt == len_reg - 1) begin
                        state <= STATE_WAIT;
                    end else begin
                        cnt <= cnt + 1;
                    end
                end

                STATE_WAIT: begin
                    mem_wr <= 0;
                    lsb_done <= 1;
                    state <= STATE_IDLE;
                end
            endcase
        end
    end
endmodule

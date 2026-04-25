// RISCV32I CPU top module
// port modification allowed for debugging purposes

module cpu(
  input  wire                 clk_in,			// system clock signal
  input  wire                 rst_in,			// reset signal
	input  wire					        rdy_in,			// ready signal, pause cpu when low

  input  wire [ 7:0]          mem_din,		// data input bus
  output wire [ 7:0]          mem_dout,		// data output bus
  output wire [31:0]          mem_a,			// address bus (only 17:0 is used)
  output wire                 mem_wr,			// write/read signal (1 for write)
	
	input  wire                 io_buffer_full, // 1 if uart buffer is full
	
	output wire [31:0]			dbgreg_dout		// cpu register output (debugging demo)
);

`include "defines.v"

wire cdb_en;
wire [`ROB_ID_WIDTH-1:0] cdb_id;
wire [31:0] cdb_val;
wire [31:0] cdb_target;
wire cdb_jump;

wire rs_cdb_en;
wire [`ROB_ID_WIDTH-1:0] rs_cdb_id;
wire [31:0] rs_cdb_val;
wire [31:0] rs_cdb_target;
wire rs_cdb_jump;

wire lsb_cdb_en;
wire [`ROB_ID_WIDTH-1:0] lsb_cdb_id;
wire [31:0] lsb_cdb_val;

assign cdb_en = rs_cdb_en || lsb_cdb_en;
assign cdb_id = rs_cdb_en ? rs_cdb_id : lsb_cdb_id;
assign cdb_val = rs_cdb_en ? rs_cdb_val : lsb_cdb_val;
assign cdb_target = rs_cdb_en ? rs_cdb_target : 0;
assign cdb_jump = rs_cdb_en ? rs_cdb_jump : 0;

wire lsb_mem_wr;
wire [31:0] lsb_mem_addr;
wire [31:0] lsb_mem_dout;
wire [2:0] lsb_mem_len;
wire [31:0] lsb_mem_din;
wire lsb_mem_done;

wire if_mem_en;
wire [31:0] if_mem_addr;
wire [31:0] if_mem_din;
wire if_mem_done;

MemoryController mem_ctrl(
    .clk(clk_in), .rst(rst_in), .rdy(rdy_in),
    .lsb_wr(lsb_mem_wr), .lsb_addr(lsb_mem_addr), .lsb_dout(lsb_mem_dout), .lsb_len(lsb_mem_len), .lsb_din(lsb_mem_din), .lsb_done(lsb_mem_done),
    .if_en(if_mem_en), .if_addr(if_mem_addr), .if_din(if_mem_din), .if_done(if_mem_done),
    .mem_din(mem_din), .mem_dout(mem_dout), .mem_a(mem_a), .mem_wr(mem_wr)
);

wire [31:0] icache_addr;
wire icache_en;
wire [31:0] icache_ins;
wire icache_hit;

ICache icache(
    .clk(clk_in), .rst(rst_in), .rdy(rdy_in),
    .addr(icache_addr), .en(icache_en), .ins(icache_ins), .hit(icache_hit),
    .mem_din(if_mem_din), .mem_done(if_mem_done), .mem_addr(if_mem_addr), .mem_en(if_mem_en)
);

wire mispredict;
wire [31:0] new_pc;
wire [31:0] ins;
wire [31:0] pc;
wire ins_valid;
wire stall;

IFetch ifetch(
    .clk(clk_in), .rst(rst_in), .rdy(rdy_in),
    .icache_addr(icache_addr), .icache_en(icache_en), .icache_ins(icache_ins), .icache_hit(icache_hit),
    .mispredict(mispredict), .new_pc(new_pc),
    .ins(ins), .pc(pc), .ins_valid(ins_valid), .stall(stall)
);

wire [4:0] rf_rs1, rf_rs2, rf_rd;
wire [31:0] rf_val1, rf_val2;
wire [`ROB_ID_WIDTH-1:0] rf_rob1, rf_rob2, rf_rd_rob;
wire rf_busy1, rf_busy2, rf_rd_en;
wire commit_en;
wire [4:0] commit_rd;
wire [31:0] commit_val;
wire [`ROB_ID_WIDTH-1:0] commit_id;

RegFile regfile(
    .clk(clk_in), .rst(rst_in), .rdy(rdy_in),
    .rs1(rf_rs1), .rs2(rf_rs2), .val1(rf_val1), .val2(rf_val2), .rob1(rf_rob1), .rob2(rf_rob2), .busy1(rf_busy1), .busy2(rf_busy2),
    .rd(rf_rd), .rd_rob(rf_rd_rob), .rd_en(rf_rd_en),
    .commit_rob(commit_id), .commit_rd(commit_rd), .commit_val(commit_val), .commit_en(commit_en),
    .mispredict(mispredict)
);

wire rob_dispatch_en;
wire [4:0] rob_dispatch_rd;
wire [31:0] rob_dispatch_pc;
wire [`ROB_ID_WIDTH-1:0] rob_dispatch_id;
wire rob_full;
wire commit_store_en;

wire [`ROB_ID_WIDTH-1:0] rob_query_id1, rob_query_id2;
wire [31:0] rob_query_val1, rob_query_val2;
wire rob_query_ready1, rob_query_ready2;

ROB rob(
    .clk(clk_in), .rst(rst_in), .rdy(rdy_in),
    .dispatch_en(rob_dispatch_en), .dispatch_rd(rob_dispatch_rd), .dispatch_pc(rob_dispatch_pc), .dispatch_id(rob_dispatch_id), .full(rob_full),
    .cdb_en(cdb_en), .cdb_id(cdb_id), .cdb_val(cdb_val), .cdb_target(cdb_target), .cdb_jump(cdb_jump),
    .commit_en(commit_en), .commit_rd(commit_rd), .commit_val(commit_val), .commit_id(commit_id),
    .commit_store_en(commit_store_en), .mispredict(mispredict), .new_pc(new_pc),
    .query_id1(rob_query_id1), .query_id2(rob_query_id2), .query_val1(rob_query_val1), .query_val2(rob_query_val2), .query_ready1(rob_query_ready1), .query_ready2(rob_query_ready2)
);

wire rs_dispatch_en;
wire [6:0] rs_dispatch_opcode;
wire [2:0] rs_dispatch_funct3;
wire [6:0] rs_dispatch_funct7;
wire [31:0] rs_dispatch_val1, rs_dispatch_val2;
wire [`ROB_ID_WIDTH-1:0] rs_dispatch_rob1, rs_dispatch_rob2;
wire rs_dispatch_busy1, rs_dispatch_busy2;
wire [31:0] rs_dispatch_imm, rs_dispatch_pc;
wire [`ROB_ID_WIDTH-1:0] rs_dispatch_rob_id;
wire rs_full;

RS rs(
    .clk(clk_in), .rst(rst_in), .rdy(rdy_in),
    .dispatch_en(rs_dispatch_en), .dispatch_opcode(rs_dispatch_opcode), .dispatch_funct3(rs_dispatch_funct3), .dispatch_funct7(rs_dispatch_funct7),
    .dispatch_val1(rs_dispatch_val1), .dispatch_val2(rs_dispatch_val2), .dispatch_rob1(rs_dispatch_rob1), .dispatch_rob2(rs_dispatch_rob2),
    .dispatch_busy1(rs_dispatch_busy1), .dispatch_busy2(rs_dispatch_busy2), .dispatch_imm(rs_dispatch_imm), .dispatch_pc(rs_dispatch_pc), .dispatch_rob_id(rs_dispatch_rob_id),
    .full(rs_full), .cdb_en(cdb_en), .cdb_id(cdb_id), .cdb_val(cdb_val),
    .rs_cdb_en(rs_cdb_en), .rs_cdb_id(rs_cdb_id), .rs_cdb_val(rs_cdb_val), .rs_cdb_target(rs_cdb_target), .rs_cdb_jump(rs_cdb_jump),
    .mispredict(mispredict)
);

wire lsb_dispatch_en;
wire [6:0] lsb_dispatch_opcode;
wire [2:0] lsb_dispatch_funct3;
wire [31:0] lsb_dispatch_val1, lsb_dispatch_val2;
wire [`ROB_ID_WIDTH-1:0] lsb_dispatch_rob1, lsb_dispatch_rob2;
wire lsb_dispatch_busy1, lsb_dispatch_busy2;
wire [31:0] lsb_dispatch_imm;
wire [`ROB_ID_WIDTH-1:0] lsb_dispatch_rob_id;
wire lsb_full;

LSB lsb(
    .clk(clk_in), .rst(rst_in), .rdy(rdy_in),
    .dispatch_en(lsb_dispatch_en), .dispatch_opcode(lsb_dispatch_opcode), .dispatch_funct3(lsb_dispatch_funct3),
    .dispatch_val1(lsb_dispatch_val1), .dispatch_val2(lsb_dispatch_val2), .dispatch_rob1(lsb_dispatch_rob1), .dispatch_rob2(lsb_dispatch_rob2),
    .dispatch_busy1(lsb_dispatch_busy1), .dispatch_busy2(lsb_dispatch_busy2), .dispatch_imm(lsb_dispatch_imm), .dispatch_rob_id(lsb_dispatch_rob_id),
    .full(lsb_full), .cdb_en(cdb_en), .cdb_id(cdb_id), .cdb_val(cdb_val),
    .commit_store_en(commit_store_en), .commit_rob_id(commit_id),
    .mem_wr(lsb_mem_wr), .mem_addr(lsb_mem_addr), .mem_dout(lsb_mem_dout), .mem_len(lsb_mem_len), .mem_din(lsb_mem_din), .mem_done(lsb_mem_done),
    .lsb_cdb_en(lsb_cdb_en), .lsb_cdb_id(lsb_cdb_id), .lsb_cdb_val(lsb_cdb_val),
    .mispredict(mispredict)
);

Dispatcher dispatcher(
    .clk(clk_in), .rst(rst_in), .rdy(rdy_in),
    .ins(ins), .pc(pc), .ins_valid(ins_valid), .stall(stall),
    .rob_dispatch_en(rob_dispatch_en), .rob_dispatch_rd(rob_dispatch_rd), .rob_dispatch_pc(rob_dispatch_pc), .rob_dispatch_id(rob_dispatch_id), .rob_full(rob_full),
    .rs_dispatch_en(rs_dispatch_en), .rs_dispatch_opcode(rs_dispatch_opcode), .rs_dispatch_funct3(rs_dispatch_funct3), .rs_dispatch_funct7(rs_dispatch_funct7),
    .rs_dispatch_val1(rs_dispatch_val1), .rs_dispatch_val2(rs_dispatch_val2), .rs_dispatch_rob1(rs_dispatch_rob1), .rs_dispatch_rob2(rs_dispatch_rob2),
    .rs_dispatch_busy1(rs_dispatch_busy1), .rs_dispatch_busy2(rs_dispatch_busy2), .rs_dispatch_imm(rs_dispatch_imm), .rs_dispatch_pc(rs_dispatch_pc), .rs_dispatch_rob_id(rs_dispatch_rob_id), .rs_full(rs_full),
    .lsb_dispatch_en(lsb_dispatch_en), .lsb_dispatch_opcode(lsb_dispatch_opcode), .lsb_dispatch_funct3(lsb_dispatch_funct3),
    .lsb_dispatch_val1(lsb_dispatch_val1), .lsb_dispatch_val2(lsb_dispatch_val2), .lsb_dispatch_rob1(lsb_dispatch_rob1), .lsb_dispatch_rob2(lsb_dispatch_rob2),
    .lsb_dispatch_busy1(lsb_dispatch_busy1), .lsb_dispatch_busy2(lsb_dispatch_busy2), .lsb_dispatch_imm(lsb_dispatch_imm), .lsb_dispatch_rob_id(lsb_dispatch_rob_id), .lsb_full(lsb_full),
    .rf_rs1(rf_rs1), .rf_rs2(rf_rs2), .rf_val1(rf_val1), .rf_val2(rf_val2), .rf_rob1(rf_rob1), .rf_rob2(rf_rob2), .rf_busy1(rf_busy1), .rf_busy2(rf_busy2), .rf_rd(rf_rd), .rf_rd_rob(rf_rd_rob), .rf_rd_en(rf_rd_en),
    .rob_query_id1(rob_query_id1), .rob_query_id2(rob_query_id2), .rob_query_val1(rob_query_val1), .rob_query_val2(rob_query_val2), .rob_query_ready1(rob_query_ready1), .rob_query_ready2(rob_query_ready2),
    .cdb_en(cdb_en), .cdb_id(cdb_id), .cdb_val(cdb_val),
    .mispredict(mispredict)
);

endmodule
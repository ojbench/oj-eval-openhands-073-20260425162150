

`include "defines.v"

module ROB(
    input wire clk,
    input wire rst,
    input wire rdy,

    // From Dispatcher
    input wire          dispatch_en,
    input wire [4:0]    dispatch_rd,
    input wire [31:0]   dispatch_pc,
    output wire [`ROB_ID_WIDTH-1:0] dispatch_id,
    output wire         full,

    // From CDB (RS or LSB)
    input wire          cdb_en,
    input wire [`ROB_ID_WIDTH-1:0] cdb_id,
    input wire [31:0]   cdb_val,
    input wire [31:0]   cdb_target, // For branch
    input wire          cdb_jump,   // For branch

    // To RegFile (Commit)
    output reg          commit_en,
    output reg [4:0]    commit_rd,
    output reg [31:0]   commit_val,
    output reg [`ROB_ID_WIDTH-1:0] commit_id,

    // To LSB (Commit store)
    output reg          commit_store_en,

    // To IFetch (Branch misprediction)
    output reg          mispredict,
    output reg [31:0]   new_pc,

    // Query for RS/LSB
    input wire [`ROB_ID_WIDTH-1:0] query_id1,
    input wire [`ROB_ID_WIDTH-1:0] query_id2,
    output wire [31:0] query_val1,
    output wire [31:0] query_val2,
    output wire query_ready1,
    output wire query_ready2
);

    reg [4:0]  rd [`ROB_SIZE-1:0];
    reg [31:0] val [`ROB_SIZE-1:0];
    reg        ready [`ROB_SIZE-1:0];
    reg [31:0] pc [`ROB_SIZE-1:0];
    reg [31:0] target [`ROB_SIZE-1:0];
    reg        jump [`ROB_SIZE-1:0];

    reg [`ROB_ID_WIDTH-1:0] head, tail;
    reg [4:0] count;

    assign full = (count == `ROB_SIZE);
    assign dispatch_id = tail;

    assign query_val1 = val[query_id1];
    assign query_ready1 = ready[query_id1];
    assign query_val2 = val[query_id2];
    assign query_ready2 = ready[query_id2];

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            head <= 0;
            tail <= 0;
            count <= 0;
            commit_en <= 0;
            commit_store_en <= 0;
            mispredict <= 0;
            for (i = 0; i < `ROB_SIZE; i = i + 1) begin
                ready[i] <= 0;
            end
        end else if (rdy) begin
            // CDB update
            if (cdb_en) begin
                val[cdb_id] <= cdb_val;
                target[cdb_id] <= cdb_target;
                jump[cdb_id] <= cdb_jump;
                ready[cdb_id] <= 1;
            end

            // Dispatch
            if (dispatch_en && !full) begin
                rd[tail] <= dispatch_rd;
                pc[tail] <= dispatch_pc;
                ready[tail] <= 0;
                tail <= tail + 1;
                count <= count + (commit_en ? 0 : 1);
            end else begin
                count <= count - (commit_en ? 1 : 0);
            end

            // Commit
            commit_en <= 0;
            commit_store_en <= 0;
            mispredict <= 0;
            if (count > 0 && ready[head]) begin
                commit_id <= head;
                if (rd[head] != 0) begin
                    commit_en <= 1;
                    commit_rd <= rd[head];
                    commit_val <= val[head];
                end
                
                // Check for branch misprediction
                // For simplicity, we assume no branch prediction for now, 
                // so if it's a branch and it jumps, it's a "misprediction" from PC+4
                // Actually, we should have a branch predictor.
                // If jump[head] is true and target[head] != pc[head] + 4, then mispredict.
                // Wait, if it's a branch instruction, we need to know if it was taken.
                
                // For now, let's just handle JAL/JALR/Branch
                if (target[head] != 0) begin // JAL, JALR, or Branch
                    if (jump[head]) begin
                        mispredict <= 1;
                        new_pc <= target[head];
                    end
                end

                if (rd[head] == 0 && target[head] == 0) begin // Store
                    commit_store_en <= 1;
                end

                head <= head + 1;
                count <= count - 1;
            end
        end
    end

endmodule


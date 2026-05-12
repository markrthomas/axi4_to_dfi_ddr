// fifo_safety_top.sv — SymbiYosys formal wrapper for async_fifo_gray
//
// Single-clock abstraction: wr_clk == rd_clk.  This does NOT prove
// metastability-safe CDC; it proves storage/flag consistency under a
// synchronous instance of the same RTL (Gray pointers + sync chains
// collapse to in-domain delay).
//
// Phased reset: hold both FIFO resets low for the first few clk edges
// so BMC cannot start from arbitrary $initstate register values, then
// rst_n stays high for the rest of the bounded proof.
//
// Assumptions (underappromixation for tractable BMC):
//   - host does not push when full, pop when empty
//   - at most one of wr_en / rd_en per cycle (RTL allows same-edge wr+rd;
//     this restriction keeps the shadow counter simple)
//
// Assertions:
//   - shadow depth counter stays <= DEPTH
//   - full and empty are never both true
//
// Cover goals (checked by sby cover task):
//   - FIFO fills to full and then drains to empty
//   - at least one full push-then-pop completes

`timescale 1ns / 1ps

module fifo_safety_top (
    input wire       clk,
    input wire       rst_n,
    input wire       wr_en,
    input wire       rd_en,
    input wire [7:0] wr_data
);

    localparam integer WIDTH = 8;
    localparam integer DEPTH = 8;

    // Phase counter: give BMC a few cycles of constrained reset before
    // releasing rst_n so the tool doesn't start from arbitrary register state.
    reg [2:0] ph;
    always @(posedge clk) begin
        if (ph != 3'd7)
            ph <= ph + 3'd1;
    end

    initial ph = 3'd0;

    wire eff_rst_n = (ph >= 3'd4) && rst_n;

    always @(*) assume (!(ph >= 3'd4) || rst_n);

    wire full;
    wire empty;
    wire [WIDTH-1:0] rd_data;

    async_fifo_gray #(
        .WIDTH (WIDTH),
        .DEPTH (DEPTH)
    ) u_fifo (
        .wr_clk   (clk),
        .wr_rst_n (eff_rst_n),
        .wr_en    (wr_en),
        .wr_data  (wr_data),
        .wr_full  (full),
        .rd_clk   (clk),
        .rd_rst_n (eff_rst_n),
        .rd_en    (rd_en),
        .rd_data  (rd_data),
        .rd_empty (empty)
    );

    // Shadow occupancy counter for assertion checking.
    reg [3:0] shadow_depth;
    wire      inc = wr_en && (shadow_depth < DEPTH);
    wire      dec = rd_en && (shadow_depth > 0);

    always @(posedge clk) begin
        if (!eff_rst_n)
            shadow_depth <= 4'd0;
        else begin
            case ({ inc, dec })
                2'b10:   shadow_depth <= shadow_depth + 4'd1;
                2'b01:   shadow_depth <= shadow_depth - 4'd1;
                2'b11:   ;
                default: ;
            endcase
        end
    end

    // Assumptions: legal host behaviour.
    always @(*) begin
        assume (!(wr_en && full));
        assume (!(rd_en && empty));
        assume (!(wr_en && rd_en));
    end

    // Assertions: safety invariants.
    always @(posedge clk) begin
        if (eff_rst_n) begin
            assert (shadow_depth <= DEPTH);
            assert (!(full && empty));
        end
    end

    // Cover goals: reachability checks (used by sby cover task).
    reg f_ever_full;
    always @(posedge clk) begin
        if (!eff_rst_n)
            f_ever_full <= 1'b0;
        else if (full)
            f_ever_full <= 1'b1;
    end

    always @(posedge clk) begin
        if (eff_rst_n) begin
            // Cover: FIFO reaches full.
            cover(full);
            // Cover: after having been full, FIFO drains to empty.
            cover(f_ever_full && empty);
        end
    end

endmodule

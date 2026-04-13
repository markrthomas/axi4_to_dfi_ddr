// fifo_safety_top.sv — Yosys-only bounded check (single-clock abstraction)
//
// Phased reset: hold both FIFO resets low for the first few clk edges so BMC
// cannot start from arbitrary async2sync register states. Then rst_n must stay
// high (constrained below for bounded depth).
//
// wr_clk == rd_clk == clk. Assumes host obeys !full / !empty.

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

    // Power-on: release FIFO reset only after enough cycles for a clean state.
    reg [2:0] ph;
    always @(posedge clk) begin
        if (ph != 3'd7)
            ph <= ph + 3'd1;
    end

    initial ph = 3'd0;

    wire eff_rst_n = (ph >= 3'd4) && rst_n;

    // Stay out of reset after warm-up so asserts apply to steady operation
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

    always @(*) begin
        assume (!(wr_en && full));
        assume (!(rd_en && empty));
    end

    always @(posedge clk) begin
        if (eff_rst_n) begin
            assert (shadow_depth <= DEPTH);
            assert (!(full && empty));
        end
    end

endmodule

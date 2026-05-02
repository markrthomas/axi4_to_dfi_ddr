// cdc_fifo_lib.v — CDC synchronizer + Gray async FIFO (used by axi4_bridge_frontend / bridge)
`timescale 1ns / 1ps
// Two-flop synchronizer (vector)
//-----------------------------------------------------------------------------
module cdc_sync #(
    parameter integer WIDTH = 1
) (
    input  wire              dst_clk,
    input  wire              dst_rst_n,
    input  wire [WIDTH-1:0]  d,
    output reg  [WIDTH-1:0]  q
);
    reg [WIDTH-1:0] s1;
    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            s1 <= {WIDTH{1'b0}};
            q  <= {WIDTH{1'b0}};
        end else begin
            s1 <= d;
            q  <= s1;
        end
    end
endmodule

//-----------------------------------------------------------------------------
// Gray-code async FIFO (Cliff Cummings style; power-of-2 DEPTH)
// Read side presents a registered word: !rd_empty means rd_data is stable until
// rd_en consumes it. The next word is prefetched on the read clock when present.
//-----------------------------------------------------------------------------
module async_fifo_gray #(
    parameter integer WIDTH  = 8,
    parameter integer DEPTH  = 8,
    parameter integer PTRW   = $clog2(DEPTH) + 1
) (
    input  wire              wr_clk,
    input  wire              wr_rst_n,
    input  wire              wr_en,
    input  wire [WIDTH-1:0]  wr_data,
    output wire              wr_full,

    input  wire              rd_clk,
    input  wire              rd_rst_n,
    input  wire              rd_en,
    output wire [WIDTH-1:0]  rd_data,
    output wire              rd_empty
);
    function [PTRW-1:0] bin2gray;
        input [PTRW-1:0] b;
        begin
            bin2gray = b ^ (b >> 1);
        end
    endfunction

    localparam integer AW = $clog2(DEPTH);

    initial begin
        if (DEPTH < 2) begin
            $display("ERROR: async_fifo_gray DEPTH=%0d must be >= 2", DEPTH);
            $finish(1);
        end
        if ((DEPTH & (DEPTH - 1)) != 0) begin
            $display("ERROR: async_fifo_gray DEPTH=%0d must be a power of two", DEPTH);
            $finish(1);
        end
        if (WIDTH < 1) begin
            $display("ERROR: async_fifo_gray WIDTH=%0d must be >= 1", WIDTH);
            $finish(1);
        end
    end

    reg [WIDTH-1:0] mem [0:DEPTH-1];

    reg [PTRW-1:0] wptr_bin, wptr_gray, rptr_bin, rptr_gray;
    wire [PTRW-1:0] wptr_gray_rd;
    wire [PTRW-1:0] rptr_gray_wr;

    wire [PTRW-1:0] wptr_gray_next = bin2gray(wptr_bin + 1'b1);
    wire [PTRW-1:0] rptr_bin_next  = rptr_bin + 1'b1;
    wire [PTRW-1:0] rptr_gray_next = bin2gray(rptr_bin_next);

    wire [PTRW-1:0] wptr_full_cmp =
        (PTRW > 2) ? {~rptr_gray_wr[PTRW-1:PTRW-2], rptr_gray_wr[PTRW-3:0]} :
                     {~rptr_gray_wr[PTRW-1:PTRW-2]};
    wire full_int = (wptr_gray_next == wptr_full_cmp);
    assign wr_full = full_int;

    reg [WIDTH-1:0] rd_data_q;
    reg             rd_valid_q;

    wire rd_have_cur  = (wptr_gray_rd != rptr_gray);
    wire rd_have_next = (wptr_gray_rd != rptr_gray_next);
    wire rd_pop       = rd_en && rd_valid_q;

    assign rd_empty = !rd_valid_q;
    assign rd_data  = rd_valid_q ? rd_data_q : {WIDTH{1'b0}};

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wptr_bin  <= {PTRW{1'b0}};
            wptr_gray <= {PTRW{1'b0}};
        end else if (wr_en && !full_int) begin
            mem[wptr_bin[AW-1:0]] <= wr_data;
            wptr_bin  <= wptr_bin + 1'b1;
            wptr_gray <= wptr_gray_next;
        end
    end

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rptr_bin  <= {PTRW{1'b0}};
            rptr_gray <= {PTRW{1'b0}};
            rd_data_q <= {WIDTH{1'b0}};
            rd_valid_q <= 1'b0;
        end else begin
            if (rd_pop) begin
                rptr_bin  <= rptr_bin_next;
                rptr_gray <= rptr_gray_next;
                if (rd_have_next) begin
                    rd_data_q  <= mem[rptr_bin_next[AW-1:0]];
                    rd_valid_q <= 1'b1;
                end else begin
                    rd_data_q  <= {WIDTH{1'b0}};
                    rd_valid_q <= 1'b0;
                end
            end else if (!rd_valid_q && rd_have_cur) begin
                rd_data_q  <= mem[rptr_bin[AW-1:0]];
                rd_valid_q <= 1'b1;
            end
        end
    end

    cdc_sync #(.WIDTH(PTRW)) u_sync_w2r (
        .dst_clk  (rd_clk),
        .dst_rst_n(rd_rst_n),
        .d        (wptr_gray),
        .q        (wptr_gray_rd)
    );

    cdc_sync #(.WIDTH(PTRW)) u_sync_r2w (
        .dst_clk  (wr_clk),
        .dst_rst_n(wr_rst_n),
        .d        (rptr_gray),
        .q        (rptr_gray_wr)
    );
endmodule

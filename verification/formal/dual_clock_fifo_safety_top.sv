// Bounded multi-clock data-integrity harness for async_fifo_gray.
//
// gclk is the formal scheduler clock.  wr_clk and rd_clk are independent
// symbolic clocks: only one may transition per scheduler step and each must
// have a rising edge at least once every five steps.  This deliberately models
// variable relative clock phase/rate without allowing simultaneous edges.
//
// Resets begin asserted, may release independently, and cannot reassert.
// Requests are held off until both domains have observed enough local clock
// edges after reset release for the pointer synchronizers to settle.
//
// The reader is an eager, legal host: it requests a word on every read-clock
// edge for which the registered output was valid.  Together with clock
// progress this makes delivery bounded.  The shadow queue checks every
// accepted transfer; an age bound catches a word that never becomes readable.

`timescale 1ns / 1ps

module dual_clock_fifo_safety_top (
    input wire       wr_clk,
    input wire       wr_rst_n,
    input wire       wr_en,
    input wire [7:0] wr_data,
    input wire       rd_clk,
    input wire       rd_rst_n,
    input wire       rd_en
);

    localparam integer WIDTH = 8;
    localparam integer DEPTH = 4;
    localparam integer MAX_DELIVERY_STEPS = 20;

    wire             wr_full;
    wire             rd_empty;
    wire [WIDTH-1:0] rd_data;

    async_fifo_gray #(
        .WIDTH (WIDTH),
        .DEPTH (DEPTH)
    ) u_fifo (
        .wr_clk   (wr_clk),
        .wr_rst_n (wr_rst_n),
        .wr_en    (wr_en),
        .wr_data  (wr_data),
        .wr_full  (wr_full),
        .rd_clk   (rd_clk),
        .rd_rst_n (rd_rst_n),
        .rd_en    (rd_en),
        .rd_data  (rd_data),
        .rd_empty (rd_empty)
    );

    (* gclk *) reg gclk;
    reg init;
    reg [2:0] boot;
    reg [2:0] wr_since_rise;
    reg [2:0] rd_since_rise;
    reg [1:0] wr_settle;
    reg [1:0] rd_settle;

    initial begin
        init          = 1'b1;
        boot          = 3'd0;
        wr_since_rise = 3'd0;
        rd_since_rise = 3'd0;
        wr_settle     = 2'd0;
        rd_settle     = 2'd0;
    end

    always @(posedge gclk) begin
        init <= 1'b0;
        if (boot != 3'd7)
            boot <= boot + 3'd1;

        if (init) begin
            assume (!wr_rst_n);
            assume (!rd_rst_n);
            assume (!wr_clk);
            assume (!rd_clk);
        end else begin
            // A scheduler step is either a write-clock event, a read-clock
            // event, or idle; it never collapses into a common clock edge.
            assume ($stable(wr_clk) || $stable(rd_clk));

            // Each independent clock must make bounded progress.
            assume (wr_since_rise <= 3'd4);
            assume (rd_since_rise <= 3'd4);

            // Reset may release at a different scheduler step in each
            // domain, but remains released and both are high by boot step 2.
            if (boot >= 3'd2) begin
                assume (wr_rst_n);
                assume (rd_rst_n);
            end
            if ($past(wr_rst_n))
                assume (wr_rst_n);
            if ($past(rd_rst_n))
                assume (rd_rst_n);
        end

        if ($rose(wr_clk))
            wr_since_rise <= 3'd0;
        else
            wr_since_rise <= wr_since_rise + 3'd1;

        if ($rose(rd_clk))
            rd_since_rise <= 3'd0;
        else
            rd_since_rise <= rd_since_rise + 3'd1;

        if (!wr_rst_n)
            wr_settle <= 2'd0;
        else if ($rose(wr_clk) && wr_settle != 2'd3)
            wr_settle <= wr_settle + 2'd1;

        if (!rd_rst_n)
            rd_settle <= 2'd0;
        else if ($rose(rd_clk) && rd_settle != 2'd3)
            rd_settle <= rd_settle + 2'd1;
    end

    wire formal_ready = (wr_settle >= 2'd2) && (rd_settle >= 2'd2);

    // The host does not operate while either reset domain is settling.  Once
    // ready, writes and reads obey the flag sampled at their local clock edge;
    // reads are deliberately eager so no accepted word can remain indefinitely.
    always @(*) begin
        if (!formal_ready) begin
            assume (!wr_en);
            assume (!rd_en);
        end
    end

    always @(posedge gclk) begin
        if (!init && formal_ready) begin
            if ($rose(wr_clk))
                assume (!($past(wr_en) && $past(wr_full)));
            if ($rose(rd_clk)) begin
                assume (!($past(rd_en) && $past(rd_empty)));
                assume ($past(rd_en) == !$past(rd_empty));
            end
        end
    end

    reg wr_fire;
    reg rd_fire;
    reg [2:0] shadow_depth;
    reg [1:0] shadow_wptr;
    reg [1:0] shadow_rptr;
    reg [WIDTH-1:0] shadow_mem0;
    reg [WIDTH-1:0] shadow_mem1;
    reg [WIDTH-1:0] shadow_mem2;
    reg [WIDTH-1:0] shadow_mem3;
    reg [5:0] oldest_age;

    initial begin
        shadow_depth = 3'd0;
        shadow_wptr  = 2'd0;
        shadow_rptr  = 2'd0;
        oldest_age   = 6'd0;
    end

    always @(posedge gclk) begin
        // The formal scheduler applies host inputs before a clock transition,
        // so $past() is the value sampled by the just-risen local clock.
        wr_fire = formal_ready && $rose(wr_clk) &&
                  $past(wr_en) && !$past(wr_full);
        rd_fire = formal_ready && $rose(rd_clk) &&
                  $past(rd_en) && !$past(rd_empty);

        if (!formal_ready) begin
            shadow_depth <= 3'd0;
            shadow_wptr  <= 2'd0;
            shadow_rptr  <= 2'd0;
            oldest_age   <= 6'd0;
        end else begin
            assert (shadow_depth <= DEPTH);
            assert (oldest_age < MAX_DELIVERY_STEPS);

            if (wr_fire) begin
                assert (shadow_depth < DEPTH);
                case (shadow_wptr)
                    2'd0: shadow_mem0 <= $past(wr_data);
                    2'd1: shadow_mem1 <= $past(wr_data);
                    2'd2: shadow_mem2 <= $past(wr_data);
                    default: shadow_mem3 <= $past(wr_data);
                endcase
                shadow_wptr <= shadow_wptr + 2'd1;
            end

            if (rd_fire) begin
                assert (shadow_depth != 0);
                // $past(rd_data) is the pre-consumption registered head
                // sampled at this read edge.
                case (shadow_rptr)
                    2'd0: assert ($past(rd_data) == shadow_mem0);
                    2'd1: assert ($past(rd_data) == shadow_mem1);
                    2'd2: assert ($past(rd_data) == shadow_mem2);
                    default: assert ($past(rd_data) == shadow_mem3);
                endcase
                shadow_rptr <= shadow_rptr + 2'd1;
            end

            // A stalled valid read keeps the registered head stable.
            if ($rose(rd_clk) && !$past(rd_empty) && !$past(rd_en))
                assert (rd_data == $past(rd_data));

            case ({wr_fire, rd_fire})
                2'b10: shadow_depth <= shadow_depth + 3'd1;
                2'b01: shadow_depth <= shadow_depth - 3'd1;
                default: ;
            endcase

            if (shadow_depth == 0 || rd_fire)
                oldest_age <= 6'd0;
            else
                oldest_age <= oldest_age + 6'd1;

        end
    end

endmodule

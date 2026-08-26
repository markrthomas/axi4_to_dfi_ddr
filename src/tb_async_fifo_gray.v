// Self-checking dual-clock test for async_fifo_gray.
`timescale 1ns / 1ps

module tb_async_fifo_gray;
    localparam integer WIDTH = 8;
    localparam integer DEPTH = 4;

    reg             wr_clk;
    reg             wr_rst_n;
    reg             wr_en;
    reg [WIDTH-1:0] wr_data;
    wire            wr_full;

    reg             rd_clk;
    reg             rd_rst_n;
    reg             rd_en;
    wire [WIDTH-1:0] rd_data;
    wire            rd_empty;

    integer failures;
    integer i;
    integer wr_i;
    integer rd_i;
    integer phase;

    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("build/fifo.vcd");
            $dumpvars(0, tb_async_fifo_gray);
        end
    end

    initial begin
        #20000;
        $fatal(1, "FAIL: tb_async_fifo_gray timed out in phase %0d", phase);
    end

    async_fifo_gray #(
        .WIDTH (WIDTH),
        .DEPTH (DEPTH)
    ) dut (
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

    always #5 wr_clk = ~wr_clk;
    always #7 rd_clk = ~rd_clk;

    task push;
        input [WIDTH-1:0] value;
        begin
            @(negedge wr_clk);
            while (wr_full)
                @(negedge wr_clk);
            wr_data = value;
            wr_en   = 1'b1;
            @(negedge wr_clk);
            wr_en   = 1'b0;
        end
    endtask

    task pop_and_check;
        input [WIDTH-1:0] expected;
        reg [WIDTH-1:0] held_data;
        begin
            @(negedge rd_clk);
            while (rd_empty)
                @(negedge rd_clk);

            held_data = rd_data;
            repeat (2) begin
                @(negedge rd_clk);
                if (rd_empty || (rd_data !== held_data)) begin
                    $display("FAIL: registered read data was not stable while stalled");
                    failures = failures + 1;
                end
            end

            if (held_data !== expected) begin
                $display("FAIL: expected 0x%0h, got 0x%0h", expected, held_data);
                failures = failures + 1;
            end

            rd_en = 1'b1;
            @(negedge rd_clk);
            rd_en = 1'b0;
        end
    endtask

    initial begin
        wr_clk   = 1'b0;
        rd_clk   = 1'b0;
        wr_rst_n = 1'b0;
        rd_rst_n = 1'b0;
        wr_en    = 1'b0;
        rd_en    = 1'b0;
        wr_data  = {WIDTH{1'b0}};
        failures = 0;
        phase    = 0;

        #31 wr_rst_n = 1'b1;
        #16 rd_rst_n = 1'b1;

        // Fill and drain every entry to verify full/empty flow control.
        phase = 1;
        for (i = 0; i < DEPTH; i = i + 1)
            push(i[WIDTH-1:0]);
        repeat (4) @(negedge wr_clk);
        if (!wr_full) begin
            $display("FAIL: FIFO did not assert full after %0d writes", DEPTH);
            failures = failures + 1;
        end

        for (i = 0; i < DEPTH; i = i + 1)
            pop_and_check(i[WIDTH-1:0]);
        repeat (4) @(negedge rd_clk);
        if (!rd_empty) begin
            $display("FAIL: FIFO did not assert empty after drain");
            failures = failures + 1;
        end

        // Use independent clocks while producer and consumer run concurrently.
        phase = 2;
        fork
            begin
                for (wr_i = 0; wr_i < 8; wr_i = wr_i + 1)
                    push(8'h80 + wr_i[WIDTH-1:0]);
            end
            begin
                repeat (3) @(negedge rd_clk);
                for (rd_i = 0; rd_i < 8; rd_i = rd_i + 1)
                    pop_and_check(8'h80 + rd_i[WIDTH-1:0]);
            end
        join

        repeat (4) @(negedge rd_clk);
        if (!rd_empty) begin
            $display("FAIL: FIFO was not empty after concurrent traffic");
            failures = failures + 1;
        end

        if (failures != 0) begin
            $display("FAIL: tb_async_fifo_gray (%0d failures)", failures);
            $fatal(1);
        end

        $display("PASS: tb_async_fifo_gray");
        $finish;
    end
endmodule

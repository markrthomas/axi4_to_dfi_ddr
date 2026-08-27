// Stress sequence — mirrors iverilog Test 14 LFSR stress.
// Generates random write and read phases (writes first, reads after) so that
// the DUT's write-priority arbitration (wreq must drain before reads start)
// is exercised. Uses a 32-bit Galois LFSR for reproducible address generation.
class stress_seq #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 64,
    parameter int ID_W   = 4
) extends axi4_dfi_base_seq #(ADDR_W, DATA_W, ID_W);

    `uvm_object_param_utils(stress_seq #(ADDR_W, DATA_W, ID_W))

    // Number of write and read transactions per stress run.
    int unsigned n_writes = 28;
    int unsigned n_reads  = 8;

    // LFSR seed (configurable for reproducibility).
    rand int unsigned lfsr_seed;
    constraint seed_nonzero_c { lfsr_seed != 0; }

    function new(string name = "stress_seq");
        super.new(name);
    endfunction

    task body();
        int unsigned lfsr;
        logic [ADDR_W-1:0] addr;

        if (!this.randomize()) `uvm_fatal("RAND", "stress_seq randomize failed")
        lfsr = lfsr_seed;

        // --- Write phase ---
        for (int i = 0; i < int'(n_writes); i++) begin
            logic [2:0]  bank;
            logic [13:0] row;
            logic [9:0]  col;
            logic [DATA_W-1:0] data;

            lfsr_step(lfsr);
            bank = lfsr[26:24] & 3'h7;
            lfsr_step(lfsr);
            row  = lfsr[23:10] & 14'h3FFF;
            lfsr_step(lfsr);
            col  = {lfsr[9:3], 3'd0};  // 8-byte aligned
            data = {lfsr, lfsr};

            addr = mc_addr(bank, row, col);
            send_write_single(addr, logic'(i[ID_W-1:0]), data);
        end

        // --- Read phase (all writes must complete first) ---
        // n_reads single reads followed by n_reads/2 burst reads
        for (int i = 0; i < int'(n_reads); i++) begin
            logic [2:0]  bank;
            logic [13:0] row;
            logic [9:0]  col;

            lfsr_step(lfsr);
            bank = lfsr[26:24] & 3'h7;
            row  = 14'd100 + logic'(i * 13);
            col  = logic'((i * 31) % 112 * 8) & 10'h380;

            addr = mc_addr(bank, row, col);
            send_read_single(addr, logic'(i[ID_W-1:0]));
        end

        // Burst reads in a separate pass so single reads drain first
        // (RRESP FIFO depth = 8 would fill otherwise).
        for (int i = 0; i < int'(n_reads); i++) begin
            logic [2:0]  bank;
            logic [13:0] row;
            logic [9:0]  col;
            logic [7:0]  arlen;

            lfsr_step(lfsr);
            bank  = lfsr[26:24] & 3'h7;
            row   = 14'd160 + logic'((i * 11) % 48);
            arlen = lfsr[21:20] & 8'h03;   // 0..3
            col   = logic'(((i * 31) % 112) * 8) & 10'h380;
            // Clamp so all beats stay in same row (max col offset = arlen * 8 bytes)
            if ((int'(col) + int'(arlen) * 8) >= 1024)
                col = 10'h200;

            addr = mc_addr(bank, row, col);
            send_read_burst(addr, ID_W'(n_reads + i), arlen);
        end
    endtask

    // One step of 32-bit Galois LFSR (tap polynomial x^32+x^22+x^2+x+1).
    function automatic void lfsr_step(inout int unsigned s);
        s = (s >> 1) ^ (32'hB400_0000 & {32{s[0]}});
    endfunction

endclass

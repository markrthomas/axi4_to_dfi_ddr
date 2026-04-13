# AXI4 to DFI Bridge - Design Specification

**Repository:** axi4_to_dfi_ddr  
**Source file:** `doc/DESIGN_SPEC.md`

# 1. Purpose and scope

This document specifies the **axi4_to_dfi_bridge** RTL: an **AMBA AXI4** slave to **JEDEC DFI**-style PHY/controller interface, with **two asynchronous clock domains** and clock-domain crossing (CDC) infrastructure.

**In scope**

- AXI4-compliant handshaking on the slave port for supported transactions.
- Crossing of commands and responses between `axi_aclk` and `dfi_clk` using gray-code asynchronous FIFOs and two-flop synchronizers.
- A minimal, illustrative DFI command and data-plane presentation suitable for simulation and as a hook for a full memory controller.

**Out of scope (intentional)**

- Full DRAM protocol (mode registers, tRAS/tWR/tRFC-class checks, timing closure, production bank interleaving).
- DFI multi-phase timing (P0-P3) as required by many PHYs; the RTL uses a simplified single-phase view of command and data.
- Production PHY training, update, and low-power sequences beyond tie-offs or stubs on optional DFI sideband signals.

# 2. Normative references (informative)

| Document | Relevance |
|----------|-----------|
| ARM AMBA AXI Protocol (e.g. IHI0022) | AXI4 signal names, handshakes, burst/response encoding |
| JEDEC DFI (e.g. 4.0; 5.x naming overlap on core paths) | `dfi_*` command, write data, read data, init/update concepts |

This implementation is **not** a certified protocol checker; it follows common industry usage for integration and simulation.

# 3. Architecture

## 3.1 Block overview

The top module **`axi4_to_dfi_bridge`** instantiates:

| Block | Role |
|-------|------|
| **`cdc_sync`** | Vector two-flop synchronizer (destination clock domain). |
| **`async_fifo_gray`** | Power-of-2-depth gray-pointer FIFO; separate write and read clocks. |
| **AXI front-end (logic in top)** | Decode AW/W/AR, push to CDC FIFOs, handle errors, drive B/R. |
| **DFI sequencer (logic in top)** | Pop request FIFOs on `dfi_clk`, drive `dfi_*`, model fixed latency, push B/R payload FIFOs. |

```
axi_aclk domain                         dfi_clk domain
----------------                        ---------------
  AW/W --> wreq FIFO (wr) ======> wreq FIFO (rd) --> DFI sequencer
  AR --> rreq FIFO (wr) ======> rreq FIFO (rd) -->        |
                                                          |
  B <-- bresp FIFO (rd) <====== bresp FIFO (wr) <--------+
  R <-- rresp FIFO (rd) <====== rresp FIFO (wr) <--------+
```

## 3.2 Clock and reset

| Domain | Clock | Reset (active low) | Notes |
|--------|-------|--------------------|-------|
| AXI | `axi_aclk` | `axi_aresetn` | All `s_axi_*` timing except where CDC applies to sourced inputs. |
| DFI | `dfi_clk` | `dfi_rst_n` | All `dfi_*` outputs and DFI-side FIFO ports. |

`dfi_init_complete` is sampled into the DFI domain via **`cdc_sync`** before gating request FIFO pops, so the PHY can deassert completion asynchronously to `dfi_clk`.

## 3.3 Asynchronous FIFO (`async_fifo_gray`)

- **Depth**: parameter `DEPTH` (power of two); bridge uses `CDC_FIFO_DEPTH`.
- **Pointers**: binary write/read pointers converted to Gray for comparison; Gray write pointer synchronized to read clock and vice versa for full/empty.
- **Full / empty**: classic Gray inequality (MSB pair adjusted for depth width).
- **Read data**: **first-word fall-through**: `rd_data` reflects `mem[rptr]` when not empty so AXI-style `valid` can align with visible data.
- **Submodules**: two **`cdc_sync`** instances per FIFO for pointer cross.

## 3.4 Request snapshot registers

On the cycle a request FIFO **`rd_en`** is asserted, the read pointer advances after the posedge; the combinational FWFT output can change immediately. The bridge latches **`wreq_snapshot`** / **`rreq_snapshot`** when **`wreq_rd_en`** / **`rreq_rd_en`** is true and uses those registers on the following cycle (**`*_rd_en_r`**) to unpack ID, address, and write data. This avoids consuming an inconsistent beat.

## 3.5 Memory controller scheduler (dfi_clk)

A **single-transaction** SDRAM-style **open-page** FSM drives `dfi_*` (one AXI-equivalent request at a time).

**Address decode** (LSBs of the AXI address): `col` = `[MC_COL_BITS-1:0]`, `row` = `[MC_COL_BITS +: MC_ROW_BITS]`, `bank` = `[MC_COL_BITS+MC_ROW_BITS +: DFI_BANK_WIDTH]`. Require the sum of those field widths to be at most `C_AXI_ADDR_WIDTH`.

**Per bank:** `row_open_mask` and `open_row_mem[bank]` track the activated row. Sequences:

1. Bank idle: **ACT** (row on `dfi_address`), wait **MC_T_RCD**, then **READ** or **WRITE** CAS (column on `dfi_address`).
2. Same open row: **CAS only**.
3. Different open row: **PRE**, wait **MC_T_RP**, then **ACT**, wait **MC_T_RCD**, then **CAS**.

**`MC_T_RAS` / `MC_T_WR` (optional, default 0):** per-bank **`dfi_clk`** counters (see **`bank_ras_cnt`**, **`bank_wr_cnt`** in RTL). **`MC_T_RAS`**: minimum cycles from **ACT** command until **PRE** is allowed for that bank (counter also decrements during **`ST_WAIT_RCD`** while the row is not yet marked open). **`MC_T_WR`**: minimum cycles from each **WRITE** CAS until **PRE** is allowed for that bank (reloaded on every write to the bank). If a row miss or refresh walk would issue **PRE** before both counters for that bank are zero, the FSM enters **`ST_WAIT_PRE`** until **`bank_pre_ready`** holds, then continues to **`ST_PRE_CMD`** or **`ST_RF_PRE`**.

**Timing (dfi_clk cycles):** `MC_T_RP`, `MC_T_RCD`, `MC_CL` (read CAS to read-data phase), `DFI_WRITE_ACK_CYCLES` (after WRITE CAS before **B** is pushed into `u_fifo_bresp`), `MC_RD_DV_MAX` (valid wait after `MC_CL`). A value of **0** for `MC_T_RP`, `MC_T_RCD`, `MC_CL`, `MC_T_RAS`, or `MC_T_WR` skips the corresponding wait (no counter underflow for **`MC_T_RAS`/`MC_T_WR`** means **PRE** is not delayed by that constraint). **`DFI_WRITE_ACK_CYCLES = 0`** means **no** extra turnaround cycles after WRITE CAS; the FSM still spends **one** `dfi_clk` in **`ST_WAIT_B`** with **`mc_ctr == 1`** so **`bresp_wr_en`** can fire (combinational **B** push requires that state).

**Refresh (optional):** parameter **`MC_REFRESH_INTERVAL`** (default **0** = disabled). When **> 0**, a counter decrements only in **`ST_IDLE`** gaps when **`dfi_mc_ready`** is true and no request snapshot is pending (**`!wreq_rd_en_r && !rreq_rd_en_r`**). At **0**, the FSM walks banks **0 … 2^`DFI_BANK_WIDTH`-1**; for each bank with an open row (**`row_open_mask`**), it issues the same **PRE** encoding as normal traffic, waits **`MC_T_RP`**, then continues. Request FIFO pops are blocked while the counter is **0** or while **`rf_active`**. After the walk, **`refresh_ctr`** reloads to **`MC_REFRESH_INTERVAL`**.

**Not in this block:** JEDEC-accurate **REF** command (auto-refresh) timing, full **tRFC**/**tRC** bookkeeping, **DFI P0–P3** phasing.

# 4. Data paths

## 4.1 Write path (supported transfers)

1. **AXI**: When AW and W present a **legal** write (`aw_ok`, full bus `AWSIZE`, INCR `AWBURST`), the bridge may push one packed word per **W beat** into **`u_fifo_wreq`** on `axi_aclk`. **Reads** remain single-beat (`ARLEN == 0`) as in section 4.2.
   - **Single-beat**: `AWLEN == 0` and `WLAST` must be high on that beat.
   - **INCR burst (writes only)**: parameter **`C_MAX_WRITE_AWLEN`** (default **3**) allows `AWLEN` in **0...C_MAX_WRITE_AWLEN** (up to **four** beats for the default). **`WLAST`** must be low on all beats except the last; the last beat's index must equal **`AWLEN`**. After each non-final beat, the held **`AWADDR`** is advanced by **`C_AXI_DATA_WIDTH/8`** for the next FIFO entry.
2. **Pack format** (`WREQ_W` bits): **MSB** = **`WLAST`** for that beat; then `AWID`, `AWADDR`, `WDATA`, `WSTRB`.
3. **DFI**: The memory-controller FSM (section 3.5) may issue **PRE/ACT** before each **WRITE** CAS; `dfi_wrdata` / `dfi_wrdata_mask` / `dfi_wrdata_en` align with each WRITE CAS cycle.
4. **Response**: After each WRITE CAS, the FSM enters **`ST_WAIT_B`** for **`max(1, DFI_WRITE_ACK_CYCLES)`** `dfi_clk` cycles (so **`DFI_WRITE_ACK_CYCLES = 0`** is one cycle in **`ST_WAIT_B`**). When **`mc_ctr`** reaches **1** and that beat's stored **`WLAST`** is **1**, the bridge pushes **`AWID`** into **`u_fifo_bresp`** (one **B** for the whole burst). The AXI domain pops this FIFO to assert **`BVALID`** with **`BRESP = OKAY`**.

AW/W **holding registers** allow address and data to arrive in separate cycles before a matching pair is pushed; beat counting for **`WLAST`** checks treats a same-cycle **`AWVALID`/`AWREADY`** handshake as starting the burst at beat **0** even if the running beat counter register is non-zero from an earlier transaction.

## 4.2 Read path (supported transfers)

1. **AXI**: Legal AR (`ar_ok`) pushes `{ARID, ARADDR}` into **`u_fifo_rreq`**.
2. **DFI**: The FSM may issue **PRE/ACT** before a **READ** CAS; **`dfi_rddata_en`** is asserted for one cycle on the READ CAS.
3. **Data**: After **`MC_CL`**, the FSM waits in a read-data window for **`dfi_rddata_valid`** (timeout **`MC_RD_DV_MAX`**); then read data (or a timeout indication) is pushed with **`ARID`** to **`u_fifo_rresp`** via a one-cycle **`ST_PULSE_R`**.
4. **AXI**: Pop yields **`RVALID`**, **`RLAST = 1`**. **`RRESP = OKAY`** when the PHY returned read data in time; if **`dfi_rddata_valid`** never arrived before the timeout, **`RRESP = SLVERR`** and **`RDATA = 0`** (same encoding as an illegal **AR** decode error).

## 4.3 Arbitration

While **`dfi_mc_ready`** is true, the DFI side serves **writes before reads** when both request FIFOs are active: read pop requires **`wreq_empty`**.

# 5. AXI error handling

Unsupported or illegal shapes are rejected with **SLVERR** (`2'b10`) where implemented.

- **Reads**: If **`ar_ok`** is false and an AR handshake completes, **`rresp_err_valid`** is raised; **`RVALID`** carries **`RRESP = SLVERR`**, **`RDATA = 0`**, and the captured **`ARID`**. If the memory-controller read window expires without **`dfi_rddata_valid`**, the read response uses **`RRESP = SLVERR`**, **`RDATA = 0`**, and the **`ARID`** for that transaction (via the **`rresp`** FIFO).
- **Writes**: If AW and W form an illegal pair (e.g. wrong burst/length/last), the bridge can enter a **drain** path: absorb remaining W beats if required, then assert **`BVALID`** with **`BRESP = SLVERR`** and the relevant ID.

Exact decode conditions are defined in **`src/axi4_to_dfi_bridge.v`** (combinational `aw_ok` / `ar_ok`, `write_pair_error`, and the AXI-domain sequential FSM).

# 6. DFI presentation

## 6.1 Driven outputs (conceptual)

- **Command**: `dfi_address`, `dfi_bank` (low address bits by default), `dfi_ras_n`, `dfi_cas_n`, `dfi_we_n`, `dfi_cs_n`, `dfi_cke`, `dfi_odt`, `dfi_act_n`: idle to NOP-like values except during command pulses. **Row activate (ACT)** asserts `dfi_act_n` low for that cycle together with RAS/CAS/WE; PRE and READ/WRITE CAS keep `dfi_act_n` high.
- **Write data**: `dfi_wrdata`, `dfi_wrdata_mask` (derived from `WSTRB` with PHY-specific interpretation noted in RTL comments), `dfi_wrdata_en`.
- **Read data**: `dfi_rddata_en` during read command; expects **`dfi_rddata`** / **`dfi_rddata_valid`** from the PHY or model.

## 6.2 Stubbed / tied sidebands

`dfi_ctrlupd_req`, `dfi_phyupd_req`, `dfi_lp_ctrl_req` are driven low. **`dfi_init_start`**: parameter **`DFI_INIT_START_CYCLES`** (default **0**) sets how many `dfi_clk` cycles the controller pulses `dfi_init_start` high after `dfi_rst_n` deasserts; **0** means the output is tied low (legacy behavior). Integrators must still connect **`dfi_init_complete`** from the PHY when ready.

# 7. Parameters (top-level)

| Parameter | Typical role |
|-----------|----------------|
| `C_AXI_*` | AXI address/data/ID/user widths. |
| `DFI_*` | DFI address, bank, data, mask, CS, ODT, CKE widths. |
| `CDC_FIFO_DEPTH` | Depth of all four gray FIFOs in the bridge. |
| `DFI_WRITE_ACK_CYCLES` | DFI-clock cycles after WRITE CAS to B push. |
| `DFI_READ_DATA_CYCLES` | Reserved / legacy; read path uses `MC_CL` and `MC_RD_DV_MAX`. |
| `MC_COL_BITS`, `MC_ROW_BITS` | Address field sizes for bank/row/col decode. |
| `MC_T_RP`, `MC_T_RCD` | PRE and ACT timing. |
| `MC_T_RAS`, `MC_T_WR` | Min **dfi_clk** cycles from **ACT** (resp. **WRITE** CAS) to **PRE** for the same bank (**0** = no extra **`ST_WAIT_PRE`** delay for that constraint). |
| `MC_CL` | CAS-to-read-data phase length (PHY should align). |
| `MC_RD_DV_MAX` | Max cycles to wait for `dfi_rddata_valid` after `MC_CL`. |
| `MC_REFRESH_INTERVAL` | **dfi_clk** cycles between refresh walks (**0** = off). Countdown runs only in fully idle MC gaps; at **0** the design **PRE**-closes any open bank in index order, then reloads the counter. |
| `DFI_INIT_START_CYCLES` | MC init: pulse `dfi_init_start` high for this many `dfi_clk` cycles after reset release; **0** ties off. |
| `C_MAX_WRITE_AWLEN` | Legal **INCR** write burst length: **`AWLEN`** must be no greater than this value (default **3** = four beats). **0** restricts writes to single-beat only. |

## 7.1 Elaboration checks (RTL)

At simulation/elaboration time, **`axi4_to_dfi_bridge`** and each **`async_fifo_gray`** instance validate parameters and **`$finish`** on violation:

- **`C_AXI_DATA_WIDTH`** must equal **`DFI_DATA_WIDTH`**, and **`DFI_MASK_WIDTH`** must equal **`C_AXI_DATA_WIDTH/8`** (there is no width adapter in the datapath).
- **`MC_COL_BITS + MC_ROW_BITS + DFI_BANK_WIDTH`** must not exceed **`C_AXI_ADDR_WIDTH`**; **`MC_COL_BITS`** and **`MC_ROW_BITS`** must be at least **1**; **`DFI_ADDR_WIDTH`** must cover **`MC_ROW_BITS`** and **`MC_COL_BITS`** on the command bus.
- **`CDC_FIFO_DEPTH`** must be a power of two **>= 2** (same rule as **`async_fifo_gray` `DEPTH`**).
- **`DFI_BANK_WIDTH`** must not exceed **24** (implementation limit on bank count).
- **`C_AXI_ID_WIDTH`** must be **>= 1**; **`C_MAX_WRITE_AWLEN`** in **0..255**; timing integers **`MC_T_RP`**, **`MC_T_RCD`**, **`MC_T_RAS`**, **`MC_T_WR`**, **`MC_CL`**, **`MC_RD_DV_MAX`**, **`DFI_WRITE_ACK_CYCLES`**, **`MC_REFRESH_INTERVAL`** must be **>= 0**.

# 8. Verification

Simulation uses **Icarus Verilog** (`iverilog -g2001`). The testbench **`src/tb_axi4_to_dfi_bridge.v`** provides:

- Independent **`axi_aclk`** and **`dfi_clk`** generators.
- A minimal PHY read-return model (**`TB_PHY_MC_CL`** should match DUT **`MC_CL`**) and scoreboard checks.
- Optional **`+vcd`** for **gtkwave**.
- Init gating (**`dfi_init_complete`**), **SLVERR** on illegal AW/W and illegal AR (wrong burst, wrong **`AWSIZE`/`ARSIZE`**, **`ARLEN` != 0** for reads), and **SLVERR** on read-data timeout (**`tb_phy_suppress_rddv`** withholds **`dfi_rddata_valid`**).
- **B** and **R** channel backpressure (**`BVALID`/`RVALID`** stable while **`BREADY`/`RREADY`** low for several cycles).
- **CDC FIFO depth (8):** eight reads issued with **`RREADY`** low until the MC has finished, then eight **R** beats drained in order; eight single-beat writes with **`BREADY`** low, then eight **B** beats drained in order. A **`tb_flush_axi_rsp`** task clears stray **R/B** beats before these blocks.
- Two outstanding legal reads with different **`ARID`**; responses are checked in **MC / `rreq` FIFO** issue order.
- SDRAM-style MC checks (**PRE/ACT/READ CAS/WRITE CAS** counts) for open-page hit, row miss, and cold bank.
- **Stress (Test 13):** xorshift32 **LFSR** drives gaps and bank/row/column choices. **Writes** (each followed by **B**) run first, then **reads** are issued only while the **`wreq`** FIFO is empty so **MC** order matches **`rreq`** issue order (the scheduler does not pop **`rreq`** until **`wreq`** is empty). **AR** spacing and **R** drains mirror the FIFO-fill test (**Icarus** + FWFT).

**`tb_param_smoke_refresh`** enables **`MC_REFRESH_INTERVAL` > 0** on the DUT: a single cold write opens one bank, then after idle gaps the refresh walk issues exactly one **PRE** (monitored on **`dfi_clk`**); a second interval with all banks closed must not add further **PRE** pulses.

**`make formal-fifo`** (optional): **Yosys** bounded **`sat -prove-asserts`** on **`formal/fifo_safety_top.sv`**, a single-clock instance of **`async_fifo_gray`** with phased reset and host **`assume`** on **`full`**/**`empty`** (see **`formal/README.md`**). This is **not** a substitute for CDC signoff on unrelated clock ratios.

**`tb_param_smoke_tras`** instantiates the DUT with **`MC_T_RAS`** and **`MC_T_WR`** both **> 0** and runs two same-bank row-miss writes (see **`make -C test run-smoke-tras`**).

Between some **AR** issues and between back-to-back **R** (or **B**) drains, the testbench inserts a few **`axi_aclk`** waits so **Icarus** simulation stays consistent with the gray **async FIFO** first-word-fall-through read path across **CDC** (tight back-to-back handshakes can otherwise show a wrong ID or a repeated beat in this environment).

**CI:** **`make -C test ci`** runs the main testbench, **`tb_param_smoke`**, **`tb_param_smoke_zcycles`** ( **`MC_T_RP`/`MC_T_RCD`/`MC_CL`/`DFI_WRITE_ACK_CYCLES` all **0** ), **`tb_param_smoke_refresh`** (**`MC_REFRESH_INTERVAL` > 0**), **`tb_param_smoke_tras`** (**`MC_T_RAS`/`MC_T_WR`**), **elaboration-fail** checks (illegal parameters must print **`ERROR:`** and **`$finish`**), **Verilator** `--lint-only` on **`axi4_to_dfi_bridge.v`**, **`syn-check`** (**Yosys** on **`syn/yosys.ys`**), and **`formal-fifo`** (**Yosys** bounded BMC on **`formal/fifo_safety_top.sv`**); the Yosys targets are skipped if **`yosys`** is not installed (see **`.github/workflows/ci.yml`**).

**Further hardening:** For stronger CDC ordering evidence than **Icarus** alone, re-verify **`async_fifo_gray`** with a second simulator, bounded formal, or a **registered read data path** designed together with **`rd_empty`** and the bridge’s **`wreq_snapshot` / `rreq_snapshot`** timing (a naive registered mux alone can deadlock or mis-`empty` without that co-design). See **README** roadmap for the ordered backlog.

Build and run: **`make -C test run`**; full automation: **`make -C test ci`** (see repository **README.md**).

# 9. Revision history

| Revision | Summary |
|----------|---------|
| 0.1 | Initial design specification from RTL structure. |
| 0.2 | Document SDRAM open-page scheduler and MC_* parameters. |
| 0.3 | DFI fidelity slice: `dfi_act_n` on ACT; `DFI_INIT_START_CYCLES` for optional `dfi_init_start` pulse. |
| 0.4 | INCR write bursts up to `C_MAX_WRITE_AWLEN` (default four beats): one `wreq` FIFO entry per W beat (MSB = `WLAST`); one **B** after the last beat. |
| 0.5 | Read data timeout reports **SLVERR**; `open_row_mem` reset covers all banks; PDF-friendly ASCII in this source. |
| 0.6 | Verification section: extended testbench (FIFO fill under **RREADY**/**BREADY**, illegal **`ARLEN`**, dual **ARID** order, MC counters); note on **Icarus** + CDC FIFO handshake spacing. |
| 0.7 | Elaboration-time parameter checks (data/mask widths, address map, CDC FIFO depth); explicit **0-cycle** handling for `MC_T_RP`, `MC_T_RCD`, `DFI_WRITE_ACK_CYCLES`, and `MC_CL`. |
| 0.8 | LFSR stress phase (writes then reads); **`tb_param_smoke`**; **`make ci`** (**iverilog** + **verilator** lint); GitHub Actions workflow. |
| 0.9 | **`tb_param_smoke_zcycles`**; **`tb_elab_fail`** + Makefile **`elab-fail-*`**; **`DFI_WRITE_ACK_CYCLES=0`** uses one **`ST_WAIT_B`** cycle so **B** is pushed. |
| 0.10 | README roadmap update (FIFO + formal + refresh ordering); **`make audit`** (**`ci`** + design PDF). |
| 0.11 | Optional **`MC_REFRESH_INTERVAL`** refresh walk (all-bank **PRE** when due); **`syn-check`** in **`make ci`**; **`formal/README.md`** template; **`syn/constraints.sdc`** SDC hints; **`tb_param_smoke_refresh`**. |
| 0.12 | **Yosys-only** bounded formal on **`async_fifo_gray`** via **`formal/fifo_safety_top.sv`** and **`make formal-fifo`**. |
| 0.13 | **`MC_T_RAS`** / **`MC_T_WR`** per-bank **PRE** gating and **`ST_WAIT_PRE`**; **`tb_param_smoke_tras`**. |

# Document control

**Source**: `doc/DESIGN_SPEC.md`: build PDF via `make -C doc pdf` (requires **pandoc** and a LaTeX engine such as **pdflatex**), or HTML via `make -C doc html`.

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

- Full DRAM protocol (activate, precharge, refresh, mode registers, timing closure, bank state machines).
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

**Timing (dfi_clk cycles):** `MC_T_RP`, `MC_T_RCD`, `MC_CL` (read CAS to read-data phase), `DFI_WRITE_ACK_CYCLES` (after WRITE CAS to B push), `MC_RD_DV_MAX` (valid wait after `MC_CL`).

**Not in this block:** refresh, tRAS/tWR checks, DFI P0-P3 phasing.

# 4. Data paths

## 4.1 Write path (supported transfers)

1. **AXI**: When AW and W present a **legal** write (`aw_ok`, full bus `AWSIZE`, INCR `AWBURST`), the bridge may push one packed word per **W beat** into **`u_fifo_wreq`** on `axi_aclk`. **Reads** remain single-beat (`ARLEN == 0`) as in section 4.2.
   - **Single-beat**: `AWLEN == 0` and `WLAST` must be high on that beat.
   - **INCR burst (writes only)**: parameter **`C_MAX_WRITE_AWLEN`** (default **3**) allows `AWLEN` in **0...C_MAX_WRITE_AWLEN** (up to **four** beats for the default). **`WLAST`** must be low on all beats except the last; the last beat's index must equal **`AWLEN`**. After each non-final beat, the held **`AWADDR`** is advanced by **`C_AXI_DATA_WIDTH/8`** for the next FIFO entry.
2. **Pack format** (`WREQ_W` bits): **MSB** = **`WLAST`** for that beat; then `AWID`, `AWADDR`, `WDATA`, `WSTRB`.
3. **DFI**: The memory-controller FSM (section 3.5) may issue **PRE/ACT** before each **WRITE** CAS; `dfi_wrdata` / `dfi_wrdata_mask` / `dfi_wrdata_en` align with each WRITE CAS cycle.
4. **Response**: After each WRITE CAS, the FSM waits **`DFI_WRITE_ACK_CYCLES`** on `dfi_clk`. Only when that beat's stored **`WLAST`** is **1** does the bridge push **`AWID`** into **`u_fifo_bresp`** (one **B** for the whole burst). The AXI domain pops this FIFO to assert **`BVALID`** with **`BRESP = OKAY`**.

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
| `MC_CL` | CAS-to-read-data phase length (PHY should align). |
| `MC_RD_DV_MAX` | Max cycles to wait for `dfi_rddata_valid` after `MC_CL`. |
| `DFI_INIT_START_CYCLES` | MC init: pulse `dfi_init_start` high for this many `dfi_clk` cycles after reset release; **0** ties off. |
| `C_MAX_WRITE_AWLEN` | Legal **INCR** write burst length: **`AWLEN`** must be no greater than this value (default **3** = four beats). **0** restricts writes to single-beat only. |

# 8. Verification

Simulation uses **Icarus Verilog** (`iverilog -g2001`). The testbench **`src/tb_axi4_to_dfi_bridge.v`** provides:

- Independent **`axi_aclk`** and **`dfi_clk`** generators.
- A minimal PHY read-return model (**`TB_PHY_MC_CL`** should match DUT **`MC_CL`**) and scoreboard checks.
- Optional **`+vcd`** for **gtkwave**.

Build and run: **`make -C test run`** (see repository **README.md**).

# 9. Revision history

| Revision | Summary |
|----------|---------|
| 0.1 | Initial design specification from RTL structure. |
| 0.2 | Document SDRAM open-page scheduler and MC_* parameters. |
| 0.3 | DFI fidelity slice: `dfi_act_n` on ACT; `DFI_INIT_START_CYCLES` for optional `dfi_init_start` pulse. |
| 0.4 | INCR write bursts up to `C_MAX_WRITE_AWLEN` (default four beats): one `wreq` FIFO entry per W beat (MSB = `WLAST`); one **B** after the last beat. |
| 0.5 | Read data timeout reports **SLVERR**; `open_row_mem` reset covers all banks; PDF-friendly ASCII in this source. |

# Document control

**Source**: `doc/DESIGN_SPEC.md`: build PDF via `make -C doc pdf` (requires **pandoc** and a LaTeX engine such as **pdflatex**), or HTML via `make -C doc html`.

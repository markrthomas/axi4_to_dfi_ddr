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

# 4. Data paths

## 4.1 Write path (supported transfers)

1. **AXI**: When AW and W present a **legal** single-beat write (`aw_ok`, `WLAST` aligned with `AWLEN == 0`, full bus `AWSIZE`, INCR `AWBURST`), the bridge may push a packed word into **`u_fifo_wreq`** on `axi_aclk`.
2. **Pack format** (`WREQ_W` bits): reserved bit, `AWID`, `AWADDR`, `WDATA`, `WSTRB`.
3. **DFI**: On `dfi_clk`, the sequencer pops the FIFO, drives a simplified DDR-style write command (e.g. CAS/WE pattern) and `dfi_wrdata` / `dfi_wrdata_mask` / `dfi_wrdata_en` for one cycle (illustrative).
4. **Response**: After **`DFI_WRITE_ACK_CYCLES`** counts down on `dfi_clk`, the bridge pushes **`AWID`** into **`u_fifo_bresp`**. The AXI domain pops this FIFO to assert **`BVALID`** with **`BRESP = OKAY`**.

AW/W **holding registers** allow address and data to arrive in separate cycles before a matching pair is pushed.

## 4.2 Read path (supported transfers)

1. **AXI**: Legal AR (`ar_ok`) pushes `{ARID, ARADDR}` into **`u_fifo_rreq`**.
2. **DFI**: Pop issues a simplified read command and asserts **`dfi_rddata_en`** for one cycle.
3. **Data**: **`r_capture`** is updated when **`dfi_rddata_valid`** is seen during the read countdown; after **`DFI_READ_DATA_CYCLES`**, `{ARID, r_capture}` is pushed to **`u_fifo_rresp`**.
4. **AXI**: Pop yields **`RVALID`**, **`RLAST = 1`**, **`RRESP = OKAY`** for this single-beat design.

## 4.3 Arbitration

While **`dfi_mc_ready`** is true, the DFI side serves **writes before reads** when both request FIFOs are active: read pop requires **`wreq_empty`**.

# 5. AXI error handling

Unsupported or illegal shapes are rejected with **SLVERR** (`2'b10`) where implemented.

- **Reads**: If **`ar_ok`** is false and an AR handshake completes, **`rresp_err_valid`** is raised; **`RVALID`** carries **`RRESP = SLVERR`**, **`RDATA = 0`**, and the captured **`ARID`**.
- **Writes**: If AW and W form an illegal pair (e.g. wrong burst/length/last), the bridge can enter a **drain** path: absorb remaining W beats if required, then assert **`BVALID`** with **`BRESP = SLVERR`** and the relevant ID.

Exact decode conditions are defined in **`src/axi4_to_dfi_bridge.v`** (combinational `aw_ok` / `ar_ok`, `write_pair_error`, and the AXI-domain sequential FSM).

# 6. DFI presentation

## 6.1 Driven outputs (conceptual)

- **Command**: `dfi_address`, `dfi_bank` (low address bits by default), `dfi_ras_n`, `dfi_cas_n`, `dfi_we_n`, `dfi_cs_n`, `dfi_cke`, `dfi_odt`, `dfi_act_n`: idle to NOP-like values except during illustrative read/write pulses.
- **Write data**: `dfi_wrdata`, `dfi_wrdata_mask` (derived from `WSTRB` with PHY-specific interpretation noted in RTL comments), `dfi_wrdata_en`.
- **Read data**: `dfi_rddata_en` during read command; expects **`dfi_rddata`** / **`dfi_rddata_valid`** from the PHY or model.

## 6.2 Stubbed / tied sidebands

`dfi_ctrlupd_req`, `dfi_phyupd_req`, `dfi_lp_ctrl_req` are driven low; `dfi_init_start` is tied low (extend for real MC init). Integrators must connect **`dfi_init_complete`** from the PHY when ready.

# 7. Parameters (top-level)

| Parameter | Typical role |
|-----------|----------------|
| `C_AXI_*` | AXI address/data/ID/user widths. |
| `DFI_*` | DFI address, bank, data, mask, CS, ODT, CKE widths. |
| `CDC_FIFO_DEPTH` | Depth of all four gray FIFOs in the bridge. |
| `DFI_WRITE_ACK_CYCLES` | DFI-clock cycles from write beat to B push. |
| `DFI_READ_DATA_CYCLES` | DFI-clock cycles for read turnaround before R push. |

# 8. Verification

Simulation uses **Icarus Verilog** (`iverilog -g2001`). The testbench **`src/tb_axi4_to_dfi_bridge.v`** provides:

- Independent **`axi_aclk`** and **`dfi_clk`** generators.
- A minimal PHY read-return model and basic write/read scoreboard checks.
- Optional **`+vcd`** for **gtkwave**.

Build and run: **`make -C test run`** (see repository **README.md**).

# 9. Revision history

| Revision | Summary |
|----------|---------|
| 0.1 | Initial design specification from RTL structure. |

# Document control

**Source**: `doc/DESIGN_SPEC.md`: build PDF via `make -C doc pdf` (requires **pandoc** and a LaTeX engine such as **pdflatex**), or HTML via `make -C doc html`.

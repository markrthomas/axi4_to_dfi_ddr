# Integration guide — AXI4 → DFI DDR bridge

Tapeout-readiness program **T7** (integration / packaging) deliverable. This guide + the
IP-XACT in `ip-xact/` are what an SoC integrator needs to instance the IP. The IP-XACT
port list is kept in sync with the RTL by `make pkg`.

## IP

| Top (module / IP-XACT name) | What |
|---|---|
| `axi4_to_dfi_bridge` | AXI4 subordinate → DFI (DDR PHY) initiator memory-controller bridge, with an AXI↔DFI clock-domain crossing. |

## Interfaces

| Interface | Role | Notes |
|---|---|---|
| `S_AXI` | AXI4 **subordinate** (slave) | Full AXI4; `C_AXI_ID_WIDTH` preserved through responses; bursts up to `C_MAX_{WRITE,READ}` len. |
| `DFI`   | DFI **initiator** (master) | JEDEC DFI command/address/write/read + control-update / PHY-update / low-power handshakes. |
| `axi_aclk` / `dfi_clk` | clocks | **Two clock domains** — the AXI↔DFI crossing is the block's CDC (gated by `make cdc`, T1-CDC). |
| `axi_aresetn` / `dfi_rst_n` | resets | Active-low, asynchronous assert; false-paths in `../syn/constraints/axi_dfi.sdc`. |

## Clock / reset / power

- **Clocks:** `axi_aclk` (AXI domain) and `dfi_clk` (DFI/PHY domain). Every crossing goes
  through a sanctioned synchronizer (`cdc_fifo_lib`, `cdc_sync`) — asserted by the
  structural CDC audit `make cdc` (T1-CDC). Constrain both with `../syn/constraints/axi_dfi.sdc` (T2).
- **Reset:** `axi_aresetn` / `dfi_rst_n` async active-low, false-paths in the SDC; drive
  from the SoC reset controller, de-assert synchronously per domain.
- **Power:** the T3 power intent (`../syn/lp/axi_dfi.upf`) models the AXI and DFI domains;
  if the SoC does not power-gate this IP, tie into a single always-on domain.

## Address map

The AXI subordinate is a **memory path to external DRAM** — the IP-XACT `S_AXI_map`
memory map exposes an addressable DRAM block (`C_AXI_ADDR_WIDTH=32` → 4 GiB,
`baseAddress 0`, width `C_AXI_DATA_WIDTH`). The bridge has **no internal control/status
registers** — it is a protocol/clock bridge, so there is no CSR RAL to generate; the
"register map" is this DRAM address space. DRAM geometry (row/col/bank) is set by the
`MC_*` / `DFI_*` parameters, not an address-mapped CSR block.

## Parameters / configuration matrix

| Parameter | Default | Meaning |
|---|---|---|
| `C_AXI_ADDR_WIDTH` | 32 | AXI address width (DRAM address space) |
| `C_AXI_DATA_WIDTH` | 64 | AXI/DFI data width (`WSTRB = DATA/8`) |
| `C_AXI_ID_WIDTH`   | 4  | AXI ID width, preserved through responses |
| `DFI_ADDR_WIDTH` / `DFI_BANK_WIDTH` / `DFI_DATA_WIDTH` | 18 / 3 / 64 | DFI geometry |
| `MC_*` (`T_RP`, `T_RCD`, `CL`, `COL_BITS`, `ROW_BITS`, …) | see RTL header | DRAM timing / geometry for the scheduler |
| `DFI_INIT_START_CYCLES` | 0 | `dfi_init_start` assert width (the directed TB exercises 4) |

## Consuming the package

- **IP-XACT** (`ip-xact/axi4_to_dfi_bridge.xml`): IEEE 1685-2014 component — bus interfaces
  (AXI4 slave, DFI master, two clocks, two resets), the full 71-port model, the `S_AXI_map`
  DRAM memory map, and the parameter set. AXI4 references the standard AMBA bus/abstraction
  defs by VLNV; DFI references a JEDEC DFI bus def (resolved from the integrator's library).
- **RTL** source is referenced from the component's `fileSet`.
- **Validate** with `make pkg` (`pkg/check_ipxact.sh`): well-formed + structural + a hard
  IP-XACT↔RTL model-port match (71 ports; fails on drift). Full XSD: `IPXACT_XSD=… make pkg`.

## Sign-off cross-reference

See [`../syn/SIGNOFF.md`](../syn/SIGNOFF.md) for T0–T7. Items needing a PDK or licensed tool
(real STA, SDF-timing GLS, real PPA, scan+ATPG, power-aware sim) are tagged there.

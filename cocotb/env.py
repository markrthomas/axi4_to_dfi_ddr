"""
Shared AXI4/DFI driver and PHY model for axi4_to_dfi_ddr cocotb tests.

AXI4Driver  : drives the AXI4 slave port of the DUT (single-beat, burst,
              AW-before-W and W-before-AW orderings).
DFIPHYModel : responds on the DFI PHY port — handles the MC_CL read latency
              pipeline and returns {32'hA5A5A5A5, 14'h0, addr[17:0]} per beat.
reset_dut   : brings both clock domains out of reset and asserts dfi_init_complete.
start_phy   : launches the PHY model coroutine, killing any stale instance.
expected_rdata: canonical read-data formula matching the PHY model.
"""

import cocotb
from cocotb.triggers import RisingEdge
from collections import deque

_phy_task = None

BRESP_OKAY   = 0b00
BRESP_SLVERR = 0b10
RRESP_OKAY   = 0b00
RRESP_SLVERR = 0b10


def expected_rdata(addr):
    return (0xA5A5A5A5 << 32) | (addr & 0x3FFFF)


async def reset_dut(dut, axi_clk, dfi_clk):
    """Assert both resets, idle all AXI inputs, then release in DFI→AXI order."""
    dut.axi_aresetn.value        = 0
    dut.dfi_rst_n.value          = 0
    dut.dfi_init_complete.value  = 0
    dut.dfi_ctrlupd_ack.value    = 0
    dut.dfi_phyupd_ack.value     = 0
    dut.dfi_lp_ctrl_ack.value    = 0
    dut.dfi_rddata.value         = 0
    dut.dfi_rddata_valid.value   = 0

    dut.s_axi_awvalid.value  = 0
    dut.s_axi_wvalid.value   = 0
    dut.s_axi_bready.value   = 0
    dut.s_axi_arvalid.value  = 0
    dut.s_axi_rready.value   = 0
    dut.s_axi_awid.value     = 0
    dut.s_axi_awaddr.value   = 0
    dut.s_axi_awlen.value    = 0
    dut.s_axi_awsize.value   = 0b011
    dut.s_axi_awburst.value  = 0b01
    dut.s_axi_awlock.value   = 0
    dut.s_axi_awcache.value  = 0
    dut.s_axi_awprot.value   = 0
    dut.s_axi_awqos.value    = 0
    dut.s_axi_awregion.value = 0
    dut.s_axi_awuser.value   = 0
    dut.s_axi_wdata.value    = 0
    dut.s_axi_wstrb.value    = 0
    dut.s_axi_wlast.value    = 0
    dut.s_axi_wuser.value    = 0
    dut.s_axi_arid.value     = 0
    dut.s_axi_araddr.value   = 0
    dut.s_axi_arlen.value    = 0
    dut.s_axi_arsize.value   = 0b011
    dut.s_axi_arburst.value  = 0b01
    dut.s_axi_arlock.value   = 0
    dut.s_axi_arcache.value  = 0
    dut.s_axi_arprot.value   = 0
    dut.s_axi_arqos.value    = 0
    dut.s_axi_arregion.value = 0
    dut.s_axi_aruser.value   = 0

    for _ in range(5):
        await RisingEdge(axi_clk)

    # Release DFI reset. With DFI_INIT_START_CYCLES=0 (default), dfi_init_start
    # is always 0; assert dfi_init_complete immediately after the DFI reset edge.
    dut.dfi_rst_n.value = 1
    await RisingEdge(dfi_clk)
    dut.dfi_init_complete.value = 1

    for _ in range(3):
        await RisingEdge(axi_clk)
    dut.axi_aresetn.value = 1
    await RisingEdge(axi_clk)


def start_phy(dut, dfi_clk, mc_cl=6):
    """Create and launch the DFI PHY model, killing any still-active prior instance."""
    global _phy_task
    if _phy_task is not None:
        _phy_task.kill()
    phy = DFIPHYModel(dut, dfi_clk, mc_cl=mc_cl)
    _phy_task = cocotb.start_soon(phy.run())
    return phy


class DFIPHYModel:
    """
    Minimal DFI PHY model.

    Mirrors tb_axi4_to_dfi_bridge.v's PHY read-return model:
    - When dfi_rddata_en=1: load countdown = mc_cl.
    - Decrement each dfi_clk cycle.
    - When countdown reaches 1: assert dfi_rddata_valid, return
      {32'hA5A5A5A5, 14'h0, addr[17:0]} dequeued from addr_q.
    """

    def __init__(self, dut, dfi_clk, mc_cl=6):
        self.dut    = dut
        self.clk    = dfi_clk
        self.mc_cl  = mc_cl
        self.addr_q = deque()

    def push_read_addr(self, addr):
        self.addr_q.append(addr & 0xFFFF_FFFF)

    async def run(self):
        dut = self.dut
        clk = self.clk
        phy_rd_lat = 0

        while True:
            await RisingEdge(clk)

            try:
                rddata_en = int(dut.dfi_rddata_en.value)
            except ValueError:
                rddata_en = 0

            dut.dfi_rddata_valid.value = 0

            if rddata_en:
                phy_rd_lat = self.mc_cl
            elif phy_rd_lat != 0:
                if phy_rd_lat == 1:
                    if self.addr_q:
                        addr = self.addr_q.popleft()
                        dut.dfi_rddata.value       = expected_rdata(addr)
                        dut.dfi_rddata_valid.value = 1
                    phy_rd_lat = 0
                else:
                    phy_rd_lat -= 1


class AXI4Driver:
    """AXI4 master driver for the DUT's slave port (all-lowercase port names)."""

    def __init__(self, dut, axi_clk, phy):
        self.dut = dut
        self.clk = axi_clk
        self.phy = phy

    # ------------------------------------------------------------------
    # Write helpers
    # ------------------------------------------------------------------

    async def write(self, addr, data, awid=0, strb=0xFF, awburst=0b01):
        """Single-beat write: AW and W driven simultaneously."""
        dut = self.dut
        clk = self.clk

        dut.s_axi_awid.value    = awid
        dut.s_axi_awaddr.value  = addr
        dut.s_axi_awlen.value   = 0
        dut.s_axi_awsize.value  = 0b011
        dut.s_axi_awburst.value = awburst
        dut.s_axi_awvalid.value = 1
        dut.s_axi_wdata.value   = data
        dut.s_axi_wstrb.value   = strb
        dut.s_axi_wlast.value   = 1
        dut.s_axi_wvalid.value  = 1

        aw_done = False
        w_done  = False
        for _ in range(128):
            await RisingEdge(clk)
            if not aw_done and int(dut.s_axi_awready.value) == 1:
                dut.s_axi_awvalid.value = 0
                aw_done = True
            if not w_done and int(dut.s_axi_wready.value) == 1:
                dut.s_axi_wvalid.value = 0
                w_done = True
            if aw_done and w_done:
                break
        else:
            raise AssertionError(f"Timeout on AW/W handshake (addr=0x{addr:08x})")

        return await self._wait_b(addr)

    async def write_aw_then_w(self, addr, data, awid=0, strb=0xFF, gap=2):
        """AW handshake first, gap cycles, then W handshake."""
        dut = self.dut
        clk = self.clk

        dut.s_axi_awid.value    = awid
        dut.s_axi_awaddr.value  = addr
        dut.s_axi_awlen.value   = 0
        dut.s_axi_awsize.value  = 0b011
        dut.s_axi_awburst.value = 0b01
        dut.s_axi_awvalid.value = 1

        for _ in range(128):
            await RisingEdge(clk)
            if int(dut.s_axi_awready.value) == 1:
                dut.s_axi_awvalid.value = 0
                break
        else:
            raise AssertionError(f"Timeout on AW handshake (addr=0x{addr:08x})")

        for _ in range(gap):
            await RisingEdge(clk)

        dut.s_axi_wdata.value  = data
        dut.s_axi_wstrb.value  = strb
        dut.s_axi_wlast.value  = 1
        dut.s_axi_wvalid.value = 1

        for _ in range(128):
            await RisingEdge(clk)
            if int(dut.s_axi_wready.value) == 1:
                dut.s_axi_wvalid.value = 0
                break
        else:
            raise AssertionError(f"Timeout on W handshake (addr=0x{addr:08x})")

        return await self._wait_b(addr)

    async def write_w_then_aw(self, addr, data, awid=0, strb=0xFF, gap=2):
        """W handshake first, gap cycles, then AW handshake."""
        dut = self.dut
        clk = self.clk

        dut.s_axi_wdata.value  = data
        dut.s_axi_wstrb.value  = strb
        dut.s_axi_wlast.value  = 1
        dut.s_axi_wvalid.value = 1

        for _ in range(128):
            await RisingEdge(clk)
            if int(dut.s_axi_wready.value) == 1:
                dut.s_axi_wvalid.value = 0
                break
        else:
            raise AssertionError(f"Timeout on W handshake (addr=0x{addr:08x})")

        for _ in range(gap):
            await RisingEdge(clk)

        dut.s_axi_awid.value    = awid
        dut.s_axi_awaddr.value  = addr
        dut.s_axi_awlen.value   = 0
        dut.s_axi_awsize.value  = 0b011
        dut.s_axi_awburst.value = 0b01
        dut.s_axi_awvalid.value = 1

        for _ in range(128):
            await RisingEdge(clk)
            if int(dut.s_axi_awready.value) == 1:
                dut.s_axi_awvalid.value = 0
                break
        else:
            raise AssertionError(f"Timeout on AW handshake (addr=0x{addr:08x})")

        return await self._wait_b(addr)

    async def burst_write(self, addr, data_list, awid=0, strb=0xFF):
        """INCR burst write: AW first, then beat-by-beat W, single B."""
        dut    = self.dut
        clk    = self.clk
        length = len(data_list)

        dut.s_axi_awid.value    = awid
        dut.s_axi_awaddr.value  = addr
        dut.s_axi_awlen.value   = length - 1
        dut.s_axi_awsize.value  = 0b011
        dut.s_axi_awburst.value = 0b01
        dut.s_axi_awvalid.value = 1

        for _ in range(128):
            await RisingEdge(clk)
            if int(dut.s_axi_awready.value) == 1:
                dut.s_axi_awvalid.value = 0
                break
        else:
            raise AssertionError(f"Timeout on AW handshake (burst addr=0x{addr:08x})")

        for i, beat_data in enumerate(data_list):
            dut.s_axi_wdata.value  = beat_data
            dut.s_axi_wstrb.value  = strb
            dut.s_axi_wlast.value  = 1 if i == length - 1 else 0
            dut.s_axi_wvalid.value = 1
            for _ in range(128):
                await RisingEdge(clk)
                if int(dut.s_axi_wready.value) == 1:
                    break
            else:
                raise AssertionError(f"Timeout on W beat {i} (addr=0x{addr:08x})")
        dut.s_axi_wvalid.value = 0

        return await self._wait_b(addr)

    async def _wait_b(self, addr, timeout=256):
        dut = self.dut
        clk = self.clk
        for _ in range(timeout):
            await RisingEdge(clk)
            if int(dut.s_axi_bvalid.value) == 1:
                bresp = int(dut.s_axi_bresp.value)
                dut.s_axi_bready.value = 1
                await RisingEdge(clk)
                dut.s_axi_bready.value = 0
                return bresp
        raise AssertionError(f"Timeout waiting for BVALID (addr=0x{addr:08x})")

    # ------------------------------------------------------------------
    # Read helpers
    # ------------------------------------------------------------------

    async def read(self, addr, arid=0):
        """Single-beat read; pushes addr to PHY queue after AR handshake."""
        dut = self.dut
        clk = self.clk

        dut.s_axi_arid.value    = arid
        dut.s_axi_araddr.value  = addr
        dut.s_axi_arlen.value   = 0
        dut.s_axi_arsize.value  = 0b011
        dut.s_axi_arburst.value = 0b01
        dut.s_axi_arvalid.value = 1
        dut.s_axi_rready.value  = 1

        for _ in range(128):
            await RisingEdge(clk)
            if int(dut.s_axi_arready.value) == 1:
                self.phy.push_read_addr(addr)
                dut.s_axi_arvalid.value = 0
                break
        else:
            raise AssertionError(f"Timeout on AR handshake (addr=0x{addr:08x})")

        for _ in range(512):
            await RisingEdge(clk)
            if int(dut.s_axi_rvalid.value) == 1:
                rdata = int(dut.s_axi_rdata.value)
                rresp = int(dut.s_axi_rresp.value)
                dut.s_axi_rready.value = 0
                return rdata, rresp
        raise AssertionError(f"Timeout waiting for RVALID (addr=0x{addr:08x})")

    async def read_illegal_size(self, addr, arid=0, arsize=0b010):
        """Read with non-full-width arsize — bridge must return SLVERR."""
        dut = self.dut
        clk = self.clk

        dut.s_axi_arid.value    = arid
        dut.s_axi_araddr.value  = addr
        dut.s_axi_arlen.value   = 0
        dut.s_axi_arsize.value  = arsize
        dut.s_axi_arvalid.value = 1
        dut.s_axi_rready.value  = 1

        for _ in range(128):
            await RisingEdge(clk)
            if int(dut.s_axi_arready.value) == 1:
                dut.s_axi_arvalid.value = 0
                dut.s_axi_arsize.value  = 0b011
                break
        else:
            raise AssertionError(f"Timeout on AR handshake (illegal size, addr=0x{addr:08x})")

        for _ in range(512):
            await RisingEdge(clk)
            if int(dut.s_axi_rvalid.value) == 1:
                rdata = int(dut.s_axi_rdata.value)
                rresp = int(dut.s_axi_rresp.value)
                dut.s_axi_rready.value = 0
                return rdata, rresp
        raise AssertionError(f"Timeout waiting for RVALID (illegal size, addr=0x{addr:08x})")

    async def burst_read(self, addr, length, arid=0):
        """INCR burst read; pushes one addr per beat to PHY queue."""
        dut = self.dut
        clk = self.clk

        dut.s_axi_arid.value    = arid
        dut.s_axi_araddr.value  = addr
        dut.s_axi_arlen.value   = length - 1
        dut.s_axi_arsize.value  = 0b011
        dut.s_axi_arburst.value = 0b01
        dut.s_axi_arvalid.value = 1
        dut.s_axi_rready.value  = 1

        for _ in range(128):
            await RisingEdge(clk)
            if int(dut.s_axi_arready.value) == 1:
                for i in range(length):
                    self.phy.push_read_addr(addr + i * 8)
                dut.s_axi_arvalid.value = 0
                break
        else:
            raise AssertionError(f"Timeout on AR handshake (burst addr=0x{addr:08x})")

        beats = []
        resps = []
        for _ in range(length * 512):
            await RisingEdge(clk)
            if int(dut.s_axi_rvalid.value) == 1:
                beats.append(int(dut.s_axi_rdata.value))
                resps.append(int(dut.s_axi_rresp.value))
                if int(dut.s_axi_rlast.value) == 1:
                    dut.s_axi_rready.value = 0
                    return beats, resps
        raise AssertionError(
            f"Timeout collecting {length} beats, got {len(beats)} (addr=0x{addr:08x})"
        )

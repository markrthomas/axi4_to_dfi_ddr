"""
cocotb tests for axi4_to_dfi_bridge.

Mirrors the UVM DV scenarios from uvm_dv/seq/:
  smoke_seq      — single write/read, INCR burst write/read
  mc_cmd_test    — AW-before-W and W-before-AW orderings
  burst_rw_test  — 4-beat INCR burst write then per-beat single reads
  backpressure   — B/R channel backpressure (BVALID/RVALID held stable)
  slverr_test    — illegal burst type → BRESP=SLVERR

PHY read data formula (must match DFIPHYModel.run()):
  rdata = {32'hA5A5A5A5, 14'h0, addr[17:0]}
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from env import (
    AXI4Driver, DFIPHYModel,
    BRESP_OKAY, BRESP_SLVERR, RRESP_OKAY, RRESP_SLVERR,
    expected_rdata, reset_dut, start_phy,
)


@cocotb.test()
async def test_single_write_read(dut):
    """Single-beat write then read; verifies DFI read-data formula."""
    axi_clk = dut.axi_aclk
    dfi_clk = dut.dfi_clk
    cocotb.start_soon(Clock(axi_clk, 20, units="ns").start())
    cocotb.start_soon(Clock(dfi_clk, 14, units="ns").start())
    await reset_dut(dut, axi_clk, dfi_clk)
    phy = start_phy(dut, dfi_clk)
    axi = AXI4Driver(dut, axi_clk, phy)

    ADDR = 0x0000_1000
    WDATA = 0xDEAD_BEEF_0000_0001

    bresp = await axi.write(ADDR, WDATA)
    assert bresp == BRESP_OKAY, f"Write BRESP: {bresp:#04b}"

    rdata, rresp = await axi.read(ADDR)
    assert rresp  == RRESP_OKAY,          f"Read RRESP: {rresp:#04b}"
    assert rdata  == expected_rdata(ADDR), f"RDATA: 0x{rdata:016x}"


@cocotb.test()
async def test_burst_write_read(dut):
    """4-beat INCR burst write, then single reads per beat.

    Mirrors smoke_seq 3b: axi_write_incr_burst + four axi_read_single calls.
    """
    axi_clk = dut.axi_aclk
    dfi_clk = dut.dfi_clk
    cocotb.start_soon(Clock(axi_clk, 20, units="ns").start())
    cocotb.start_soon(Clock(dfi_clk, 14, units="ns").start())
    await reset_dut(dut, axi_clk, dfi_clk)
    phy = start_phy(dut, dfi_clk)
    axi = AXI4Driver(dut, axi_clk, phy)

    BASE   = 0x0000_9000
    BEATS  = [0xBEEF9000_00000001 + i * 8 for i in range(4)]

    bresp = await axi.burst_write(BASE, BEATS)
    assert bresp == BRESP_OKAY, f"Burst write BRESP: {bresp:#04b}"

    for i in range(4):
        addr = BASE + i * 8
        rdata, rresp = await axi.read(addr)
        assert rresp  == RRESP_OKAY,           f"Beat {i} RRESP: {rresp:#04b}"
        assert rdata  == expected_rdata(addr),  f"Beat {i} RDATA: 0x{rdata:016x}"


@cocotb.test()
async def test_aw_before_w(dut):
    """AW channel handshake arrives 2 cycles before W; verifies W buffer."""
    axi_clk = dut.axi_aclk
    dfi_clk = dut.dfi_clk
    cocotb.start_soon(Clock(axi_clk, 20, units="ns").start())
    cocotb.start_soon(Clock(dfi_clk, 14, units="ns").start())
    await reset_dut(dut, axi_clk, dfi_clk)
    phy = start_phy(dut, dfi_clk)
    axi = AXI4Driver(dut, axi_clk, phy)

    ADDR  = 0x0000_2008
    WDATA = 0xCAFE_BABE_1234_5678

    bresp = await axi.write_aw_then_w(ADDR, WDATA, gap=2)
    assert bresp == BRESP_OKAY, f"BRESP: {bresp:#04b}"

    rdata, rresp = await axi.read(ADDR)
    assert rresp  == RRESP_OKAY,           f"RRESP: {rresp:#04b}"
    assert rdata  == expected_rdata(ADDR), f"RDATA: 0x{rdata:016x}"


@cocotb.test()
async def test_w_before_aw(dut):
    """W channel handshake arrives 2 cycles before AW; verifies AW buffer."""
    axi_clk = dut.axi_aclk
    dfi_clk = dut.dfi_clk
    cocotb.start_soon(Clock(axi_clk, 20, units="ns").start())
    cocotb.start_soon(Clock(dfi_clk, 14, units="ns").start())
    await reset_dut(dut, axi_clk, dfi_clk)
    phy = start_phy(dut, dfi_clk)
    axi = AXI4Driver(dut, axi_clk, phy)

    ADDR  = 0x0000_3010
    WDATA = 0x1122_3344_5566_7788

    bresp = await axi.write_w_then_aw(ADDR, WDATA, strb=0xF0, gap=2)
    assert bresp == BRESP_OKAY, f"BRESP: {bresp:#04b}"


@cocotb.test()
async def test_b_backpressure(dut):
    """Two writes with BREADY withheld; BVALID must remain stable."""
    axi_clk = dut.axi_aclk
    dfi_clk = dut.dfi_clk
    cocotb.start_soon(Clock(axi_clk, 20, units="ns").start())
    cocotb.start_soon(Clock(dfi_clk, 14, units="ns").start())
    await reset_dut(dut, axi_clk, dfi_clk)
    phy = start_phy(dut, dfi_clk)
    axi = AXI4Driver(dut, axi_clk, phy)
    dut.s_axi_bready.value = 0

    # Issue both writes without accepting B responses.
    for addr, data in [
        (0x0000_4000, 0xABCD_EF00_0000_0001),
        (0x0000_4008, 0xABCD_EF00_0000_0002),
    ]:
        dut.s_axi_awid.value    = 0
        dut.s_axi_awaddr.value  = addr
        dut.s_axi_awlen.value   = 0
        dut.s_axi_awsize.value  = 0b011
        dut.s_axi_awburst.value = 0b01
        dut.s_axi_awvalid.value = 1
        dut.s_axi_wdata.value   = data
        dut.s_axi_wstrb.value   = 0xFF
        dut.s_axi_wlast.value   = 1
        dut.s_axi_wvalid.value  = 1

        aw_done = w_done = False
        for _ in range(128):
            await RisingEdge(axi_clk)
            if not aw_done and int(dut.s_axi_awready.value) == 1:
                dut.s_axi_awvalid.value = 0
                aw_done = True
            if not w_done and int(dut.s_axi_wready.value) == 1:
                dut.s_axi_wvalid.value = 0
                w_done = True
            if aw_done and w_done:
                break

    # Wait for first BVALID, then stall 4 cycles to verify stability.
    for _ in range(256):
        await RisingEdge(axi_clk)
        if int(dut.s_axi_bvalid.value) == 1:
            break
    else:
        raise AssertionError("Timeout waiting for first BVALID")

    for i in range(4):
        assert int(dut.s_axi_bvalid.value) == 1, f"BVALID dropped at stall cycle {i}"
        await RisingEdge(axi_clk)

    # Accept both responses.
    dut.s_axi_bready.value = 1
    await RisingEdge(axi_clk)
    assert int(dut.s_axi_bresp.value) == BRESP_OKAY, "First BRESP not OKAY"
    dut.s_axi_bready.value = 0
    await RisingEdge(axi_clk)

    for _ in range(128):
        await RisingEdge(axi_clk)
        if int(dut.s_axi_bvalid.value) == 1:
            assert int(dut.s_axi_bresp.value) == BRESP_OKAY, "Second BRESP not OKAY"
            dut.s_axi_bready.value = 1
            await RisingEdge(axi_clk)
            dut.s_axi_bready.value = 0
            return
    raise AssertionError("Timeout waiting for second BVALID")


@cocotb.test()
async def test_r_backpressure(dut):
    """Read with RREADY withheld; RVALID must remain stable for 4 cycles."""
    axi_clk = dut.axi_aclk
    dfi_clk = dut.dfi_clk
    cocotb.start_soon(Clock(axi_clk, 20, units="ns").start())
    cocotb.start_soon(Clock(dfi_clk, 14, units="ns").start())
    await reset_dut(dut, axi_clk, dfi_clk)
    phy = start_phy(dut, dfi_clk)
    axi = AXI4Driver(dut, axi_clk, phy)

    ADDR = 0x0000_5000
    dut.s_axi_rready.value = 0  # hold off before issuing AR

    dut.s_axi_arid.value    = 0
    dut.s_axi_araddr.value  = ADDR
    dut.s_axi_arlen.value   = 0
    dut.s_axi_arsize.value  = 0b011
    dut.s_axi_arburst.value = 0b01
    dut.s_axi_arvalid.value = 1

    for _ in range(128):
        await RisingEdge(axi_clk)
        if int(dut.s_axi_arready.value) == 1:
            phy.push_read_addr(ADDR)
            dut.s_axi_arvalid.value = 0
            break
    else:
        raise AssertionError("Timeout on AR handshake")

    # Wait for RVALID while RREADY is still 0.
    for _ in range(512):
        await RisingEdge(axi_clk)
        if int(dut.s_axi_rvalid.value) == 1:
            break
    else:
        raise AssertionError("Timeout waiting for RVALID")

    exp = expected_rdata(ADDR)
    for i in range(4):
        assert int(dut.s_axi_rvalid.value) == 1,  f"RVALID dropped at stall cycle {i}"
        assert int(dut.s_axi_rdata.value)  == exp, f"RDATA changed at stall cycle {i}"
        await RisingEdge(axi_clk)

    dut.s_axi_rready.value = 1
    await RisingEdge(axi_clk)
    assert int(dut.s_axi_rresp.value) == RRESP_OKAY, "RRESP not OKAY"
    dut.s_axi_rready.value = 0


@cocotb.test()
async def test_slverr_illegal_burst(dut):
    """FIXED burst (awburst=0b00) must be rejected with BRESP=SLVERR."""
    axi_clk = dut.axi_aclk
    dfi_clk = dut.dfi_clk
    cocotb.start_soon(Clock(axi_clk, 20, units="ns").start())
    cocotb.start_soon(Clock(dfi_clk, 14, units="ns").start())
    await reset_dut(dut, axi_clk, dfi_clk)
    phy = start_phy(dut, dfi_clk)
    axi = AXI4Driver(dut, axi_clk, phy)

    ADDR = 0x0000_0200

    bresp = await axi.write(ADDR, 0x1111_2222_3333_4444, awburst=0b00)
    assert bresp == BRESP_SLVERR, f"Expected SLVERR for FIXED burst, got {bresp:#04b}"

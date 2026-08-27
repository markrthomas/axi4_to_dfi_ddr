# Verilator UVM flow for the AXI4->DFI/DDR bridge UVM environment
# (../ = uvm_dv; RTL in <repo>/src).
#
# Runs the *same* SystemVerilog UVM env as VCS would, but under open-source
# Verilator (>= 5.050) with the Accellera UVM 2020.3.1 library bundled in the
# Verilator source tree (test_regress/t/uvm).
#
# Quick start (local lint is RAM-safe; the full --binary build belongs in CI):
#   V=~/verilator/bin/verilator ; U=~/verilator/test_regress/t/uvm
#   ( unset VERILATOR_ROOT; make -C uvm_dv/vlt lint  VERILATOR=$V UVM_HOME=$U )
#   ( unset VERILATOR_ROOT; make -C uvm_dv/vlt smoke VERILATOR=$V UVM_HOME=$U )

VERILATOR ?= verilator

UVM_HOME ?= $(error Set UVM_HOME to the bundled Verilator UVM dir, e.g. \
  ~/verilator/test_regress/t/uvm)
UVM_HDR := $(UVM_HOME)/uvm_pkg_all_v2020_3_1_dpi.svh
UVM_DPI := $(UVM_HOME)/v2020_3_1/dpi/uvm_dpi.cc

BUILD_JOBS ?= 1
UVM_TEST   ?= smoke_test

VFLAGS ?= --binary --timing --vpi -j $(BUILD_JOBS) --build-jobs $(BUILD_JOBS) \
          -Wno-fatal -Wno-COVERIGN -Wno-TIMESCALEMOD --CFLAGS -O0
UVM_PLUSARGS ?= +UVM_NO_RELNOTES

VLT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
DV      := $(abspath $(VLT_DIR)/..)
SRC     := $(abspath $(VLT_DIR)/../../src)
OBJ     := $(VLT_DIR)/obj

INCS := +incdir+$(DV)/if +incdir+$(DV)/env +incdir+$(DV)/seq +incdir+$(DV)/tests \
        +incdir+$(DV)/tb +incdir+$(VLT_DIR) +incdir+$(UVM_HOME)

# Order matches uvm_dv/filelist.f: RTL, interfaces, packages, TB top.
SRCS := $(SRC)/cdc_fifo_lib.v $(SRC)/mc_dfi_scheduler.v \
        $(SRC)/axi4_bridge_frontend.v $(SRC)/dfi_adapter.v \
        $(SRC)/axi4_to_dfi_bridge.v \
        $(DV)/if/axi4_if.sv $(DV)/if/dfi_if.sv \
        $(DV)/env/axi4_dfi_env_pkg.sv $(DV)/seq/axi4_dfi_seq_pkg.sv \
        $(DV)/tests/axi4_dfi_test_pkg.sv $(DV)/tb/tb_top.sv

define build
	rm -rf $(OBJ)/tb_top
	mkdir -p $(OBJ)/tb_top
	$(VERILATOR) $(VFLAGS) --top-module tb_top --Mdir $(OBJ)/tb_top \
	  $(INCS) $(UVM_HDR) $(UVM_DPI) $(SRCS)
endef
define run
	$(OBJ)/tb_top/Vtb_top $(UVM_PLUSARGS) +UVM_TESTNAME=$(1)
endef

.PHONY: all build smoke lint clean

all: smoke

build:
	$(build)

# The TB top calls run_test() with no default, so the test is chosen here.
smoke: build
	$(call run,$(UVM_TEST))

LINTFLAGS ?= --lint-only --timing -Wno-fatal -Wno-COVERIGN -Wno-TIMESCALEMOD
lint:
	$(VERILATOR) $(LINTFLAGS) --top-module tb_top $(INCS) $(UVM_HDR) $(SRCS)

clean:
	rm -rf $(OBJ)

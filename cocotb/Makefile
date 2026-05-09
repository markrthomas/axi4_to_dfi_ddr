SIM          ?= icarus
TOPLEVEL_LANG = verilog

SRC_DIR := $(PWD)/../src

VERILOG_SOURCES = \
    $(SRC_DIR)/cdc_fifo_lib.v \
    $(SRC_DIR)/mc_dfi_scheduler.v \
    $(SRC_DIR)/axi4_bridge_frontend.v \
    $(SRC_DIR)/dfi_adapter.v \
    $(SRC_DIR)/axi4_to_dfi_bridge.v

TOPLEVEL = axi4_to_dfi_bridge
MODULE   = test_dfi_bridge

# Use system iverilog/vvp (v11) to avoid OSS CAD Suite Python path conflicts.
ICARUS_BIN_DIR ?= /usr/bin
COMPILE_ARGS    = -g2001

export PYTHONPATH := $(PWD):$(PYTHONPATH)

# Strip OSS CAD Suite Python environment so cocotb's pip-installed VPI loads cleanly.
SIM_CMD_PREFIX          := env -u VIRTUAL_ENV -u PYTHONHOME
export PYGPI_PYTHON_BIN := $(shell cocotb-config --python-bin)

include $(shell cocotb-config --makefiles)/Makefile.sim

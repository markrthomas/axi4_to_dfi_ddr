# Build and run AXI4→DFI bridge simulation (Icarus Verilog).
#
# Usage (from repo root):  make -C test <target>
# Usage (from test/):      make <target>
#
# Targets:
#   build   Compile only (outputs build/sim.vvp)
#   run     Build if needed, run simulation (default for `all`)
#   test    Same as run
#   vcd     Run with +vcd; writes build/sim.vcd for gtkwave
#   wave    Run vcd then launch gtkwave on build/sim.vcd (if gtkwave in PATH)
#   clean   Remove build/
#   help    Show this summary

SRC_DIR   := ../src
BUILD_DIR := build
SIM       := $(BUILD_DIR)/sim.vvp
VCD       := $(BUILD_DIR)/sim.vcd
SOURCES   := $(SRC_DIR)/axi4_to_dfi_bridge.v $(SRC_DIR)/tb_axi4_to_dfi_bridge.v

IVERILOG  := iverilog
VVP       := vvp
IVERFLAGS := -g2001 -Wall

.PHONY: all build run test vcd wave clean help

all: run

help:
	@echo "Targets: build  run  test  vcd  wave  clean  help"
	@echo "  build  - compile to $(SIM)"
	@echo "  run    - compile (if needed) and run tests"
	@echo "  vcd    - run tests and write $(VCD) (open with gtkwave)"
	@echo "  wave   - vcd + gtkwave $(VCD)"

build: $(SIM)

$(SIM): $(SOURCES)
	mkdir -p $(dir $@)
	$(IVERILOG) $(IVERFLAGS) -o $(SIM) $(SOURCES)

run: $(SIM)
	$(VVP) $(SIM)

test: run

vcd: $(SIM)
	$(VVP) $(SIM) +vcd
	@echo "VCD: $(VCD)  (gtkwave $(VCD))"

wave: vcd
	@if command -v gtkwave >/dev/null 2>&1; then \
		gtkwave $(VCD) & \
	else \
		echo "gtkwave not found in PATH; open $(VCD) manually"; \
		exit 1; \
	fi

clean:
	rm -rf $(BUILD_DIR)

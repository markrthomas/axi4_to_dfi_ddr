# UVM DV Makefile for the AXI4-to-DFI bridge — targets VCS + UVM 1.2.
#
# Usage:
#   make build                     Compile (default test: smoke_test)
#   make run TEST=smoke_test        Compile + run
#   make run TEST=mc_cmd_test
#   make run TEST=burst_rw_test
#   make run TEST=fifo_depth_test
#   make run TEST=slverr_test
#   make run TEST=stress_test
#   make run-all                   Run all tests in sequence
#   make clean                     Remove build/
#
# Requires VCS in PATH.  UVM 1.2 is bundled with VCS via -ntb_opts uvm-1.2.
# If your VCS uses a different UVM flag (e.g. -uvm) adjust UVM_FLAG below.

VCS      := vcs
SIMV_DIR := build
SIMV     := $(SIMV_DIR)/simv

# Verbosity: UVM_NONE UVM_LOW UVM_MEDIUM UVM_HIGH UVM_FULL UVM_DEBUG
VERB     ?= UVM_LOW
TEST     ?= smoke_test
SEED     ?= 1

# VCS compile flags
VCS_FLAGS := \
    -full64                         \
    -sverilog                       \
    -timescale=1ns/1ps              \
    -ntb_opts uvm-1.2               \
    +define+UVM_NO_DEPRECATED       \
    +define+UVM_OBJECT_MUST_HAVE_CONSTRUCTOR \
    -l $(SIMV_DIR)/compile.log      \
    -o $(SIMV)                      \
    +incdir+env                     \
    +incdir+seq                     \
    +incdir+tests                   \
    -f filelist.f

# Optional: add +define+TB_TIMEOUT_NS=600000000 to override hard timeout
VCS_FLAGS += +define+TB_TIMEOUT_NS=600000000

# Run flags
RUN_FLAGS := \
    +UVM_TESTNAME=$(TEST)           \
    +UVM_VERBOSITY=$(VERB)          \
    +ntb_random_seed=$(SEED)        \
    -l $(SIMV_DIR)/$(TEST)_$(SEED).log

TESTS := smoke_test mc_cmd_test burst_rw_test fifo_depth_test slverr_test stress_test

SIM_TIMEOUT ?= 300

.PHONY: all build run run-all clean help

all: run

build: $(SIMV)

$(SIMV): filelist.f $(wildcard ../src/*.v if/*.sv env/*.sv seq/*.sv tests/*.sv tb/*.sv)
	mkdir -p $(SIMV_DIR)
	$(VCS) $(VCS_FLAGS)

run: $(SIMV)
	timeout $(SIM_TIMEOUT) $(SIMV) $(RUN_FLAGS)

run-all: $(SIMV)
	@status=0; \
	for t in $(TESTS); do \
	    echo "=== Running $$t ==="; \
	    timeout $(SIM_TIMEOUT) $(SIMV) +UVM_TESTNAME=$$t \
	        +UVM_VERBOSITY=$(VERB) +ntb_random_seed=$(SEED) \
	        -l $(SIMV_DIR)/$${t}_$(SEED).log || status=$$?; \
	done; \
	exit $$status

clean:
	rm -rf $(SIMV_DIR) csrc ucli.key vc_hdrs.h .vloganfile

help:
	@echo "Targets: build run run-all clean"
	@echo "  make run TEST=<name> VERB=UVM_MEDIUM SEED=<n>"
	@echo "  Tests: $(TESTS)"
	@echo "  SIM_TIMEOUT=<seconds>  (default 300)"

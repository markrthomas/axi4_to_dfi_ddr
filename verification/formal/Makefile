SBY ?= sby

.PHONY: all bmc cover clean

all: bmc cover

bmc:
	@command -v $(SBY) >/dev/null 2>&1 || { echo "[FORMAL] sby not found; install SymbiYosys to run BMC"; exit 0; }
	$(SBY) -f async_fifo.sby bmc

cover:
	@command -v $(SBY) >/dev/null 2>&1 || { echo "[FORMAL] sby not found; install SymbiYosys to run cover"; exit 0; }
	$(SBY) -f async_fifo.sby cover

clean:
	rm -rf async_fifo_bmc/ async_fifo_cover/

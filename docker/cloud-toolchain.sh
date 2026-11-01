#!/usr/bin/env bash
# docker/cloud-toolchain.sh — minimal toolchain for the random-regression flows in a bare cloud
# container (Ubuntu): Icarus 12 + Verilator 5.050 (from source, ~10-20 min once) + zlib/lz4 headers.
# Not installed here: Yosys/SBY/SystemC/cocotb (formal, systemc, cocotb flows) - see docs/TOOLCHAIN.md.
# Idempotent; installs to $HOME/.local and prints the PATH line to export.
set -euo pipefail
PREFIX="${PREFIX:-$HOME/.local}"
SUDO=""; [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null && SUDO=sudo
export PATH="$PREFIX/bin:$PATH"

if ! command -v iverilog >/dev/null || [ "$(iverilog -V 2>&1 | sed -n 's/.*version \([0-9]*\)\..*/\1/p' | head -1)" -lt 12 ]; then
  $SUDO apt-get update -qq
  $SUDO apt-get install -y -qq iverilog
fi
if ! command -v verilator >/dev/null || ! verilator --version | grep -q ' 5\.0[3-9]'; then
  $SUDO apt-get update -qq
  $SUDO apt-get install -y -qq git make g++ ccache autoconf flex bison libfl-dev help2man perl \
      python3 zlib1g-dev liblz4-dev
  rm -rf "$HOME/src/verilator"; mkdir -p "$HOME/src"
  git clone --depth 1 -b v5.050 https://github.com/verilator/verilator "$HOME/src/verilator"
  (cd "$HOME/src/verilator" && autoconf && ./configure --prefix="$PREFIX" && make -j"$(nproc)" && make install)
fi
unset VERILATOR_ROOT   # breaks the UVM flow; never set it
iverilog -V 2>&1 | head -1
verilator --version
echo "export PATH=$PREFIX/bin:\$PATH"

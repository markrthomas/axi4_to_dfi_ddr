# pkg/ — IP packaging (tapeout-readiness T7)

Packaging deliverables for the AXI4 → DFI DDR bridge, so an SoC integrator can instance the
IP. Adopted from the shared sign-off kit (`dv-swarm-kit/templates/signoff/pkg`), pathfound
on `IP-axi-to-2apbs`.

## Contents

| Path | What |
|---|---|
| `ip-xact/axi4_to_dfi_bridge.xml` | IP-XACT (IEEE 1685-2014) component (71 ports; AXI4 slave + DFI master + 2 clocks + 2 resets; DRAM memory map; parameters). |
| `INTEGRATION.md` | Integration guide: interfaces, clock/reset/power (CDC), address map, parameter/config matrix. |
| `check_ipxact.sh` | The `make pkg` gate: well-formed + structural + IP-XACT↔RTL port-sync. |

## Run the gate

```
make pkg          # xmllint well-formed + structural + model-ports-match-RTL (71)
IPXACT_XSD=/path/to/1685-2014/index.xsd make pkg   # + full XSD schema validation
```

`make pkg` is wired into CI and fails on any drift between the IP-XACT model ports and the
RTL — so the package cannot silently fall out of sync with the design.

## Scope

OSS, no-PDK packaging layer. Real-silicon collateral needing a PDK or licensed tool
(timing/STA, SDF-timing GLS, real PPA, scan/ATPG, power-aware sim) is tracked in
[`../syn/SIGNOFF.md`](../syn/SIGNOFF.md), not duplicated here.

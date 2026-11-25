#!/usr/bin/env bash
# check_ipxact.sh — canonical T7 packaging gate (OSS pathfinder).
#
# Part of the tapeout-readiness program (workspace DESIGN_READINESS.md). Adopt by
# copying into a repo's pkg/ and setting the vars below. Validates the IP-XACT
# (IEEE 1685-2014) component descriptions that package this IP. Three checks, all real
# artifacts, no licensed tool required:
#   1. WELL-FORMED   — xmllint parses each component XML.
#   2. STRUCTURAL    — the required IP-XACT elements are present
#                      (vendor/library/name/version, model, busInterfaces).
#   3. RTL-IN-SYNC   — the set of model ports in the IP-XACT EXACTLY matches the RTL
#                      module's port list. This is the check that matters: it fails the
#                      gate if the package drifts from the RTL (a renamed/added/removed
#                      port). Port *widths* are parametric expressions in the XML and are
#                      reviewed against the design contract, not re-derived here.
# Full XSD schema validation is an optional extra: set IPXACT_XSD=/path/to/index.xsd to
# enable it (the 1685-2014 schema is not redistributed here). Absent that, a skip is
# reported honestly as "not run", never as a pass.
#
# Config (env or edit the defaults below):
#   TOPS     space-separated top module names (one component XML per top)
#   RTL      space-separated source files (used to locate each top's RTL module)
#   XML_DIR  directory holding <top>.xml component files (default pkg/ip-xact)
set -euo pipefail
# --- adopted defaults for axi4_to_dfi_ddr (override via env) ---
TOPS="${TOPS:-axi4_to_dfi_bridge}"
RTL="${RTL:-src/cdc_fifo_lib.v src/mc_dfi_scheduler.v src/axi4_bridge_frontend.v src/dfi_adapter.v src/axi4_to_dfi_bridge.v}"
XML_DIR="${XML_DIR:-pkg/ip-xact}"
RTL="$(printf '%s ' $RTL)"

command -v xmllint >/dev/null || { echo "[PKG] xmllint not on PATH — SKIP (needs libxml2-utils)"; exit 0; }

rc=0
for TOP in $TOPS; do
  xml="$XML_DIR/$TOP.xml"
  # locate the RTL file that declares this top (fall back to src/<top>.v)
  rtl=""; for f in $RTL; do grep -qE "^[ \t]*module[ \t]+$TOP\b" "$f" 2>/dev/null && { rtl="$f"; break; }; done
  [ -n "$rtl" ] || rtl="src/$TOP.v"
  echo "[PKG] === $TOP ==="
  [ -f "$xml" ] || { echo "[PKG] $TOP: FAIL — missing $xml"; rc=1; continue; }
  [ -f "$rtl" ] || { echo "[PKG] $TOP: FAIL — cannot locate RTL for $TOP (looked for module decl in RTL, then $rtl)"; rc=1; continue; }

  # 1) well-formed
  if ! xmllint --noout "$xml" 2>/tmp/_pkg_xmllint.$$; then
    echo "[PKG] $TOP: FAIL — malformed XML:"; cat /tmp/_pkg_xmllint.$$; rm -f /tmp/_pkg_xmllint.$$; rc=1; continue
  fi
  rm -f /tmp/_pkg_xmllint.$$

  # 2) structural — required top-level IP-XACT elements present
  miss=""
  for tag in "ipxact:vendor" "ipxact:library" "ipxact:name" "ipxact:version" "ipxact:busInterfaces" "ipxact:model"; do
    grep -q "<$tag>" "$xml" || miss="$miss $tag"
  done
  if [ -n "$miss" ]; then echo "[PKG] $TOP: FAIL — missing IP-XACT elements:$miss"; rc=1; continue; fi

  # 3) RTL-in-sync — model ports (XML) must equal RTL module ports
  xml_ports="$(grep -oE '<ipxact:port><ipxact:name>[A-Za-z0-9_]+' "$xml" | sed -E 's|.*<ipxact:name>||' | sort -u)"
  rtl_ports="$(awk -v top="$TOP" '
      $0 ~ "^[ \t]*module[ \t]+"top"[ \t]*[#(]" {m=1}
      m && /^[ \t]*(input|output|inout)[ \t]/ {
          s=$0; gsub(/\r/,"",s); sub(/\/\/.*/,"",s); sub(/,[ \t]*$/,"",s);
          n=split(s,a,/[ \t]/); name=a[n]; sub(/\[.*$/,"",name); sub(/[,\r]+$/,"",name);
          if (name ~ /^[A-Za-z_]/) print name
      }
      m && /^[ \t]*\);/ {exit}
  ' "$rtl" | sort -u)"

  if [ "$xml_ports" = "$rtl_ports" ]; then
    nports="$(printf '%s\n' "$xml_ports" | grep -c .)"
    echo "[PKG] $TOP: PASS — well-formed + structural + RTL-in-sync ($nports ports match $rtl)"
  else
    echo "[PKG] $TOP: FAIL — IP-XACT model ports differ from RTL ($rtl):"
    echo "  only in IP-XACT:"; comm -23 <(printf '%s\n' "$xml_ports") <(printf '%s\n' "$rtl_ports") | sed 's/^/    /'
    echo "  only in RTL:";     comm -13 <(printf '%s\n' "$xml_ports") <(printf '%s\n' "$rtl_ports") | sed 's/^/    /'
    rc=1
  fi
done

# optional: full XSD schema validation when a local schema is provided
if [ -n "${IPXACT_XSD:-}" ] && [ -f "${IPXACT_XSD}" ]; then
  echo "[PKG] XSD schema validation against $IPXACT_XSD"
  for TOP in $TOPS; do
    xmllint --noout --schema "$IPXACT_XSD" "$XML_DIR/$TOP.xml" || rc=1
  done
else
  echo "[PKG] XSD schema validation: not run (set IPXACT_XSD to the 1685-2014 index.xsd to enable) — this is 'not run', not a pass."
fi

[ $rc -eq 0 ] && echo "[PKG] T7 packaging gate PASSED (IP-XACT well-formed + structural + in sync with RTL)."
exit $rc

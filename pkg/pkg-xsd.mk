# T7 full XSD validation (kit templates/signoff/pkg/). Include from the repo Makefile,
# with scripts/fetch_ipxact_xsd.py and pkg/ip-xact/schema/ieee-1685-2014.sha256 adopted.
# Strict by default: an unavailable schema host FAILS. XSD_HOST_OPTIONAL=1 (PR CI only)
# reports "XSD NOT RUN" (a GitHub warning, never a pass) and exits 0; schema validation
# errors and pin mismatches always fail. Release workflows run it strict.
IPXACT_XSD_DIR ?= $(CURDIR)/.cache/ipxact-1685-2014
PKG_CHECK      ?= pkg/check_ipxact.sh
.PHONY: pkg-xsd
pkg-xsd:
	@python3 $(CURDIR)/scripts/fetch_ipxact_xsd.py $(IPXACT_XSD_DIR); rc=$$?; \
	if [ $$rc -eq 3 ] && [ "$(XSD_HOST_OPTIONAL)" = "1" ]; then \
		echo "::warning title=IP-XACT XSD NOT RUN::schema host unavailable; IP-XACT was NOT schema-validated in this run (not a pass). Releases still require it."; \
		echo "[PKG] XSD schema validation: NOT RUN (schema host unavailable) — this is 'not run', not a pass."; \
		exit 0; \
	elif [ $$rc -eq 1 ]; then \
		echo "[PKG] XSD schema validation: FAIL — schema integrity check (pinned SHA-256 mismatch)"; exit 1; \
	elif [ $$rc -ne 0 ]; then \
		echo "[PKG] XSD schema validation: FAIL — could not obtain the 1685-2014 schema (rc=$$rc)"; exit 1; \
	fi; \
	IPXACT_XSD=$(IPXACT_XSD_DIR)/index.xsd bash $(CURDIR)/$(PKG_CHECK)

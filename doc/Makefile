# Build design documentation from Markdown.
#
# From repo root:  make -C doc <target>
# From doc/:       make <target>
#
# PDF requires: pandoc + a LaTeX engine (e.g. texlive-full, or pandoc with pdflatex).
# HTML requires: pandoc only.

SPEC    := DESIGN_SPEC.md
OUTDIR  := build
PDF     := $(OUTDIR)/design_spec.pdf
HTML    := $(OUTDIR)/design_spec.html
PANDOC  := pandoc

PANDOC_META := --metadata title="AXI4 to DFI Bridge - Design Specification"

PANDOC_PDF_FLAGS := \
	$(PANDOC_META) \
	-V geometry:margin=1in \
	-V documentclass=article \
	--toc \
	-N \
	--pdf-engine=pdflatex

PANDOC_HTML_FLAGS := -s --toc -N $(PANDOC_META)

.PHONY: all pdf html clean help

all: pdf

help:
	@echo "Targets: pdf  html  clean  help"
	@echo "  pdf  - $(PDF)  (pandoc + pdflatex)"
	@echo "  html - $(HTML) (pandoc only)"
	@echo "  From test:  make -C ../doc pdf"

pdf: $(PDF)

$(PDF): $(SPEC)
	@command -v $(PANDOC) >/dev/null 2>&1 || \
		{ echo "error: pandoc not found (e.g. apt install pandoc texlive-latex-base)"; exit 1; }
	mkdir -p $(dir $@)
	$(PANDOC) $(SPEC) -o $(PDF) $(PANDOC_PDF_FLAGS)

html: $(HTML)

$(HTML): $(SPEC)
	@command -v $(PANDOC) >/dev/null 2>&1 || \
		{ echo "error: pandoc not found"; exit 1; }
	mkdir -p $(dir $@)
	$(PANDOC) $(SPEC) -o $(HTML) $(PANDOC_HTML_FLAGS)

clean:
	rm -rf $(OUTDIR)

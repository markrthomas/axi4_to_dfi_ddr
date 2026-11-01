# swarm.mk — shared swarm/infra targets, included by the root Makefile (`include swarm.mk`).
# [swarm-kit: shared file, do not fork per repo; repo specifics come from .claude/swarm.env]
# Defines: heavy board board-wait swarm swarm-rr swarm-dry swarm-profile swarm-kit-check batch
# The repo's own Makefile must NOT define these names.

SWARM_ENV := .claude/swarm.env

# heavy: run one resource-hungry target at a time, machine-wide (UVM/Verilator builds, formal, ci).
# `make heavy T=vlt`. The lock lives in the recipe because Claude Code's permission checker cannot
# match a bare `flock ...` command line, but does allow `make ...`.
HEAVY_LOCK ?= /tmp/$(notdir $(CURDIR))-heavy.lock
HEAVY_WAIT ?= 1800
.PHONY: heavy board board-wait swarm swarm-rr swarm-dry swarm-profile swarm-kit-check batch
heavy:
	@test -n "$(T)" || { echo "usage: make heavy T=<target>  (e.g. T=vlt)"; exit 2; }
	flock -w $(HEAVY_WAIT) $(HEAVY_LOCK) $(MAKE) $(T)

# swarm status board (tools/swarm/board.py; board files live in $RR_DIR/board): manager view of every worker branch
board:
	python3 tools/swarm/board.py show
board-wait:
	python3 tools/swarm/board.py wait

# run a swarm locally / in a Codespace (needs `claude` on PATH + CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY)
swarm:
	docker/swarm.sh --task docker/swarm-task.md $(if $(MODEL),--model $(MODEL))
swarm-rr:
	docker/swarm.sh --task docker/rr-swarm-task.md $(if $(MODEL),--model $(MODEL))
swarm-dry:
	docker/swarm.sh --dry-run
	docker/swarm.sh --dry-run --task docker/rr-swarm-task.md

# the Railway batch (what the container ENTRYPOINT runs), runnable in a Codespace / checkout too
batch:
	docker/entrypoint.sh ci

swarm-profile:
	@bash -c '. docker/profile.sh; for k in PROJECT GH_REPO DV_ENVS GATE_TARGET CI_TARGET CROSSCHECK_TARGET INFRA_TARGETS HEAVY_TARGETS RTL_DIR MUTATION_FILE RR_DIR RR_STATUS METRICS; do printf "%-18s %s\n" "$$k" "$${!k}"; done'

# drift check: kit version + the files the kit owns are present; profile names targets that exist
swarm-kit-check:
	@test -f $(SWARM_ENV) || { echo "swarm-kit-check: $(SWARM_ENV) missing"; exit 1; }
	@echo "swarm-kit $$(cat .claude/swarm-kit.version 2>/dev/null || echo '?')"
	@bash -c '. docker/profile.sh; rc=0; \
	  have=" $$($(MAKE) --no-print-directory -pRrq : 2>/dev/null | sed -n "s/^\([A-Za-z0-9_.-][A-Za-z0-9_.-]*\):.*/\1/p" | sort -u | tr "\n" " ") "; \
	  for t in $$GATE_TARGET $$CI_TARGET $$DV_ENVS $$INFRA_TARGETS $$CROSSCHECK_TARGET; do \
	    [[ "$$have" == *" $$t "* ]] || { echo "swarm-kit-check: profile names target \"$$t\" but the Makefile has no such target"; rc=1; }; done; \
	  if [ "$$RR_STATUS" = present ]; then for t in rr-build rr rr-triage rr-replay; do \
	    [[ "$$have" == *" $$t "* ]] || { echo "swarm-kit-check: RR_STATUS=present but no $$t target"; rc=1; }; done; fi; \
	  for f in Dockerfile .claude/agents/swarm-manager.md tools/swarm/board.py; do [ -f "$$f" ] || { echo "swarm-kit-check: $$f missing"; rc=1; }; done; \
	  [ $$rc = 0 ] && echo "swarm-kit-check: OK"; exit $$rc'

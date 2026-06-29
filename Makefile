# Makefile — one command per contributor task.
# Requires: shellcheck, bats, shfmt (brew install shellcheck bats-core shfmt).

# Files shellcheck lints directly (entry scripts; -x follows sourced libs).
SHELL_ENTRYPOINTS := bin/* stacks/*.sh vm/sandbox-egress install.sh tests/validate-screening.sh
# Files shfmt formats (all shell in the repo).
SHFMT_TARGETS := bin lib stacks install.sh tests/run-tests.sh tests/validate-screening.sh

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[1m%-18s\033[0m %s\n", $$1, $$2}'

.PHONY: lint
lint: shellcheck fmt-check ## Run all static checks (shellcheck + shfmt --diff)

.PHONY: shellcheck
shellcheck: ## ShellCheck the entry scripts (matches CI)
	shellcheck -x --severity=warning $(SHELL_ENTRYPOINTS)

.PHONY: fmt
fmt: ## Format all shell with shfmt (2-space, case-indent)
	shfmt -w -i 2 -ci $(SHFMT_TARGETS)

.PHONY: fmt-check
fmt-check: ## Check formatting without writing (CI-friendly)
	shfmt -d -i 2 -ci $(SHFMT_TARGETS)

.PHONY: smoke
smoke: ## Smoke the no-VM paths: every command's --help, schema + example, sandbox-init
	@set -e; for c in bin/sandbox bin/sandbox-*; do \
	  [ -f "$$c" ] || continue; "$$c" --help >/dev/null || { echo "FAIL: $$c --help"; exit 1; }; \
	done; echo "  all --help OK"
	@jq -e . sandbox.schema.json >/dev/null && jq -e . sandbox.config.example.json >/dev/null && echo "  schema + example valid JSON"
	@d=$$(mktemp -d); ( cd "$$d" && echo '{}' > package.json && "$(CURDIR)/bin/sandbox-init" >/dev/null ) \
	  && jq -e . "$$d/sandbox.config.json" >/dev/null && echo "  sandbox-init generates valid config"; rm -rf "$$d"

.PHONY: test-unit
test-unit: ## Run unit tests (bats; auto-fetches helpers)
	tests/run-tests.sh unit

.PHONY: test-integration
test-integration: ## Run integration tests (needs sandbox-setup / a real VM)
	tests/run-tests.sh integration

.PHONY: test
test: test-unit ## Alias for test-unit (the no-infra suite)

.PHONY: check
check: lint smoke test-unit ## Everything CI runs without a VM

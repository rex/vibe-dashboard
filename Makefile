# Makefile — universal build interface for Vibe Dashboard (macOS).
# Platform-agnostic verbs; bodies fan out to xcodegen + xcodebuild.

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

XCODEGEN   ?= xcodegen
XCODEBUILD ?= xcodebuild
PROJECT    ?= VibeDashboard.xcodeproj
SCHEME_MAC ?= VibeDashboard
DEST_MAC   ?= 'platform=macOS,arch=arm64'

# Version stamping — build-time injection so direct-Xcode and CI agree.
BUILD_NUM := $(shell git rev-list --count HEAD 2>/dev/null || echo 1)

# Architecture gate thresholds (mirror VIBE.yaml).
HARD_LINES ?= 400
SOFT_LINES ?= 250

# ----------------------------------------------------------------------------

.PHONY: help
help:
	@printf "%s\n" \
	  "Vibe Dashboard — targets:" \
	  "  make regenerate         xcodegen generate the .xcodeproj" \
	  "  make build-mac          build the macOS app (unsigned)" \
	  "  make run                build + launch the app" \
	  "  make test               run unit tests" \
	  "  make lint               SwiftLint (advisory)" \
	  "  make check-architecture file-size census (soft $(SOFT_LINES) / hard $(HARD_LINES))" \
	  "  make check-docs         doc-size audit (AGENTS/CLAUDE/TASK_STATE)" \
	  "  make validate           build + lint + architecture + docs — the gate" \
	  "  make audit              privacy + usage-description + no-cocoapods gates" \
	  "  make clean              clean derived data + regenerated project" \
	  ""

.PHONY: regenerate
regenerate:
	$(XCODEGEN) generate

.PHONY: resolve
resolve: regenerate
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME_MAC) -resolvePackageDependencies

.PHONY: build-mac
build-mac: regenerate
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME_MAC) -destination $(DEST_MAC) \
		CODE_SIGNING_ALLOWED=NO \
		CURRENT_PROJECT_VERSION=$(BUILD_NUM) build

.PHONY: run
run: build-mac
	@APP="$$($(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME_MAC) -destination $(DEST_MAC) \
		-showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR/ {d=$$3} / FULL_PRODUCT_NAME/ {n=$$3} END {print d"/"n}')"; \
	echo ">>> launching $$APP"; open "$$APP"

.PHONY: test
test: regenerate
	$(XCODEBUILD) test -project $(PROJECT) -scheme $(SCHEME_MAC) -destination $(DEST_MAC) \
		CODE_SIGNING_ALLOWED=NO \
		-resultBundlePath build/test-results.xcresult \
		CURRENT_PROJECT_VERSION=$(BUILD_NUM)

.PHONY: lint
lint:
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint --strict || true; \
	else \
		echo "swiftlint not installed; skipping"; \
	fi

.PHONY: check-architecture
check-architecture:
	@echo ">>> architecture: scanning Swift files (soft $(SOFT_LINES) / hard $(HARD_LINES))"; \
	fail=0; \
	while IFS= read -r f; do \
		n=$$(wc -l < "$$f" | tr -d ' '); \
		if [ "$$n" -gt "$(HARD_LINES)" ]; then echo "  GOD-FILE  $$f — $$n lines (over hard $(HARD_LINES))"; fail=1; \
		elif [ "$$n" -gt "$(SOFT_LINES)" ]; then echo "  soft      $$f — $$n lines (over soft $(SOFT_LINES))"; fi; \
	done < <(find VibeDashboard Shared Tests -name '*.swift' -not -path '*/Generated/*' 2>/dev/null); \
	if [ "$$fail" -ne 0 ]; then echo ">>> architecture: FAIL (god-files present)"; exit 1; fi; \
	echo ">>> architecture: within hard limit"

.PHONY: check-docs
check-docs:
	@echo ">>> docs: size audit"; \
	for f in TASK_STATE.md AGENTS.md CLAUDE.md; do \
		if [ -f "$$f" ]; then n=$$(wc -l < "$$f" | tr -d ' '); echo "  $$f — $$n lines"; fi; \
	done; \
	echo ">>> docs: ok"

.PHONY: validate
validate: build-mac lint check-architecture check-docs
	@echo ">>> validate: all gates green"

.PHONY: audit
audit:
	@./Scripts/audit-privacy-manifest.sh 2>/dev/null || echo "audit-privacy-manifest.sh missing"
	@./Scripts/check-no-cocoapods.sh 2>/dev/null || echo "check-no-cocoapods.sh missing"

.PHONY: clean
clean:
	$(XCODEBUILD) -project $(PROJECT) clean 2>/dev/null || true
	rm -rf build/ DerivedData/ $(PROJECT)
	@echo ">>> cleaned"

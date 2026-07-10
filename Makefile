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

# Marketing version — single source of truth is VERSION (MAJOR.(MINOR_BASE +
# commits-since-VERSION)). Computed by generate-build-info.sh and passed to
# every xcodebuild build so the shipped CFBundleShortVersionString equals the
# value BuildInfo.swift stamps — never the project.yml 0.1 placeholder.
MARKETING_VERSION := $(shell ./Scripts/generate-build-info.sh --print-marketing 2>/dev/null || echo 0.0)

# Reproducible SPM — the committed lockfile (Package.resolved) is restored into
# the regenerated workspace so xcodebuild pins exact dependency versions.
PKG_RESOLVED     := Package.resolved
PKG_RESOLVED_DST := $(PROJECT)/project.xcworkspace/xcshareddata/swiftpm/Package.resolved

# CLI SwiftPM state lives inside the repo (build/spm), ISOLATED from Xcode's —
# sharing ~/Library/Caches/org.swift.swiftpm lets a make build poison the GUI
# build ("Missing package product 'Sparkle'" / artifact "already exists").
SPM_CLONES := build/spm

# Architecture gate thresholds (mirror VIBE.yaml).
HARD_LINES ?= 400
SOFT_LINES ?= 250

# ----------------------------------------------------------------------------

.PHONY: help
help:
	@printf "%s\n" \
	  "Vibe Dashboard — targets:" \
	  "  make setup              install git hooks (one-time, per checkout)" \
	  "  make install-hooks      point git at .githooks (core.hooksPath)" \
	  "  make regenerate         xcodegen generate the .xcodeproj" \
	  "  make resolve            resolve + pin SPM deps (updates Package.resolved)" \
	  "  make build-mac          build the macOS app (unsigned)" \
	  "  make run                build + launch the app" \
	  "  make test               run unit tests" \
	  "  make lint               SwiftLint (advisory)" \
	  "  make check-architecture file-size census (soft $(SOFT_LINES) / hard $(HARD_LINES))" \
	  "  make check-docs         doc-size audit (AGENTS/CLAUDE/TASK_STATE)" \
	  "  make audit              privacy + usage-description + no-cocoapods gates" \
	  "  make validate           build + test + lint + architecture + docs + audit — the gate" \
	  "  make release-check      preflight the Developer ID + notary setup (no changes)" \
	  "  make dmg-local          build an UNSIGNED app + DMG into dist/ (testing only)" \
	  "  make notary-setup       store notary credentials once (ARGS=\"--apple-id … --team-id …\")" \
	  "  make release            archive → sign → notarize → stapled DMG (the shippable)" \
	  "  make clean              clean derived data + regenerated project" \
	  ""

.PHONY: setup
setup: install-hooks
	@echo ">>> setup complete — run 'make validate' to check the gate"

.PHONY: install-hooks
install-hooks:
	@git config core.hooksPath .githooks
	@echo ">>> git hooks installed (core.hooksPath=.githooks)"

.PHONY: regenerate
regenerate:
	$(XCODEGEN) generate
	@if [ -f "$(PKG_RESOLVED)" ]; then \
		mkdir -p "$(dir $(PKG_RESOLVED_DST))"; \
		cp "$(PKG_RESOLVED)" "$(PKG_RESOLVED_DST)"; \
		echo ">>> restored pinned $(PKG_RESOLVED) into workspace"; \
	fi

.PHONY: resolve
resolve: regenerate
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME_MAC) -resolvePackageDependencies \
		-clonedSourcePackagesDirPath $(SPM_CLONES)
	@if [ -f "$(PKG_RESOLVED_DST)" ]; then \
		cp "$(PKG_RESOLVED_DST)" "$(PKG_RESOLVED)"; \
		echo ">>> updated $(PKG_RESOLVED) from resolution — commit it to pin"; \
	fi

.PHONY: build-mac
build-mac: regenerate
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME_MAC) -destination $(DEST_MAC) \
		-clonedSourcePackagesDirPath $(SPM_CLONES) \
		CODE_SIGNING_ALLOWED=NO \
		CURRENT_PROJECT_VERSION=$(BUILD_NUM) \
		MARKETING_VERSION=$(MARKETING_VERSION) build

.PHONY: run
run: build-mac
	@APP="$$($(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME_MAC) -destination $(DEST_MAC) \
		-clonedSourcePackagesDirPath $(SPM_CLONES) \
		MARKETING_VERSION=$(MARKETING_VERSION) \
		-showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR/ {d=$$3} / FULL_PRODUCT_NAME/ {n=$$3} END {print d"/"n}')"; \
	echo ">>> launching $$APP"; open "$$APP"

.PHONY: test
test: regenerate
	rm -rf build/test-results.xcresult   # xcodebuild refuses to overwrite an existing result bundle
	$(XCODEBUILD) test -project $(PROJECT) -scheme $(SCHEME_MAC) -destination $(DEST_MAC) \
		-clonedSourcePackagesDirPath $(SPM_CLONES) \
		CODE_SIGNING_ALLOWED=NO \
		-resultBundlePath build/test-results.xcresult \
		CURRENT_PROJECT_VERSION=$(BUILD_NUM) \
		MARKETING_VERSION=$(MARKETING_VERSION)

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
validate: build-mac test lint check-architecture check-docs audit
	@echo ">>> validate: all gates green (build · test · lint · architecture · docs · audit)"

.PHONY: audit
audit:
	@echo ">>> audit: privacy manifest · usage descriptions · no-cocoapods"
	@for s in audit-privacy-manifest audit-usage-descriptions check-no-cocoapods; do \
		if [ -x "./Scripts/$$s.sh" ]; then \
			echo "--- $$s ---"; \
			"./Scripts/$$s.sh"; \
		else \
			echo "MISSING gate script: Scripts/$$s.sh" >&2; exit 1; \
		fi; \
	done
	@echo ">>> audit: all gates passed"

# ----------------------------------------------------------------------------
# Release — Developer ID signing + notarization + stapled DMG (direct
# distribution; NOT the Mac App Store). One-time setup in docs/RELEASE.md.
# ----------------------------------------------------------------------------

.PHONY: release-check
release-check:
	@./Scripts/release.sh check

.PHONY: dmg-local
dmg-local:
	@./Scripts/release.sh local

.PHONY: notary-setup
notary-setup:
	@./Scripts/notary-setup.sh $(ARGS)

.PHONY: release
release:
	@./Scripts/release.sh full

.PHONY: clean
clean:
	$(XCODEBUILD) -project $(PROJECT) clean 2>/dev/null || true
	rm -rf build/ DerivedData/ dist/ $(PROJECT)
	@echo ">>> cleaned"

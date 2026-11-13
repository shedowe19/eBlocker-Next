# Safe developer entry points. Nothing installs services or changes networking.
PYTHON ?= python3
MVN ?= mvn
GO ?= go
NPM ?= npm

.PHONY: help verify test test-java test-go test-ui build-native
.DEFAULT_GOAL := help
help:
	@printf '%s\n' 'verify: provenance and structural checks' 'test: Java, Go and UI suites (requires their toolchains)' 'test-java / test-go / test-ui: individual suites' 'build-native: compile network helpers, never install/run them'
verify:
	$(PYTHON) scripts/verify_workspace.py
	$(PYTHON) -m unittest discover -s tests -v
	$(PYTHON) scripts/check_credentials.py

test: test-java test-go test-ui

test-java:
	$(MVN) -B test $(MAVEN_ARGS)

test-go:
	cd services/coredns && $(GO) test ./...
	cd services/dyndns && $(GO) test ./...
	cd tools/environment-simulator && $(GO) test ./...

test-ui:
	cd apps/core/eblocker-ui && $(NPM) ci && $(NPM) test

build-native:
	$(MAKE) -C services/network-tools all

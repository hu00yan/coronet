PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin

.PHONY: all build test clean install coverage check

all: build

build:
	moon build --target native --release

test:
	moon test
	moon run cmd/coverage -- --strict

coverage:
	moon run cmd/coverage -- --strict

check:
	moon check
	./scripts/test_core_plugin.sh

install: build
	mkdir -p $(BINDIR)
	cp _build/native/release/build/cmd/main/main.exe $(BINDIR)/coronet
	@echo "Coronet installed successfully to $(BINDIR)/coronet"

clean:
	moon clean

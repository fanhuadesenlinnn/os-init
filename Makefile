.PHONY: build run lint test lib-strategy-test arch-test check clean

BINARY ?= os-init
VERSION ?= dev
COMMIT ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo none)

build:
	go build -trimpath -ldflags "-s -w -X main.version=$(VERSION) -X main.commit=$(COMMIT)" -o $(BINARY) .

run:
	go run .

lint:
	test -z "$$(gofmt -l $$(find . -name '*.go' -not -path './.git/*'))"
	bash -n modules/lib.sh modules/provider.sh modules/*/*.sh tooling/*.sh
	shellcheck modules/lib.sh modules/provider.sh modules/*/*.sh tooling/*.sh

test:
	go test ./...

lib-strategy-test:
	bash tooling/test-lib-strategy.sh

arch-test:
	bash modules/arch/scripts/test.sh
	shellcheck -x $$(find modules/arch -type f -name '*.sh' -print)

check: test lint lib-strategy-test arch-test

clean:
	rm -rf os-init kickstart dist

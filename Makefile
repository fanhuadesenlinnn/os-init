.PHONY: build run lint test lib-strategy-test mise-strategy-test release-strategy-test arch-test distro-contract-test check clean

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

mise-strategy-test:
	bash tooling/test-mise-strategy.sh

release-strategy-test:
	bash tooling/test-release-strategy.sh

arch-test:
	bash modules/arch/scripts/test.sh
	shellcheck -x $$(find modules/arch -type f -name '*.sh' -print)

distro-contract-test: build
	@if [ "$$(uname -s)" = Linux ]; then \
		family="$$(./$(BINARY) --system-info | sed -n 's/^family=//p')"; \
		bash tooling/test-distro-contract.sh "$$family" "./$(BINARY)"; \
	else \
		echo "Skipping distro contract: Linux required"; \
	fi

check: test lint lib-strategy-test mise-strategy-test release-strategy-test arch-test

clean:
	rm -rf os-init kickstart dist

.PHONY: build run lint test check clean

BINARY ?= os-init
VERSION ?= dev
COMMIT ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo none)

build:
	go build -trimpath -ldflags "-s -w -X main.version=$(VERSION) -X main.commit=$(COMMIT)" -o $(BINARY) .

run:
	go run .

lint:
	test -z "$$(gofmt -l $$(find . -name '*.go' -not -path './.git/*'))"
	bash -n modules/lib.sh modules/*/*.sh
	shellcheck modules/lib.sh modules/*/*.sh

test:
	go test ./...

check: test lint

clean:
	rm -rf os-init kickstart dist

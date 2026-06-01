.PHONY: build run lint test clean

BINARY ?= os-init
VERSION ?= dev
COMMIT ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo none)

build:
	go build -trimpath -ldflags "-s -w -X main.version=$(VERSION) -X main.commit=$(COMMIT)" -o $(BINARY) .

run:
	go run .

lint:
	golangci-lint run ./...

test:
	go test ./...

clean:
	rm -rf os-init kickstart dist

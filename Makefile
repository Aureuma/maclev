.PHONY: build app test

build:
	./scripts/build-guard.sh swift build --jobs 2

app:
	./scripts/build-guard.sh ./build_app.sh

test:
	./scripts/build-guard.sh swift test --jobs 2

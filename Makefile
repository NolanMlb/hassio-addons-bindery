IMAGE ?= bindery-ha:test
APP   := bindery

.PHONY: help build build-multiarch run test test-no-build lint icons clean

help:
	@echo "make build           build $(IMAGE)"
	@echo "make build-multiarch build for linux/amd64 and linux/arm64"
	@echo "make test            build, then run the smoke tests"
	@echo "make lint            shellcheck + hadolint + yamllint"
	@echo "make icons           regenerate icon.png and logo.png"

build:
	docker build -t $(IMAGE) $(APP)

build-multiarch:
	docker buildx build --platform linux/amd64,linux/arm64 $(APP)

test:
	./tests/smoke-test.sh

test-no-build:
	./tests/smoke-test.sh --no-build

lint:
	docker run --rm -v "$(CURDIR):/mnt" koalaman/shellcheck:stable -S warning \
		/mnt/$(APP)/rootfs/usr/lib/bindery/common.sh \
		/mnt/$(APP)/rootfs/etc/cont-init.d/00-bindery.sh \
		/mnt/$(APP)/rootfs/etc/services.d/bindery/run \
		/mnt/$(APP)/rootfs/etc/services.d/bindery/finish \
		/mnt/tests/smoke-test.sh
	docker run --rm -v "$(CURDIR):/mnt" hadolint/hadolint:latest hadolint /mnt/$(APP)/Dockerfile
	docker run --rm -v "$(CURDIR):/mnt" cytopia/yamllint:latest -c /mnt/.yamllint \
		/mnt/$(APP) /mnt/repository.yaml /mnt/.github/workflows /mnt/examples

icons:
	python3 assets/generate-icons.py

clean:
	docker rmi -f $(IMAGE) 2>/dev/null || true

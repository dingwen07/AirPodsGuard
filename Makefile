.PHONY: run

MACOSX_DEPLOYMENT_TARGET := 11.0

all: AirPodsGuard

AirPodsGuard: AirPodsGuard-arm64 AirPodsGuard-x86_64
	lipo -create -output AirPodsGuard AirPodsGuard-x86_64 AirPodsGuard-arm64
	lipo -info AirPodsGuard

AirPodsGuard-arm64: AirPodsGuard.swift
	swiftc -target arm64-apple-macosx$(MACOSX_DEPLOYMENT_TARGET) AirPodsGuard.swift -o AirPodsGuard-arm64

AirPodsGuard-x86_64: AirPodsGuard.swift
	swiftc -target x86_64-apple-macosx$(MACOSX_DEPLOYMENT_TARGET) AirPodsGuard.swift -o AirPodsGuard-x86_64

run: AirPodsGuard
	./AirPodsGuard --callback 'osascript -e "say \"Attention! Attention! Your %{part} AirPod of %{name} is not charging!\""' $(ARGS)

clean:
	rm -f AirPodsGuard AirPodsGuard-x86_64 AirPodsGuard-arm64 AirPodsGuard.zip

ARGS = $(filter-out run,$(MAKECMDGOALS))

%:
	@:

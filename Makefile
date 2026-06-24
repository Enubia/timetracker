PROJECT := TimeTracker.xcodeproj
SCHEME := TimeTracker
DESTINATION := platform=macOS
RELEASE_APP := build/Build/Products/Release/TimeTracker.app

.PHONY: all build test release install clean generate

all: build

$(PROJECT): project.yml
	xcodegen generate

generate: $(PROJECT)

build: $(PROJECT)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' build CODE_SIGNING_ALLOWED=NO

test: $(PROJECT)
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -only-testing:TimeTrackerTests CODE_SIGNING_ALLOWED=NO

release: $(PROJECT)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -derivedDataPath build CODE_SIGN_IDENTITY=- build

install: release
	cp -R $(RELEASE_APP) /Applications/

clean:
	rm -rf build
	rm -rf $(PROJECT)

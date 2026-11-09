.PHONY: test interface universal apple-silicon

test:
	swift test --parallel

interface:
	swift run AlphaSyncUIChecks build/interface-checks

universal:
	xcodebuild -project AlphaSync/AlphaSync.xcodeproj -scheme AlphaSyncUniversal -configuration Release -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData build

apple-silicon:
	xcodebuild -project AlphaSync/AlphaSync.xcodeproj -scheme AlphaSyncAppleSilicon -configuration Release -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData build

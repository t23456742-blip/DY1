# DouYinCleaner Makefile
# macOS 本地构建 + GitHub Actions 自动构建

.PHONY: project archive ipa clean

# 前置: brew install xcodegen
project:
	xcodegen generate

# 本地 Archive
archive: project
	xcodebuild archive \
		-project DouYinCleaner.xcodeproj \
		-scheme DouYinCleaner \
		-archivePath build/DouYinCleaner.xcarchive \
		-destination "generic/platform=iOS" \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO

# 打包 IPA
ipa: archive
	mkdir -p Payload
	cp -r build/DouYinCleaner.xcarchive/Products/Applications/DouYinCleaner.app Payload/
	zip -qr DouYinCleaner.tipa Payload
	rm -rf Payload
	@echo "✅ 生成: DouYinCleaner.tipa"
	@ls -lh DouYinCleaner.tipa

# 清理
clean:
	rm -rf DouYinCleaner.xcodeproj build Payload

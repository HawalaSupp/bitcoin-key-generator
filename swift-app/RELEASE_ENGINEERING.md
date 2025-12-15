# Hawala Release Engineering Guide

## Overview

This document covers the release engineering requirements for Hawala v1:
- Code signing and notarization
- Auto-update implementation
- Distribution strategy

## 1. Code Signing & Notarization

### Prerequisites

1. **Apple Developer Account** (Individual or Organization)
2. **Developer ID Application Certificate** for distribution outside App Store
3. **Developer ID Installer Certificate** (if distributing .pkg)

### Certificate Setup

```bash
# List available signing identities
security find-identity -v -p codesigning

# Export certificate for CI (if needed)
# Do this from Keychain Access
```

### Signing the App

```bash
# Sign the app bundle
codesign --deep --force --verify --verbose \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  --options runtime \
  --timestamp \
  Hawala.app

# Verify signing
codesign --verify --deep --strict --verbose=2 Hawala.app
```

### Notarization

```bash
# Create a ZIP for notarization
ditto -c -k --keepParent Hawala.app Hawala.zip

# Submit for notarization
xcrun notarytool submit Hawala.zip \
  --apple-id "your@email.com" \
  --password "app-specific-password" \
  --team-id "TEAMID" \
  --wait

# Staple the ticket (after approval)
xcrun stapler staple Hawala.app
```

### Automating with Xcode

If using Xcode for archive:
1. Product → Archive
2. Distribute App → Developer ID → Direct Distribution
3. Xcode handles signing and notarization automatically

### CI/CD Integration

For GitHub Actions:

```yaml
# .github/workflows/release.yml
name: Release Build

on:
  release:
    types: [created]

jobs:
  build:
    runs-on: macos-14
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Import Certificate
      env:
        CERTIFICATE_P12: ${{ secrets.CERTIFICATE_P12 }}
        CERTIFICATE_PASSWORD: ${{ secrets.CERTIFICATE_PASSWORD }}
      run: |
        echo $CERTIFICATE_P12 | base64 --decode > certificate.p12
        security create-keychain -p "$CERTIFICATE_PASSWORD" build.keychain
        security import certificate.p12 -k build.keychain -P "$CERTIFICATE_PASSWORD"
        security list-keychains -s build.keychain
        security default-keychain -s build.keychain
        security unlock-keychain -p "$CERTIFICATE_PASSWORD" build.keychain
    
    - name: Build
      run: |
        swift build -c release
        
    - name: Sign & Notarize
      env:
        APPLE_ID: ${{ secrets.APPLE_ID }}
        APPLE_APP_PASSWORD: ${{ secrets.APPLE_APP_PASSWORD }}
        TEAM_ID: ${{ secrets.TEAM_ID }}
      run: |
        # Sign
        codesign --deep --force --verify --verbose \
          --sign "Developer ID Application" \
          --options runtime \
          --timestamp \
          .build/release/Hawala.app
        
        # Notarize
        ditto -c -k --keepParent .build/release/Hawala.app Hawala.zip
        xcrun notarytool submit Hawala.zip \
          --apple-id "$APPLE_ID" \
          --password "$APPLE_APP_PASSWORD" \
          --team-id "$TEAM_ID" \
          --wait
        
        xcrun stapler staple .build/release/Hawala.app
```

## 2. Auto-Update (Sparkle)

### Why Sparkle?

Sparkle is the industry-standard update framework for macOS apps distributed outside the App Store:
- Secure (Ed25519 signatures)
- Delta updates
- Background downloads
- Staged rollouts
- User-configurable update checks

### Integration

Add Sparkle to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.5.0"),
],
targets: [
    .target(
        name: "HawalaApp",
        dependencies: [
            .product(name: "Sparkle", package: "Sparkle"),
        ]
    ),
]
```

### Key Generation

Generate Ed25519 signing keys:

```bash
# Generate private key (keep this VERY safe!)
./Sparkle.framework/Resources/generate_keys

# Output:
# Private key saved to ~/Library/Sparkle/
# Public key: base64-encoded-public-key
```

### App Integration

```swift
import Sparkle

// In your App struct or AppDelegate
@main
struct HawalaApp: App {
    private let updaterController: SPUStandardUpdaterController
    
    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }
}

// Check for Updates menu item
struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    let updater: SPUUpdater
    
    init(updater: SPUUpdater) {
        self.updater = updater
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }
    
    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}
```

### Info.plist Configuration

Add to your Info.plist:

```xml
<key>SUFeedURL</key>
<string>https://updates.hawala.app/appcast.xml</string>

<key>SUPublicEDKey</key>
<string>YOUR_BASE64_PUBLIC_KEY</string>

<key>SUEnableAutomaticChecks</key>
<true/>
```

### Appcast.xml

Host on your update server (https://updates.hawala.app/appcast.xml):

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Hawala Updates</title>
        <link>https://hawala.app</link>
        <description>Most recent changes with links to updates.</description>
        <language>en</language>
        
        <item>
            <title>Version 1.0.1</title>
            <pubDate>Mon, 15 Dec 2025 12:00:00 +0000</pubDate>
            <sparkle:version>1.0.1</sparkle:version>
            <sparkle:shortVersionString>1.0.1</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
            <description>
                <![CDATA[
                    <h2>What's New</h2>
                    <ul>
                        <li>Bug fixes and performance improvements</li>
                    </ul>
                ]]>
            </description>
            <enclosure 
                url="https://updates.hawala.app/Hawala-1.0.1.zip"
                sparkle:edSignature="BASE64_ED25519_SIGNATURE"
                length="12345678"
                type="application/octet-stream"/>
        </item>
    </channel>
</rss>
```

### Signing Updates

Sign update archives:

```bash
# Sign the update
./Sparkle.framework/Resources/sign_update Hawala.zip

# Output: edSignature="..." length="..."
# Use these values in appcast.xml
```

## 3. Rollback & Kill Switch

### Rollback Strategy

1. Keep last 3 versions hosted on update server
2. If critical bug found, update appcast.xml to point to previous version
3. Users will auto-downgrade on next check

### Kill Switch

For compromised builds, immediately:

1. Remove compromised version from update server
2. Update appcast.xml with emergency patch or previous safe version
3. Optionally add `<sparkle:criticalUpdate/>` tag to force immediate update

```xml
<item>
    <title>Security Update 1.0.2</title>
    <sparkle:version>1.0.2</sparkle:version>
    <sparkle:criticalUpdate/>
    <!-- ... -->
</item>
```

## 4. Distribution Checklist

### Pre-Release

- [ ] Version number bumped in Info.plist
- [ ] Changelog prepared
- [ ] App signed with Developer ID
- [ ] App notarized and stapled
- [ ] Update archive created and signed
- [ ] Appcast.xml updated
- [ ] SHA256 hash of download published

### Post-Release

- [ ] Download tested from update server
- [ ] Auto-update tested from previous version
- [ ] GitHub release created with changelog
- [ ] Website updated

## 5. Security Considerations

### Update Security

1. **HTTPS only** - All update feeds must be HTTPS
2. **Ed25519 signatures** - Verify every update with EdDSA
3. **No downgrades** - By default, prevent downgrade attacks
4. **Code signing** - Updates must match Developer ID

### Key Management

1. **Private key**: Store offline (hardware security module or air-gapped)
2. **CI/CD**: Use environment secrets, never commit keys
3. **Rotation**: Plan for key rotation if compromised

## 6. Future Enhancements

- **Delta updates**: Ship only changed files (Sparkle supports this)
- **Staged rollouts**: Release to % of users first
- **Release channels**: Beta, Stable, etc.
- **In-app update UI**: Custom update experience

---

## Quick Reference

```bash
# Build release
swift build -c release

# Sign
codesign --deep --force --verify --sign "Developer ID Application" --options runtime --timestamp Hawala.app

# Notarize
ditto -c -k --keepParent Hawala.app Hawala.zip
xcrun notarytool submit Hawala.zip --apple-id "email" --password "pwd" --team-id "TEAM" --wait
xcrun stapler staple Hawala.app

# Sign update for Sparkle
./Sparkle.framework/Resources/sign_update Hawala.zip
```

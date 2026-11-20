# Sticky TV for iPhone

The Fire TV app's features and flow, made for touch.

- `StickyKit/`: everything that isn't a screen (provider, lists, titles). `cd StickyKit && swift test`
- `StickyTV/`: the SwiftUI app
- `project.yml`: the Xcode project, made with XcodeGen (`xcodegen generate`)

## Getting the IPA

Every push to `main` builds an unsigned `StickyTV.ipa` on GitHub's Macs (Actions › Build IPA › Artifacts).

## Installing it on your iPhone

1. Install **Sideloadly** (sideloadly.io) on a Windows PC or Mac.
2. Plug the iPhone in with a cable, open Sideloadly, drop `StickyTV.ipa` in, type your Apple ID, press **Start**.
3. On the iPhone: Settings › General › VPN & Device Management › your Apple ID › **Trust**.
4. With a free Apple ID the app must be re-signed every 7 days (do step 2 again, or use AltStore to do it automatically).

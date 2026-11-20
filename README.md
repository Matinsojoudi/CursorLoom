# CursorLoom

**Early development preview — not a functional Synergy replacement.** CursorLoom is a work-in-progress local-network software KVM for macOS and Windows. Both platform implementations are incomplete; Windows builds in CI but has not been functionally tested. The [v0.2.0-alpha.1 preview](https://github.com/Matinsojoudi/CursorLoom/releases/tag/v0.2.0-alpha.1) contains an unsigned macOS arm64 command-line executable (Apple Silicon only, not a .app) and a Windows x64 build requiring .NET 8 Desktop Runtime. Do not use for real remote control or sensitive input. Internal code names currently still use `InputBridge`.

## Plan
1. Define versioned interoperable messages and unit tests.
2. Build native macOS Swift app and Windows .NET app with explicit input permissions.
3. Add mutually authenticated encrypted transport, pairing, connection and disconnect safety.
4. Add input capture/injection, multi-monitor edge navigation, text clipboard, and configurable shortcuts.
5. Test across actual macOS and Windows devices; package installers.

Security: the experimental sender and receiver on both platforms require local PKCS#12 identities, explicit user consent and manually pinned peer certificates. Cross-device operation has not been tested. Each side verifies only the exact pinned certificate, not hostname, expiry, revocation or CA validity; compare pins through a trusted separate channel. No automatic pairing or certificate management exists. Local keystrokes are mirrored to the selected receiver while capture is active. Never enter passwords or sensitive information during a test. Do not expose the listener to the Internet or untrusted networks. No production security or compatibility claims.

## Protocol draft
Transport will use TLS 1.3 with certificate pinning after explicit pairing. Application messages are UTF-8 JSON, one message per line, max 64 KiB, carrying `version`, `type`, and `payload`. Handshake and pairing details remain to be designed and tested. This format alone does not provide authentication or encryption.

Initial event types: `hello`, `pointer`, `button`, `key`, `scroll`, `clipboard`, `releaseAll`. Input keys use USB HID keyboard-page usage IDs, not platform-specific key codes. Validated input payloads: `key` = `{usage: integer 0..255, down: boolean}`; `pointer` = `{x: 0..1, y: 0..1}` in normalized primary-display coordinates; `button` = `{index: 0..1, down: boolean}` (left/right); `scroll` = `{vertical: integer -100..100, horizontal: integer -100..100}` in line units; `clipboard` = `{text: string}`, max 48,000 UTF-8 bytes; `releaseAll` = `{}`. Unknown fields are rejected. Binary content and file transfer are future work. These semantics are preliminary and have not undergone interoperability tests.

For the unexecuted cross-platform test matrix and safety checks, see [INTEROPERABILITY.md](INTEROPERABILITY.md). For the multi-device design and remaining work, see [MULTI_DEVICE_PLAN.md](MULTI_DEVICE_PLAN.md).

## Development status
The current main branch has experimental sender and receiver UIs on both macOS and Windows. Each one-to-one session requires manual identity and pin configuration and explicit consent. Each sender can optionally send text clipboard changes; each receiver separately opts in. Cross-device behavior, keyboard mappings, modifier keys and clipboard have not been tested on real devices. Input capture is passive: activity is mirrored locally as well as sent remotely. Concurrent multi-device sessions, integrated screen-edge switching, automatic pairing, multi-monitor handling and installers are not implemented. A grid and routing state model exists but is not connected to the UI or network. GitHub Actions builds Windows and runs Swift tests; loopback TLS tests check certificate pin acceptance/rejection separately on each OS, and shared fixtures exercise protocol parsing. These checks do not establish a real connection between computers. The published v0.2 alpha predates the newer sender/receiver UI and does not contain it.

Run macOS tests: `cd macos && swift test`. Run the development window: `cd macos && swift run InputBridgeApp`. This is not a packaged app; macOS permission behavior may vary when launched from a terminal.
Windows preview requires Windows and .NET 8 SDK: `dotnet run --project windows-app/InputBridge.Windows.csproj` from the project root. A successful build does not establish functional correctness.

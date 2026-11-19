# CursorLoom

**Early development preview — not a functional Synergy replacement.** CursorLoom is a work-in-progress local-network software KVM for macOS and Windows. Both platform implementations are incomplete; Windows builds in CI but has not been functionally tested. Do not use for real remote control or sensitive input. Internal code names currently still use `InputBridge`.

## Plan
1. Define versioned interoperable messages and unit tests.
2. Build native macOS Swift app and Windows .NET app with explicit input permissions.
3. Add mutually authenticated encrypted transport, pairing, connection and disconnect safety.
4. Add input capture/injection, multi-monitor edge navigation, text clipboard, and configurable shortcuts.
5. Test across actual macOS and Windows devices; package installers.

Security: the experimental macOS sender and Windows receiver require local PKCS#12 identities, explicit user consent and manually pinned peer certificates. They have not been tested together. Each side verifies only the exact pinned certificate, not hostname, expiry, revocation or CA validity; compare pins through a trusted separate channel. No automatic pairing or certificate management exists. Local keystrokes are mirrored to Windows while capture is active. Never enter passwords or sensitive information during a test. Do not expose the listener to the Internet or untrusted networks. No production security or compatibility claims.

## Protocol draft
Transport will use TLS 1.3 with certificate pinning after explicit pairing. Application messages are UTF-8 JSON, one message per line, max 64 KiB, carrying `version`, `type`, and `payload`. Handshake and pairing details remain to be designed and tested. This format alone does not provide authentication or encryption.

Initial event types: `hello`, `pointer`, `button`, `key`, `scroll`, `clipboard`, `releaseAll`. Input keys use USB HID keyboard-page usage IDs, not platform-specific key codes. Validated input payloads: `key` = `{usage: integer 0..255, down: boolean}`; `pointer` = `{x: 0..1, y: 0..1}` in normalized primary-display coordinates; `button` = `{index: 0..1, down: boolean}` (left/right); `scroll` = `{vertical: integer -100..100, horizontal: integer -100..100}` in line units; `clipboard` = `{text: string}`, max 48,000 UTF-8 bytes; `releaseAll` = `{}`. Unknown fields are rejected. Binary content and file transfer are future work. These semantics are preliminary and have not undergone interoperability tests.

## Development status
macOS has an experimental sender UI; Windows has an experimental receiver UI. Both require manually provided identities and pins. They have not been exercised together or assessed for security; this is a one-way test implementation only. Mac input capture is passive and mirrors activity locally. Experimental one-way macOS-to-Windows text clipboard forwarding requires independent opt-in at both ends and has not been tested end-to-end. Reverse clipboard synchronization, screen-edge switching, Windows-to-Mac operation, multi-monitor handling, packaging and installers are not implemented. Separate input and clipboard primitives are not integrated. Some keyboard mappings and modifier behavior need real-device testing. GitHub Actions builds Windows and runs Swift tests, but does not establish a real session.

Run macOS tests: `cd macos && swift test`. Run the development window: `cd macos && swift run InputBridgeApp`. This is not a packaged app; macOS permission behavior may vary when launched from a terminal.
Windows preview requires Windows and .NET 8 SDK: `dotnet run --project windows-app/InputBridge.Windows.csproj` from the project root. A successful build does not establish functional correctness.

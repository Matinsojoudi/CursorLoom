# Cross-platform interoperability checklist

**Not executed.** Use only disposable accounts, non-sensitive input and an isolated trusted network. Input remains active on both source and target. Do not use passwords while sharing. Make sure a separate physical input device remains available. Never expose the listener to the Internet.

## Setup

- Install matching experimental builds from the same commit on all test devices. Current alpha installers are unsigned, macOS package is not notarized, and may be blocked by operating-system security checks.
- Provision a distinct PKCS#12 identity for each device using trusted certificate tooling. The sender certificate needs client authentication and the receiver certificate server authentication. Keep private keys and passwords private.
- Verify each exact leaf certificate SHA-256 fingerprint through a separate trusted channel. Each endpoint requires its peer's pin and explicit session consent. Pinning intentionally bypasses hostname, CA, expiration and revocation checks.
- On macOS, grant Accessibility for injecting input and Input Monitoring for capture. Set test network firewall rules narrowly; remove temporary rules after testing.

## Required matrix

| Sender | Receiver | Status |
|---|---|---|
| macOS | Windows | Not tested |
| Windows | macOS | Not tested |
| Windows | Windows | Not tested |
| macOS | macOS | Not tested |
| One sender, 2+ receivers | Mixed OS | Not implemented |

## For each one-to-one pairing

1. Start the receiver with its identity and the sender's verified pin; approve remote input. Enable clipboard only if testing it.
2. Start the sender with its identity and the receiver's verified pin. Give explicit input consent and start sharing.
3. Check primary-screen movement, left/right click, dragging, common key positions, modifiers (including left/right Shift and Ctrl), scrolling and non-sensitive text. Confirm input continues locally; no automatic screen-edge switching exists.
4. If clipboard is allowed at both ends, copy short multilingual text on the sender and verify receiver clipboard; verify that disabling either side prevents transfer (rejection may disconnect). Clear test clipboard after use.
5. Reject invalid pins in each direction, missing permissions, a second controller and a stalled handshake. Verify no unauthorized input is applied.
6. Hold a key/button, then stop sender, stop receiver, close app, and interrupt network in separate trials. Verify receiver releases all injected inputs. Record any failure immediately; do not assume API call success proves OS delivery.
7. Test sleep/wake, firewall interruption and reconnect; verify capture requires new consent.

Record commit, installer hash, versions, test date, configuration and observed outcome for every matrix cell. CI loopback tests do not establish cross-device functionality. Multi-device switching, reverse direction on an existing connection, seamless pointer transition, and clipboard broadcast are not available.

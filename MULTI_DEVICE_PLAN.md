# Multi-device architecture (work in progress)

Goal: every combination macOS→macOS, macOS→Windows, Windows→macOS and Windows→Windows, plus multiple concurrently connected receivers. Current alpha has experimental sender and receiver interfaces on both OSes, but no real-device interoperability validation. Multi-device and seamless switching are not implemented.

## Roles and topology
A session has one explicitly selected controller (the machine owning the physical keyboard and mouse) and up to four paired receivers in the initial milestone. Any supported OS can assume either role. Connections are direct authenticated TLS; there is no cloud relay. One active destination receives keyboard/mouse events at a time, not a broadcast. Clipboard sharing is opt-in for each peer and disabled by default. A receiver accepts input from at most one authorized controller at a time. Manual topology and address configuration precede discovery and drag-and-drop layout.

## Session safety
Each device has its own identity and explicit per-peer pinned certificate; never reuse a shared peer pin for all receivers. TLS authentication does not grant consent: receiver must explicitly allow a specific controller. Controller must explicitly enable capture. Switching destinations must release all pressed keys/buttons at the previous peer and stop forwarding there before activating a new peer; ambiguous delivery, disconnection or failed release closes that session and immediately restores local input. Emergency stop must remain available locally. Receiver releases held inputs on EOF, timeout or application exit. No automatic reconnection with renewed capture consent. Limit frames and queues, apply deadlines and reject malformed messages. Clipboard must avoid echo loops and never be sent to peers without consent.

## Status and next implementation steps

- Single-target sender and receiver UIs exist for both operating systems, with explicit consent and pinned TLS; only loopback protocol/TLS tests have run, not cross-device or real input tests.
- Device layout, routing, release request/acknowledgement, capability messages and switch coordinators are isolated models. They are **not** connected to active network sessions or the interface.
- The existing wire protocol is unidirectional: do not send draft capability or acknowledgement messages to current peers. Design a backward-compatible versioned handshake before enabling these messages; a received acknowledgement must be tied to the authenticated peer, request ID and deadline.
- Implement a bounded multi-peer connection owner and failure cleanup; switching must block new forwarding, release the old peer, await correlated acknowledgement, and activate the next peer only on success. On timeout or disconnect, close the previous session and restore local control.
- Clipboard loop prevention must use session/peer identities and explicit grants; do not broadcast clipboard content by default.
- Local input suppression, cursor movement across displays and emergency stop remain unimplemented. Do not claim seamless switching until physical-device tests pass.

## Sequence
1. Implement Windows TLS sender using existing bounded protocol and Windows capture, with consent and fail-closed cleanup; add Windows-to-Windows integration tests.
2. Implement macOS authenticated TLS listener and receiver using existing MacInputSink, per-peer certificate pins and explicit consent; add Windows-to-macOS interoperability tests.
3. Add device registry, per-peer lifecycle and single-active-target routing, then screen layout and switching. Disconnect and stuck-input tests precede enabling suppression of local input.
4. Integrate opt-in clipboard in both directions with loop prevention, plus Windows/macOS sender and receiver UI.
5. Exercise all four OS combinations and three or more physical devices, including network loss, wrong pins, stuck modifiers, high-DPI and sleep/wake. Build signed/installable releases only after validation.

## Boundaries
Initial target four receivers is an engineering milestone, not a claim of measured capacity. No promise of Linux, file transfer, sound, secure desktop/UAC, multiple simultaneous controllers or Internet operation. Direct peer connectivity requires permitted LAN routing; automatic discovery and pairing are future work. Current alpha binaries remain unsafe for sensitive input and must not be presented as complete.

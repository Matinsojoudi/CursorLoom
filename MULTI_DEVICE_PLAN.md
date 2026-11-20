# Multi-device architecture (work in progress)

Goal: every combination macOS→macOS, macOS→Windows, Windows→macOS and Windows→Windows, plus multiple concurrently connected receivers. Current alpha supports only experimental macOS→Windows; none of the following is complete.

## Roles and topology
A session has one explicitly selected controller (the machine owning the physical keyboard and mouse) and up to four paired receivers in the initial milestone. Any supported OS can assume either role. Connections are direct authenticated TLS; there is no cloud relay. One active destination receives keyboard/mouse events at a time, not a broadcast. Clipboard sharing is opt-in for each peer and disabled by default. A receiver accepts input from at most one authorized controller at a time. Manual topology and address configuration precede discovery and drag-and-drop layout.

## Session safety
Each device has its own identity and explicit per-peer pinned certificate; never reuse a shared peer pin for all receivers. TLS authentication does not grant consent: receiver must explicitly allow a specific controller. Controller must explicitly enable capture. Switching destinations must release all pressed keys/buttons at the previous peer and stop forwarding there before activating a new peer; ambiguous delivery, disconnection or failed release closes that session and immediately restores local input. Emergency stop must remain available locally. Receiver releases held inputs on EOF, timeout or application exit. No automatic reconnection with renewed capture consent. Limit frames and queues, apply deadlines and reject malformed messages. Clipboard must avoid echo loops and never be sent to peers without consent.

## Sequence
1. Implement Windows TLS sender using existing bounded protocol and Windows capture, with consent and fail-closed cleanup; add Windows-to-Windows integration tests.
2. Implement macOS authenticated TLS listener and receiver using existing MacInputSink, per-peer certificate pins and explicit consent; add Windows-to-macOS interoperability tests.
3. Add device registry, per-peer lifecycle and single-active-target routing, then screen layout and switching. Disconnect and stuck-input tests precede enabling suppression of local input.
4. Integrate opt-in clipboard in both directions with loop prevention, plus Windows/macOS sender and receiver UI.
5. Exercise all four OS combinations and three or more physical devices, including network loss, wrong pins, stuck modifiers, high-DPI and sleep/wake. Build signed/installable releases only after validation.

## Boundaries
Initial target four receivers is an engineering milestone, not a claim of measured capacity. No promise of Linux, file transfer, sound, secure desktop/UAC, multiple simultaneous controllers or Internet operation. Direct peer connectivity requires permitted LAN routing; automatic discovery and pairing are future work. Current alpha binaries remain unsafe for sensitive input and must not be presented as complete.

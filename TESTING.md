# Manual interoperability test plan (not yet run)

This is an experimental macOS-sender-to-Windows-receiver test, not production guidance. The current main branch also has experimental Windows sender and macOS receiver UIs; other combinations are not covered by this checklist and have not been validated. Use dedicated test accounts and an isolated trusted network. Do not type passwords or sensitive text while capture is active: the sender mirrors all supported keyboard input to the peer and also leaves it active locally. Never expose the listener to the Internet. Each peer pin must be independently verified out-of-band. Stop immediately if input sticks; sign out or use a separate physical input device if required.

## Preparation

- macOS 13+ with Swift toolchain, Accessibility and Input Monitoring permissions; Windows with .NET 8 SDK.
- Separate protected PKCS#12 client and server certificates with private keys and TLS client/server authentication usages. Obtain them using your organization's certificate tooling. Never commit identities or passwords.
- Compute SHA-256 fingerprint of each DER leaf certificate using a trusted tool on its originating device, compare through a separate trusted channel. Each peer must pin the other's exact certificate. Pin validation does not check certificate expiration, hostname, CA chain or revocation.
- Ensure the Windows port is reachable only within the isolated network. Launch with `dotnet run --project windows-app/InputBridge.Windows.csproj`; macOS: `cd macos && swift run InputBridgeApp`.

## Checks

1. On Windows choose server identity and enter the macOS leaf fingerprint; explicitly consent and start receiver.
2. On macOS choose client identity and enter the Windows leaf fingerprint and address. Connect, then explicitly start input capture.
3. Test primary-display movement, left/right click, common key positions and scroll. Confirm local input is also active. Do not test secrets. Current implementation has no screen-edge switching and supports only a subset of keys.
4. Stop sharing, disconnect, reconnect, then disconnect abruptly while a key and a mouse button are held. Verify both are released on Windows. Repeat for app termination and network interruption.
5. Test wrong pins, missing client identity, invalid port and missing permissions: each must fail closed. Test legitimate pin on both ends. Observe UI and process logs; no sensitive data should be logged.
6. Test clipboard with either endpoint disabled and confirm no clipboard transfer occurs (the receiver may close the session upon rejecting an unexpected clipboard message). Enable clipboard on both ends and test ordinary text copied on macOS reaches Windows. Only changes after capture begins are sent. Verify stopping sharing stops further updates. Reverse clipboard synchronization is not implemented.

Record OS versions, commit SHA, results, errors, and which tests were actually performed. Never mark this plan passed without real observations. Automated Swift tests and Windows CI compilation do not substitute for these steps.

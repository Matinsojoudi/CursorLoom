#!/usr/bin/env bash
# Generates throwaway self-signed identities for a CursorLoom loopback/interop test.
# Pinning ignores CA chains, so self-signed certificates are sufficient — but they
# provide no hostname or revocation protection. Never reuse these in production.
set -euo pipefail

out="${1:-./cursorloom-certs}"
pass="${2:-cursorloom-test}"

command -v openssl >/dev/null || { echo "openssl is required" >&2; exit 1; }
mkdir -p "$out"
chmod 700 "$out"

make_identity() {
  local name="$1" eku="$2"
  openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 30 \
    -keyout "$out/$name.key" -out "$out/$name.pem" \
    -subj "/CN=cursorloom-$name" \
    -addext "extendedKeyUsage=$eku" \
    -addext "keyUsage=digitalSignature,keyEncipherment" >/dev/null 2>&1
  openssl pkcs12 -export -inkey "$out/$name.key" -in "$out/$name.pem" \
    -out "$out/$name.p12" -passout "pass:$pass" >/dev/null 2>&1
  local fp
  fp=$(openssl x509 -in "$out/$name.pem" -outform DER | shasum -a 256 | awk '{print $1}')
  printf '%s fingerprint (SHA-256):\n' "$name"
  printf '  %s\n' "$(echo "$fp" | fold -w2 | paste -sd: -)"
}

make_identity client clientAuth
make_identity server serverAuth

cat <<EOF

Certificates written to: $out
PKCS#12 password: $pass
Private keys stay in this directory; delete the whole directory after testing.

Next steps:
  * On the sending computer, import "$out/client.p12" and enter the SERVER fingerprint.
  * On the receiving computer, import "$out/server.p12" and enter the CLIENT fingerprint.
  * Both fingerprints are printed above; copy them by hand, never over the network
    you are testing.
EOF

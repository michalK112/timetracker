#!/bin/bash
# Tworzy raz certyfikat „TimeTracker Local” do podpisywania aplikacji.
# Dzięki niemu macOS pamięta Dostępność między kompilacjami (build.sh używa go automatycznie).
set -e
NAME="TimeTracker Local"
if security find-identity -p codesigning 2>/dev/null | grep -q "$NAME"; then
  echo "Certyfikat „$NAME” już jest w pęku kluczy."; exit 0
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -out "$TMP/cert.p12" -passout pass:timetracker
security import "$TMP/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P timetracker -T /usr/bin/codesign
echo "✅ Certyfikat „$NAME” dodany. Uruchom teraz build.sh — aplikacja podpisze się nim automatycznie."

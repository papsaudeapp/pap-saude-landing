#!/usr/bin/env bash
set -euo pipefail
[[ -s site/index.html ]] || { echo 'ERROR: site/index.html missing'; exit 1; }
# Do not accidentally commit a dump, .env or credentials copied from the server.
if find site -type l | grep -q .; then echo 'ERROR: site contains symlinks'; exit 1; fi
if find site -type f | grep -Ei '/(\.env([^/]*|$)|[^/]*\.(pem|key|p12|pfx|sqlite|db|dump|bak|sql)|id_(rsa|ed25519)|[^/]*backup[^/]*)$' >/dev/null; then
  echo 'ERROR: sensitive-looking file under site/'; exit 1
fi
if find site -type f -size +50M | grep -q .; then echo 'ERROR: unusually large file under site/'; exit 1; fi
# Simple validity/smoke checks. No client-side build tools needed for this static site.
grep -Eqi '<html([[:space:]>])' site/index.html || { echo 'ERROR: no HTML root'; exit 1; }
! grep -qE 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY' site/index.html || { echo 'ERROR: private key signature'; exit 1; }
echo 'PASS static landing validation'

#!/usr/bin/env bash
# Install as root-owned /usr/local/sbin/pap-landing-deploy. Never run directly from a Git checkout on the VPS.
set -euo pipefail
umask 077

sha="${1:-}"; digest="${2:-}"
if [[ ! "$sha" =~ ^[a-f0-9]{40}$ || ! "$digest" =~ ^sha256:[a-f0-9]{64}$ ]]; then
  echo 'INVALID_REVISION_OR_DIGEST' >&2; exit 2
fi
root=/opt/pap-landing
marker="$root/READY_FOR_CI_DEPLOY"
compose="$root/compose.yml"
envfile="$root/.env"
image="ghcr.io/papsaudeapp/pap-saude-landing@$digest"

if [[ ! -f "$marker" || ! -f "$compose" || ! -f "$envfile" ]]; then
  echo 'LANDING_BOOTSTRAP_NOT_APPROVED' >&2; exit 3
fi
# These deployment configuration files must remain owned by root, never by the CI SSH account.
for file in "$marker" "$compose" "$envfile"; do
  [[ -f "$file" && ! -L "$file" && "$(stat -c %u "$file")" == '0' && "$(stat -c %a "$file")" != '777' ]] || { echo 'UNSAFE_DEPLOYMENT_CONFIG' >&2; exit 4; }
done

cd "$root"
compose_cmd=(docker compose --project-name pap-landing --env-file "$envfile" --file "$compose")
old="$(sed -n 's/^LANDING_IMAGE=//p' "$envfile")"
[[ "$old" =~ ^ghcr\.io/papsaudeapp/pap-saude-landing@sha256:[a-f0-9]{64}$ ]] || { echo 'INVALID_CURRENT_IMAGE' >&2; exit 5; }

docker pull "$image"
revision="$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$image")"
source="$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.source" }}' "$image")"
[[ "$revision" == "$sha" && "$source" == 'https://github.com/papsaudeapp/pap-saude-landing' ]] || { echo 'IMAGE_PROVENANCE_MISMATCH' >&2; exit 6; }

newenv="$(mktemp "$root/.env.new.XXXXXX")"
trap 'rm -f "$newenv"' EXIT
printf 'LANDING_IMAGE=%s\n' "$image" > "$newenv"
chmod 0600 "$newenv"
mv -f "$newenv" "$envfile"

restore() {
  echo 'LANDING_DEPLOY_UNHEALTHY_RESTORING_PREVIOUS_IMAGE' >&2
  printf 'LANDING_IMAGE=%s\n' "$old" > "$envfile"
  chmod 0600 "$envfile"
  "${compose_cmd[@]}" up -d --no-deps --pull never web || true
}

if ! "${compose_cmd[@]}" up -d --no-deps --pull never web; then
  restore; exit 7
fi
healthy=0
for _ in {1..20}; do
  state="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' pap-landing-web 2>/dev/null || true)"
  if [[ "$state" == healthy ]] && curl -fsS --max-time 3 http://127.0.0.1:3102/healthz >/dev/null; then
    healthy=1; break
  fi
  sleep 2
done
if [[ "$healthy" != 1 ]]; then restore; exit 8; fi
printf 'PASS landing deployed SHA=%s image=%s\n' "$sha" "$image"

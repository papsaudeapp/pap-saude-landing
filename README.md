# PAP Saúde — Landing Page

Independent static landing repository. Source of truth: **the actual publicly served landing** exported from the VPS (`/var/www/pap-maintenance`).
This repository does NOT contain the administration or clinical code.

## Safety model

- `main` for development; `prod` for approved releases.
- GitHub Actions validate/build on `main` and `prod`; publish to `ghcr.io/papsaudeapp/pap-saude-landing:sha-<commit>` only on `prod`.
- Auto-deploy is **disabled until the initial manual cutover**; enable GitHub Actions variable `LANDING_AUTODEPLOY_ENABLED=true` only afterward.
- First launch new container on host loopback `127.0.0.1:3102`. Nginx/Cloudflare/TLS continue on host.
- No automatic changes to `/opt/pap-saude`, `/opt/pap-saude-beta`, `pap-web`, `pap-postgres`, or `pap-n8n`.
- Host Nginx cutover is **manual**, after inspecting existing papsaude.com.br/www vhosts and `pap-mode.conf` (don't blindly replace them).

## Import actual VPS site (run on WSL, never inside a VPS Git checkout)

First, on VPS, inventory public document root for sensitive files and confirm it's the one actually served:

```sh
ssh papserver 'sudo find /var/www/pap-maintenance -maxdepth 3 -type f -printf "%P\n" | sort'
```

If safe, bundle into private per-user staging on VPS (interactive sudo):

```sh
ssh -t papserver 'umask 077; sudo tar -C /var/www/pap-maintenance -czf /home/papadmin/pap-landing-export.tar.gz . && sudo chown papadmin:papadmin /home/papadmin/pap-landing-export.tar.gz && chmod 600 /home/papadmin/pap-landing-export.tar.gz'
```

Then on WSL, inside your freshly initialized `pap-saude-landing` checkout, run:

```sh
scp papserver:/home/papadmin/pap-landing-export.tar.gz /tmp/pap-landing-export.tar.gz
mkdir -p site
tar -tzf /tmp/pap-landing-export.tar.gz | head -80  # review before extraction
# Extract only when content is verified public; do not copy dotfiles or secrets to Git.
tar -xzf /tmp/pap-landing-export.tar.gz -C site
bash scripts/validate.sh
git status --short
```

After confirming source is correct, securely remove the staging copies using your usual retention policy (do not remove original site). Note: backup remains only as long as you need to verify successful import.

## First installation on VPS

1. Publish `prod` image. Do NOT enable auto-deploy yet.
2. Install root-owned `ops/compose.yml` in `/opt/pap-landing/compose.yml`, root-owned `ops/deploy.sh` to `/usr/local/sbin/pap-landing-deploy` (mode 0750); create `.env` with the approved image **digest**, not `latest`.
3. Pull and run the landing Compose. Verify `curl http://127.0.0.1:3102/healthz` and HTML/styles/images; do not modify public vhosts yet.
4. Inspect and back up current Nginx site configs; only then manually switch landing host names to proxy to `127.0.0.1:3102`. Preserve ACME, TLS, www and any maintenance-mode logic. `nginx -t` before controlled reload; test and rollback if needed.
5. Create root-owned empty marker `/opt/pap-landing/READY_FOR_CI_DEPLOY` after a successful manual cutover. Set repo Actions variable `LANDING_AUTODEPLOY_ENABLED=true` and required secrets. Enable only the landing workflow.

### GitHub Actions secrets (in the NEW repo)

- `LANDING_SSH_KEY` — **new dedicated deploy SSH key**, not production's existing key.
- `LANDING_KNOWN_HOSTS` — pinned, independently verified host key line (not blindly `ssh-keyscan` inside CI).
- `LANDING_VPS_HOST` — VPS host/IP.
- `LANDING_VPS_PORT` — SSH port.
- `LANDING_VPS_USER` — separate deployment account with only `sudo -n /usr/local/sbin/pap-landing-deploy` authorized.
- Variable: `LANDING_AUTODEPLOY_ENABLED`, initially absent/false.

`GHCR` may require setting package access for the repository to **Write** and a new read-only pull credential on VPS if the image is private. Do not reuse PAP Admin's Docker auth or broader production PAT.

### Rollback

The deploy script records the previous immutable image and attempts to restore it on failed health checks. Manually restore the original Nginx site configuration if the first cutover fails. Keep the old `/var/www/pap-maintenance` content and all old vhost configs until after post-deploy verification.

### Known limits

- Landing is a static-site image (Nginx), no Next.js runtime. If the VPS source uses dynamic server-side code, this scaffold is NOT appropriate until adapted.
- Rolling update of a single Compose service has a short possible downtime. Blue/green zero-downtime deployment can be added after first stabilization.
- `ops/deploy.sh` and VPS setup have not been executed against your VPS; first deployment remains manual and requires operator review.

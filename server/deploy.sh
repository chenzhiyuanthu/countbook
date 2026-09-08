#!/usr/bin/env bash
# Deploy the 花得值 sync server to a host you control.
#
#   SSHPASS='...' ./deploy.sh            # password auth (needs sshpass)
#   ./deploy.sh                          # once your key is installed
#   SSH_HOST=1.2.3.4 DOMAIN=x.example ./deploy.sh
#
# The web app on GitHub Pages talks to this over HTTPS, so ALLOWED_ORIGINS must
# contain that origin or the browser will refuse the response.
set -euo pipefail

SSH_USER="${SSH_USER:-ubuntu}"
SSH_HOST="${SSH_HOST:-43.162.121.196}"
REMOTE_DIR="${REMOTE_DIR:-/opt/countbook}"
DOMAIN="${DOMAIN:-count.czylsy911.art}"
ORIGINS="${ALLOWED_ORIGINS:-https://chenzhiyuanthu.github.io}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${SSH_USER}@${SSH_HOST}"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=15)

if [[ -n "${SSHPASS:-}" ]]; then
  command -v sshpass >/dev/null || { echo "sshpass missing: brew install sshpass"; exit 1; }
  SSH=(sshpass -e ssh "${SSH_OPTS[@]}")
else
  SSH=(ssh "${SSH_OPTS[@]}")
fi

say() { printf '\n\033[1;33m▸ %s\033[0m\n' "$*"; }

say "1/6  Server check"
"${SSH[@]}" "$TARGET" 'echo "  $(hostname) · $(. /etc/os-release; echo $PRETTY_NAME)"; echo "  docker: $(sudo docker --version 2>/dev/null || echo MISSING)"'

say "2/6  Uploading source to ${REMOTE_DIR}"
"${SSH[@]}" "$TARGET" "sudo mkdir -p ${REMOTE_DIR} && sudo chown -R ${SSH_USER}:${SSH_USER} ${REMOTE_DIR}"
tar czf - -C "$HERE" package.json server.js Dockerfile docker-compose.yml caddy \
  | "${SSH[@]}" "$TARGET" "tar xzf - -C ${REMOTE_DIR}"
echo "  uploaded"

say "3/6  Secrets and data directory"
# The container runs as uid 1000 (`node`); Docker would otherwise create the
# bind-mounted data directory as root and the app could not write its database.
"${SSH[@]}" "$TARGET" "
  set -e
  mkdir -p ${REMOTE_DIR}/data && sudo chown -R 1000:1000 ${REMOTE_DIR}/data
  if [ ! -f ${REMOTE_DIR}/.env ]; then
    printf 'SESSION_SECRET=%s\nALLOWED_ORIGINS=%s\nSIGNUP_CODE=%s\n' \
      \"\$(head -c 32 /dev/urandom | base64 | tr -d '=+/' )\" \
      '${ORIGINS}' \
      \"\$(head -c 9 /dev/urandom | base64 | tr -d '=+/' )\" \
      > ${REMOTE_DIR}/.env
    chmod 600 ${REMOTE_DIR}/.env
    echo '  wrote a fresh .env'
  else
    echo '  .env already present, left alone'
  fi
  sudo docker network inspect countbook-edge >/dev/null 2>&1 || sudo docker network create countbook-edge
"

say "4/6  Choosing an edge"
# Binding 80/443 twice fails, so only run our own Caddy when nothing else holds
# those ports.
MODE=$("${SSH[@]}" "$TARGET" "sudo docker ps --format '{{.Ports}}' | grep -q ':443->' && echo attach || echo standalone")
echo "  ${MODE}"

say "5/6  Building and starting"
if [[ "$MODE" == "standalone" ]]; then
  "${SSH[@]}" "$TARGET" "cd ${REMOTE_DIR} && sudo docker compose --profile edge up -d --build 2>&1 | tail -20"
else
  "${SSH[@]}" "$TARGET" "cd ${REMOTE_DIR} && sudo docker compose up -d --build 2>&1 | tail -20"
  # Wire the existing edge Caddy to this app and give it the site block.
  "${SSH[@]}" "$TARGET" "
    EDGE=\$(sudo docker ps --filter 'publish=443' --format '{{.Names}}' | head -1)
    if [ -n \"\$EDGE\" ]; then
      sudo docker network connect countbook-edge \"\$EDGE\" 2>/dev/null || true
      echo \"  attached \$EDGE to countbook-edge\"
      echo '  --- add this to that stack'\''s Caddyfile, then restart it ---'
      cat ${REMOTE_DIR}/caddy/countbook.caddy
    fi
  "
fi

say "6/6  Waiting for the app to answer"
"${SSH[@]}" "$TARGET" "
  for i in \$(seq 1 40); do
    if curl -fsS http://127.0.0.1:8788/healthz >/dev/null 2>&1; then echo '  healthz OK'; exit 0; fi
    sleep 2
  done
  echo '  !! app never became healthy'
  cd ${REMOTE_DIR} && sudo docker compose logs --tail 40
  exit 1
"

printf '\n\033[1;32m✓ deployed\033[0m  https://%s\n' "$DOMAIN"
printf '  Point %s at %s if it does not resolve yet.\n' "$DOMAIN" "$SSH_HOST"
printf '  The signup code is in %s/.env on the server.\n\n' "$REMOTE_DIR"

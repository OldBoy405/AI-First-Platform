#!/usr/bin/env bash
# AIFI-45 M2: real platform issuance + daemon-owned trust installation probe.
#
# This script deliberately stops at the first hard blocker. It never substitutes
# a fixture signer, fake HTTP router, fake DB, fake binding endpoint, or a locally
# spawned admission child for the real daemon path. The initial workspace and one
# pipeline queue carrier are seeded in the disposable real DB; task CLAIM, claim
# revalidation, authorization delivery, trust installation, crctl --check and the
# terminal callback use the real backend routes and real multica daemon.
#
# Boundary: disposable PG/tmpfs, self-signed CA and same-UID container processes
# are not production isolation or production activation evidence.
set -euo pipefail
export MSYS_NO_PATHCONV=1

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERE_WIN="$(cygpath -m "$HERE" 2>/dev/null || printf '%s' "$HERE")"
OUT="${AIFI45_EVIDENCE_DIR:-$HERE}"
mkdir -p "$OUT"
OUT_WIN="$(cygpath -m "$OUT" 2>/dev/null || printf '%s' "$OUT")"
if [ "$HERE_WIN" != "$OUT_WIN" ]; then cp "$HERE/run.sh" "$OUT/run.sh"; fi
# Never leave a previous run's conclusion visible after an earlier-stage failure.
rm -f "$OUT/README.md" "$OUT/run-facts.json" "$OUT/manifest.sha256.txt" \
  "$OUT/daemon.log.txt" "$OUT/negative-tampered.stdout.txt" "$OUT/negative-cross-project.stdout.txt" \
  "$OUT/binding-relay.stdout.txt" "$OUT/db-consumption.stdout.txt" "$OUT/disk-free.stdout.txt"
REPO="${MULTICA_REPO:-C:/Users/GOBAO/Downloads/AI/multica}"
SERVER="$REPO/server"
TOOLS="${AIFI45_TOOLS:-C:/Users/GOBAO/Downloads/AI/tools-aifi45}"
PG_IMAGE="${AIFI45_PG_IMAGE:-docker.io/pgvector/pgvector:pg17}"
NODE_IMAGE="${AIFI45_NODE_IMAGE:-docker.io/library/node:22-alpine}"
CR_ID="CR-2026-992"

TMPDIR_RUN="$(mktemp -d)"
TMP_WIN="$(cygpath -m "$TMPDIR_RUN" 2>/dev/null || printf '%s' "$TMPDIR_RUN")"
NONCE="$(node -e "console.log(require('crypto').randomBytes(8).toString('hex'))")"
NET_NAME="aifi45-m2-net-$NONCE"
PG_NAME="aifi45-m2-pg-$NONCE"
BACKEND_NAME="aifi45-m2-backend-$NONCE"
TLS_NAME="aifi45-m2-tls-$NONCE"
DAEMON_NAME="aifi45-m2-daemon-$NONCE"
DAEMON_ID="$(node -e "console.log(require('crypto').randomUUID())")"
BACKEND_IMAGE="localhost/multica-backend:m2-$(date -u +%Y%m%dT%H%M%SZ)-$NONCE"
printf '%s\n' "$BACKEND_IMAGE" > "$OUT/backend-image-tag.txt"

PG_PASSWORD="$(node -e "console.log(require('crypto').randomBytes(18).toString('hex'))")"
ROLE_NAME="aifi45_m2_$NONCE"
DB_NAME="aifi45_m2_$NONCE"
ROLE_PASSWORD="$(node -e "console.log(require('crypto').randomBytes(18).toString('hex'))")"
DAEMON_TOKEN="mdt_$(node -e "console.log(require('crypto').randomBytes(20).toString('hex'))")"
JWT_SECRET="$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")"
RUN_STATUS="not-run"
BLOCKER=""
DISK_LOW=0

disk_free() {
  local step="$1" free
  free="$(powershell -NoProfile -Command "Get-PSDrive C | %{ [math]::Round(\$_.Free/1GB,2) }" | tr -d '\r')"
  printf '%s\t%s GB free\n' "$step" "$free" | tee -a "$OUT/disk-free.stdout.txt"
  if node -e 'process.exit(Number(process.argv[1]) < 3 ? 0 : 1)' "$free"; then
    DISK_LOW=1
    printf 'STOP: C: free space below 3 GB at %s\n' "$step" | tee -a "$OUT/disk-free.stdout.txt"
    return 1
  fi
}

manifest() {
  set +e
  RUN_STATUS="$RUN_STATUS" BLOCKER="$BLOCKER" OUT_WIN_M="$OUT_WIN" BACKEND_IMAGE_M="$BACKEND_IMAGE" node - <<'NODE'
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const out = process.env.OUT_WIN_M;
const names = [
  'run.sh', 'build.stdout.txt', 'migrate.stdout.txt', 'health.stdout.txt',
  'issue-authorization.stdout.txt', 'issue-cross-project.stdout.txt', 'db-grant-row.stdout.txt',
  'trust-root-install.stdout.txt', 'binding-relay.stdout.txt',
  'crctl-admission.stdout.txt', 'db-consumption.stdout.txt',
  'negative-tampered.stdout.txt', 'negative-cross-project.stdout.txt',
  'podman-ps-after.stdout.txt', 'image-cleanup.stdout.txt', 'disk-free.stdout.txt',
  'run-facts.json', 'README.md', 'run-exit-code.txt',
];
const lines = [];
for (const name of names) {
  const file = path.join(out, name);
  if (!fs.existsSync(file)) continue;
  const normalized = fs.readFileSync(file).toString('utf8').replaceAll('\r\n', '\n');
  const digest = crypto.createHash('sha256').update(normalized, 'utf8').digest('hex');
  lines.push(`${digest}  ${name}`);
}
fs.writeFileSync(path.join(out, 'manifest.sha256.txt'), lines.join('\n') + '\n');
NODE
}
cleanup() {
  local exit_code=$?
  set +e
  printf '%s\n' "$exit_code" > "$OUT/run-exit-code.txt"
  if [ -n "${RUNNER_HOME:-}" ] && [ -f "$RUNNER_HOME/daemon.log" ]; then cp "$RUNNER_HOME/daemon.log" "$OUT/daemon.log.txt"; fi
  podman logs "$DAEMON_NAME" > "$OUT/daemon-container.log.txt" 2>&1
  podman logs "$BACKEND_NAME" > "$OUT/backend.log.txt" 2>&1
  podman logs "$TLS_NAME" > "$OUT/tls-proxy.log.txt" 2>&1
  podman rm -f "$DAEMON_NAME" "$TLS_NAME" "$BACKEND_NAME" "$PG_NAME" >/dev/null 2>&1
  podman network rm "$NET_NAME" >/dev/null 2>&1
  printf '\n$ podman image rm -f %s\n' "$BACKEND_IMAGE" > "$OUT/image-cleanup.stdout.txt"
  podman image rm -f "$BACKEND_IMAGE" >> "$OUT/image-cleanup.stdout.txt" 2>&1
  if podman image inspect "$BACKEND_IMAGE" >/dev/null 2>&1; then
    printf 'image_deleted=false\n' >> "$OUT/image-cleanup.stdout.txt"
  else
    printf 'image_deleted=true\n' >> "$OUT/image-cleanup.stdout.txt"
  fi
  rm -rf "$TMPDIR_RUN"
  podman ps -a --format '{{.Names}}\t{{.Status}}\t{{.Image}}' > "$OUT/podman-ps-after.stdout.txt" 2>&1
  printf '\n$ exact flow image after cleanup\n' >> "$OUT/podman-ps-after.stdout.txt"
  podman images --digests --format '{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Digest}}' | grep -F "$BACKEND_IMAGE" >> "$OUT/podman-ps-after.stdout.txt" 2>&1
  disk_free cleanup >/dev/null 2>&1
  manifest
  return "$exit_code"
}
trap cleanup EXIT

podman ps -a --format '{{.Names}}\t{{.Status}}\t{{.Image}}' > "$OUT/podman-ps-before.stdout.txt"
disk_free start
psql_q() {
  podman exec -i -e PGPASSWORD="$ROLE_PASSWORD" "$PG_NAME" \
    psql -X -q -v ON_ERROR_STOP=1 -U "$ROLE_NAME" -d "$DB_NAME" "$@"
}
psql_at() {
  podman exec -i -e PGPASSWORD="$ROLE_PASSWORD" "$PG_NAME" \
    psql -X -q -A -t -v ON_ERROR_STOP=1 -U "$ROLE_NAME" -d "$DB_NAME" -c "$1"
}

echo '== [1/8] rebuild current source image =='
(
  cd "$REPO"
  {
    printf '$ podman build --rm --pull=never -t %s -f Dockerfile .\n' "$BACKEND_IMAGE"
    printf 'source_HEAD=%s\n' "$(git rev-parse HEAD)"
    printf 'source_dirty_entries=%s\n' "$(git status --porcelain | wc -l | tr -d ' ')"
    podman build --rm --pull=never \
      --build-arg "VERSION=m2-$NONCE" --build-arg "COMMIT=$(git rev-parse HEAD)" \
      -t "$BACKEND_IMAGE" -f Dockerfile .
    printf 'build_exit=0\n'
    printf '\n$ podman image inspect %s --format {{.Id}}\n' "$BACKEND_IMAGE"
    podman image inspect "$BACKEND_IMAGE" --format '{{.Id}}'
    printf '\n$ podman images (exact tag)\n'
    podman images --digests --format '{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Digest}}' | grep -F "$BACKEND_IMAGE"
  } 2>&1 | tee "$OUT/build.stdout.txt"
)

disk_free build
echo '== [2/8] disposable network / CA / tmpfs PG / real migrations =='
mkdir -p "$TMP_WIN/signals"
cat > "$TMPDIR_RUN/tlsproxy.go" <<'GO'
package main
import (
  "flag"
  "log"
  "net/http"
  "net/http/httputil"
  "net/url"
  "os"
  "path/filepath"
  "strings"
  "time"
)
func main() {
  listen := flag.String("listen", ":8443", "listen")
  target := flag.String("target", "http://backend:8080", "target")
  cert := flag.String("cert", "/certs/server.crt", "cert")
  key := flag.String("key", "/certs/server.key", "key")
  signalDir := flag.String("signal-dir", "", "test synchronization directory")
  flag.Parse()
  upstream, err := url.Parse(*target)
  if err != nil { log.Fatal(err) }
  proxy := httputil.NewSingleHostReverseProxy(upstream)
  proxy.ErrorHandler = func(w http.ResponseWriter, r *http.Request, err error) {
    log.Printf("upstream %s %s: %v", r.Method, r.URL.Path, err)
    http.Error(w, "upstream unavailable", http.StatusBadGateway)
  }
  proxy.Transport = roundTripperFunc(func(r *http.Request) (*http.Response, error) {
    resp, err := http.DefaultTransport.RoundTrip(r)
    status := 0
    if resp != nil { status = resp.StatusCode }
    log.Printf("proxy %s %s -> %d err=%v", r.Method, r.URL.Path, status, err)
    // Deterministic negative-test window: the real platform has committed its
    // binding response, but T has not received it yet. No response or signature
    // is altered; only this disposable proxy delays the cross-project case.
    if err == nil && resp != nil && *signalDir != "" && strings.HasSuffix(r.URL.Path, "/execution-authorization/binding") {
      if _, statErr := os.Stat(filepath.Join(*signalDir, "arm-cross")); statErr == nil {
        _ = os.WriteFile(filepath.Join(*signalDir, "binding-returned"), []byte("committed\n"), 0600)
        time.Sleep(750 * time.Millisecond)
      }
    }
    return resp, err
  })
  log.Printf("tls proxy listening on %s -> %s", *listen, *target)
  log.Fatal((&http.Server{Addr: *listen, Handler: proxy}).ListenAndServeTLS(*cert, *key))
}
type roundTripperFunc func(*http.Request) (*http.Response, error)
func (f roundTripperFunc) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
GO
(
  cd "$TMP_WIN"
  GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -o tlsproxy-linux tlsproxy.go
)
chmod +x "$TMPDIR_RUN/tlsproxy-linux"
podman network create "$NET_NAME" >/dev/null
mkdir -p "$TMP_WIN/pki"
(
  cd "$TMP_WIN/pki"
  openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt -days 2 \
    -subj "/CN=AIFI45 M2 disposable CA $NONCE" >/dev/null 2>&1
  openssl req -newkey rsa:2048 -nodes -keyout server.key -out server.csr \
    -subj "/CN=tls-$NONCE" >/dev/null 2>&1
  printf 'subjectAltName=DNS:tls,DNS:backend,DNS:localhost,IP:127.0.0.1\nbasicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n' > ext.cnf
  openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
    -out server.crt -days 2 -extfile ext.cnf >/dev/null 2>&1
  openssl verify -CAfile ca.crt server.crt
) > "$OUT/tls-ca.stdout.txt" 2>&1

podman run -d --rm --name "$PG_NAME" \
  --network "$NET_NAME" --network-alias pg \
  -e POSTGRES_PASSWORD="$PG_PASSWORD" -p 127.0.0.1::5432 \
  --tmpfs /var/lib/postgresql/data:rw "$PG_IMAGE" >/dev/null
for _ in $(seq 1 60); do
  if podman exec "$PG_NAME" pg_isready -U postgres >/dev/null 2>&1; then break; fi
  sleep 1
done
podman exec "$PG_NAME" pg_isready -U postgres | tee "$OUT/pg-ready.stdout.txt"
HOST_PG_PORT="$(podman port "$PG_NAME" 5432/tcp | sed 's/.*://')"
podman exec -i "$PG_NAME" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d postgres <<SQL
CREATE ROLE "$ROLE_NAME" LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS PASSWORD '$ROLE_PASSWORD';
COMMENT ON ROLE "$ROLE_NAME" IS 'AIFI45_DISPOSABLE:$NONCE';
CREATE DATABASE "$DB_NAME" WITH TEMPLATE template0 OWNER "$ROLE_NAME";
COMMENT ON DATABASE "$DB_NAME" IS 'AIFI45_DISPOSABLE:$NONCE';
SQL
export DATABASE_URL="postgres://$ROLE_NAME:$ROLE_PASSWORD@127.0.0.1:$HOST_PG_PORT/$DB_NAME?sslmode=disable"
(
  cd "$SERVER"
  go run ./cmd/migrate up
) 2>&1 | tee "$OUT/migrate.stdout.txt"

echo '== [3/8] seed initial ownership graph and start real backend =='
mkdir -p "$TMP_WIN/workspace/change-requests/$CR_ID" "$TMP_WIN/workspace/.crctl/outbox"
cat > "$TMP_WIN/workspace/dir-graph.yaml" <<'YAML'
workspace:
  tools_package_path: /tools-aifi45
YAML
cat > "$TMP_WIN/workspace/change-requests/$CR_ID/cr.md" <<CRMD
---
id: $CR_ID
title: M2 real trust delivery probe
status: writing-back
execution-contract: authorized-execution/v1
---
# M2 real trust delivery probe
CRMD
TMP_WIN_M="$TMP_WIN" DAEMON_ID_M="$DAEMON_ID" CR_ID_M="$CR_ID" NONCE_M="$NONCE" node - <<'NODE'
const crypto = require('crypto');
const fs = require('fs');
const uuid = () => crypto.randomUUID();
const ids = {
  user_id: uuid(), workspace_id: uuid(), project_id: uuid(), issue_id: uuid(),
  resource_id: uuid(), run_id: uuid(), node_run_id: uuid(), comment_id: uuid(),
  task_id: uuid(), cr_id: process.env.CR_ID_M,
};
const ref = {
  local_path: '/workspace', daemon_id: process.env.DAEMON_ID_M,
  kind: 'm2_real_root', execution_mode: 'in_place',
};
const identity = {
  daemon_id: process.env.DAEMON_ID_M, local_path: '/workspace', execution_mode: 'in_place',
};
const identityB64 = Buffer.from(JSON.stringify(identity)).toString('base64');
const projection = {
  resource_id: ids.resource_id, workspace_id: ids.workspace_id,
  project_id: ids.project_id, resource_type: 'local_directory', identity_b64: identityB64,
};
ids.resource_ref = ref;
ids.binding_digest = crypto.createHash('sha256')
  .update('project-resource-binding/v1\0').update(JSON.stringify(projection)).digest('hex');
fs.writeFileSync(process.env.TMP_WIN_M + '/ids.json', JSON.stringify(ids, null, 2));
const strictComment = [
  'run this archive node', '', '```yaml', 'context:', '  execution:',
  '    contract: authorized-execution/v1', '```', '',
].join('\n');
const context = {
  type: 'pipeline_node', schema: 'ai-first.pipeline-task/v1', workspace_id: ids.workspace_id,
  cr_id: ids.cr_id, run_id: ids.run_id, node_id: '00000000-0000-0000-0013-000000000005',
  pipeline_id: 'feature-writeback', attempt: 1, prompt: 'real daemon trust installation probe',
};
const executionContext = { template_digest: 'sha256:6a63a222146eb018564cd0487e8b1ab5352f832fd3d972f6c065ff7010c01108' };
fs.writeFileSync(process.env.TMP_WIN_M + '/seed-initial.sql', `
INSERT INTO "user" (id,name,email) VALUES ('${ids.user_id}','M2 disposable owner','m2-${process.env.NONCE_M}@example.invalid');
INSERT INTO workspace (id,name,slug,description,issue_counter) VALUES ('${ids.workspace_id}','M2 disposable','m2-${process.env.NONCE_M}','disposable M2',2);
INSERT INTO member (workspace_id,user_id,role) VALUES ('${ids.workspace_id}','${ids.user_id}','owner');
INSERT INTO project (id,workspace_id,title) VALUES ('${ids.project_id}','${ids.workspace_id}','M2 project A');
INSERT INTO issue (id,workspace_id,project_id,title,creator_type,creator_id,number) VALUES ('${ids.issue_id}','${ids.workspace_id}','${ids.project_id}','M2 shell','member','${ids.user_id}',1);
INSERT INTO project_resource (id,workspace_id,project_id,resource_type,resource_ref,label) VALUES ('${ids.resource_id}','${ids.workspace_id}','${ids.project_id}','local_directory','${JSON.stringify(ref)}'::jsonb,'M2 real root');
INSERT INTO cr (workspace_id,cr_id,title,status,shell_issue_id) VALUES ('${ids.workspace_id}','${ids.cr_id}','M2 real loop','writing-back','${ids.issue_id}');
INSERT INTO comment (id,workspace_id,issue_id,author_type,author_id,content) VALUES ('${ids.comment_id}','${ids.workspace_id}','${ids.issue_id}','member','${ids.user_id}','${strictComment}');
INSERT INTO pipeline_run (id,workspace_id,pipeline_id,cr_id,issue_id,status,inputs,execution_context,started_by)
VALUES ('${ids.run_id}','${ids.workspace_id}','feature-writeback','${ids.cr_id}','${ids.issue_id}','running','{"cr_id":"${ids.cr_id}"}'::jsonb,'${JSON.stringify(executionContext)}'::jsonb,'${ids.user_id}');
INSERT INTO pipeline_node_run (id,run_id,node_id,ref,kind,seq,status,attempt)
VALUES ('${ids.node_run_id}','${ids.run_id}','00000000-0000-0000-0013-000000000005','cr-archive','skill',5,'running',1);
`);
fs.writeFileSync(process.env.TMP_WIN_M + '/pipeline-context.json', JSON.stringify({ context, executionContext }));
NODE
psql_q < "$TMPDIR_RUN/seed-initial.sql"
read -r WORKSPACE_ID USER_ID PROJECT_ID ISSUE_ID RESOURCE_ID BINDING_DIGEST RUN_ID NODE_RUN_ID COMMENT_ID TASK_ID <<< "$(node -e "const i=require('$TMP_WIN/ids.json'); console.log(i.workspace_id,i.user_id,i.project_id,i.issue_id,i.resource_id,i.binding_digest,i.run_id,i.node_run_id,i.comment_id,i.task_id)")"
DAEMON_HASH="$(node -e "console.log(require('crypto').createHash('sha256').update(process.argv[1]).digest('hex'))" "$DAEMON_TOKEN")"
psql_q <<SQL
INSERT INTO daemon_token (token_hash,workspace_id,daemon_id,expires_at)
VALUES ('$DAEMON_HASH','$WORKSPACE_ID','$DAEMON_ID',now()+interval '2 hours');
SQL

node - "$TMP_WIN/approval-key.env" "$TMP_WIN/execution-contract.json" "$TMP_WIN/manifest.sha256.txt" "$NONCE" <<'NODE'
const crypto = require('crypto');
const fs = require('fs');
const { privateKey } = crypto.generateKeyPairSync('ed25519');
const der = privateKey.export({ type: 'pkcs8', format: 'der' });
const manifest = JSON.stringify({
  schema: 'execution-contract-manifest/v1', policy_version: 'authorized-execution/v1',
  policy_digest: 'a'.repeat(64), template_digest: 'b'.repeat(64),
});
const sha = crypto.createHash('sha256').update(manifest).digest('hex');
fs.writeFileSync(process.argv[3], manifest);
fs.writeFileSync(process.argv[4], sha + '\n');
fs.writeFileSync(process.argv[2],
  `APPROVAL_SIGNING_KEY=${der.toString('base64')}\nAPPROVAL_SIGNING_KEY_ID=m2-${process.argv[5]}\nMANIFEST_SHA256=${sha}\n`);
NODE
# shellcheck disable=SC1090
source "$TMPDIR_RUN/approval-key.env"
podman run -d --rm --name "$BACKEND_NAME" \
  --network "$NET_NAME" --network-alias backend \
  -e DATABASE_URL="postgres://$ROLE_NAME:$ROLE_PASSWORD@pg:5432/$DB_NAME?sslmode=disable" \
  -e JWT_SECRET="$JWT_SECRET" -e APPROVAL_SIGNING_KEY="$APPROVAL_SIGNING_KEY" \
  -e APPROVAL_SIGNING_KEY_ID="$APPROVAL_SIGNING_KEY_ID" -e PORT=8080 \
  -v "$TMP_WIN/execution-contract.json:/evidence/execution-contract.json:ro" \
  --entrypoint /app/server "$BACKEND_IMAGE" \
  --execution-contract-manifest=/evidence/execution-contract.json \
  --execution-contract-manifest-sha256="$MANIFEST_SHA256" >/dev/null
for _ in $(seq 1 60); do
  if podman exec "$BACKEND_NAME" wget -q -O - http://127.0.0.1:8080/health >/dev/null 2>&1; then break; fi
  sleep 1
done
podman run -d --rm --name "$TLS_NAME" \
  --network "$NET_NAME" --network-alias tls -p 127.0.0.1::8443 \
  -v "$TMP_WIN/tlsproxy-linux:/usr/local/bin/tlsproxy:ro" \
  -v "$TMP_WIN/pki:/certs:ro" -v "$TMP_WIN/signals:/signals" \
  --entrypoint /usr/local/bin/tlsproxy "$NODE_IMAGE" \
  --listen :8443 --target http://backend:8080 --cert /certs/server.crt --key /certs/server.key --signal-dir /signals >/dev/null
for _ in $(seq 1 60); do
  if curl -fsS --ssl-no-revoke --cacert "$TMP_WIN/pki/ca.crt" "https://127.0.0.1:$(podman port "$TLS_NAME" 8443/tcp | sed 's/.*://')/health" >/dev/null 2>&1; then break; fi
  sleep 1
done
TLS_PORT="$(podman port "$TLS_NAME" 8443/tcp | sed 's/.*://')"
BACKEND_URL="https://127.0.0.1:$TLS_PORT"
{
  printf '$ curl --cacert <temporary-ca> https://127.0.0.1:%s/health\n' "$TLS_PORT"
  curl -sS -i --ssl-no-revoke --cacert "$TMP_WIN/pki/ca.crt" "$BACKEND_URL/health"
  printf '\n$ curl --cacert <temporary-ca> https://127.0.0.1:%s/readyz\n' "$TLS_PORT"
  curl -sS -i --ssl-no-revoke --cacert "$TMP_WIN/pki/ca.crt" "$BACKEND_URL/readyz"
  printf '\n$ /app/multica version\n'
  podman exec "$BACKEND_NAME" /app/multica version
} 2>&1 | tee "$OUT/health.stdout.txt"
disk_free migrate_health

JWT_FILE="$TMP_WIN/platform-jwt.txt"
JWT_SECRET="$JWT_SECRET" USER_ID_M="$USER_ID" NONCE_M="$NONCE" node - "$JWT_FILE" <<'NODE'
const crypto = require('crypto');
const fs = require('fs');
const b64u = value => Buffer.from(JSON.stringify(value)).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const header = b64u({ alg: 'HS256', typ: 'JWT' });
const payload = b64u({ sub: process.env.USER_ID_M, email: `m2-${process.env.NONCE_M}@example.invalid`, name: 'M2 disposable owner', exp: now + 3600, iat: now });
const signature = crypto.createHmac('sha256', process.env.JWT_SECRET).update(`${header}.${payload}`).digest('base64url');
fs.writeFileSync(process.argv[2], `${header}.${payload}.${signature}\n`);
NODE
JWT="$(cat "$JWT_FILE")"
api() {
  local method="$1" route="$2" body="${3:-}"
  if [ -n "$body" ]; then
    curl -sS --ssl-no-revoke --cacert "$TMP_WIN/pki/ca.crt" -X "$method" "$BACKEND_URL$route" \
      -H "authorization: Bearer $JWT" -H "x-workspace-id: $WORKSPACE_ID" \
      -H 'content-type: application/json' --data-binary "$body" -w '\nHTTP %{http_code}\n'
  else
    curl -sS --ssl-no-revoke --cacert "$TMP_WIN/pki/ca.crt" -X "$method" "$BACKEND_URL$route" \
      -H "authorization: Bearer $JWT" -H "x-workspace-id: $WORKSPACE_ID" -w '\nHTTP %{http_code}\n'
  fi
}

echo '== [4/8] real structured-human-request authorization route + DB row =='
IDS_FILE="$TMP_WIN/ids.json" SOURCE_FILE="$TMP_WIN/source-request.json" node - <<'NODE'
const fs = require('fs');
const ids = JSON.parse(fs.readFileSync(process.env.IDS_FILE, 'utf8'));
const selection = { resource_id: ids.resource_id, binding_digest: ids.binding_digest };
const body = {
  goal: 'M2 real cross-end trust delivery', scope_revision: 1,
  allowed_repositories: ['kb'], allowed_paths: { kb: ['change-requests'] },
  delivery_targets: ['review branch'], acceptance: ['accepted_rules: allow-a'],
  prohibitions: ['no production'], sensitive_actions: [],
  policy_version: 'authorized-execution/v1', policy_digest: 'a'.repeat(64), template_digest: 'b'.repeat(64),
  target_version: 'v1.0.0', target_spec_id: 'm2-real-loop', repair_limit: 1,
  repository_selections: { kb: selection }, coordinator_selection: selection,
};
// Deliberately preserve these exact bytes; the signed digest covers them.
fs.writeFileSync(process.env.SOURCE_FILE, JSON.stringify(body, null, 2));
NODE
SOURCE_BODY="$(cat "$TMPDIR_RUN/source-request.json")"
api POST "/api/workspaces/$WORKSPACE_ID/crs/$CR_ID/execution-authorization" "$SOURCE_BODY" \
  | tee "$OUT/issue-authorization.stdout.txt"
grep -q '^HTTP 201' "$OUT/issue-authorization.stdout.txt" || { echo 'authorization did not return 201'; exit 1; }
cp "$TMPDIR_RUN/source-request.json" "$OUT/source-request.json"
{
  printf '$ approval_record + authoritative CR/shell issue/project + current head\n'
  psql_at "SELECT a.id,a.workspace_id,a.cr_id,a.stage,a.decision,a.approver_user_id,a.evidence_digest,a.key_id,a.created_at,c.execution_authorization_head_id,i.project_id FROM approval_record a JOIN cr c ON c.workspace_id=a.workspace_id AND c.cr_id=a.cr_id LEFT JOIN issue i ON i.id=c.shell_issue_id WHERE a.workspace_id='$WORKSPACE_ID' AND a.cr_id='$CR_ID' AND a.stage='execution';"
  printf '\n$ computed facts from the actual HTTP response and exact source bytes\n'
  RESPONSE="$OUT_WIN/issue-authorization.stdout.txt" SOURCE="$OUT_WIN/source-request.json" node - <<'NODE'
const crypto = require('crypto');
const fs = require('fs');
const text = fs.readFileSync(process.env.RESPONSE, 'utf8').split('\nHTTP ')[0];
const response = JSON.parse(text);
const record = response.record;
const payload = JSON.parse(Buffer.from(record.envelope.payload_b64, 'base64').toString('utf8'));
const raw = fs.readFileSync(process.env.SOURCE);
const actualDigest = crypto.createHash('sha256').update(raw).digest('hex');
const storedRaw = Buffer.from(record.source.raw_b64, 'base64');
console.log(JSON.stringify({
  http_reused: response.reused, source_event_id: payload.source_event_id,
  source_digest: payload.source_digest, source_digest_prefix: payload.source_digest.slice(0, 16),
  actual_source_sha256: actualDigest, exact_source_bytes_equal: storedRaw.equals(raw),
  source_format: record.source.format, source_bindings_count: Object.keys(record.source.bindings).length,
  source_bindings: record.source.bindings, workspace_id: payload.workspace_id,
  project_id: payload.project_id, cr_id: payload.cr_id, grant_id: payload.grant_id,
}, null, 2));
if (!storedRaw.equals(raw) || actualDigest !== payload.source_digest) process.exit(1);
NODE
} 2>&1 | tee "$OUT/db-grant-row.stdout.txt"
disk_free authorization

echo '== [5/8] real daemon build / registration / real agent row =='
(
  cd "$SERVER"
  GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -mod=readonly -trimpath \
    -ldflags "-s -w -X main.version=m2-$NONCE -X main.commit=$(git rev-parse HEAD)" \
    -o "$TMP_WIN/multica" ./cmd/multica
) > "$OUT/daemon-build.stdout.txt" 2>&1
chmod +x "$TMPDIR_RUN/multica"
RUNNER_HOME="$TMPDIR_RUN/runner-home"
mkdir -p "$RUNNER_HOME"
WORKSPACE_ID="$WORKSPACE_ID" DAEMON_TOKEN="$DAEMON_TOKEN" NONCE="$NONCE" RUNNER_HOME_M="$TMP_WIN/runner-home" node - <<'NODE'
const fs = require('fs');
const config = {
  server_url: 'https://tls:8443', workspace_id: process.env.WORKSPACE_ID,
  token: process.env.DAEMON_TOKEN, device_name: `m2-${process.env.NONCE}`,
  workspaces_root: '/root/multica_workspaces', poll_interval: '1s',
  ws_claim_poll_interval: '2s', heartbeat_interval: '2s', max_concurrent_tasks: 1,
  disable_auto_update: true, disable_auto_reload: true,
};
fs.writeFileSync(process.env.RUNNER_HOME_M + '/config.json', JSON.stringify(config, null, 2));
NODE
cat > "$TMPDIR_RUN/daemon-entry.sh" <<'ENTRY'
set -eu
apk add --no-cache git >/tmp/apk-git.log 2>&1 || { tail -30 /tmp/apk-git.log; exit 1; }
printf '[user]\n\tname = M2 disposable\n\temail = m2@example.invalid\n' > /root/.gitconfig
npm i -g @earendil-works/pi-coding-agent >/tmp/npm-pi.log 2>&1 || { tail -30 /tmp/npm-pi.log; exit 1; }
pi --version
cat /etc/ssl/certs/ca-certificates.crt /certs/ca.crt > /tmp/ca-bundle.crt
export SSL_CERT_FILE=/tmp/ca-bundle.crt
exec /usr/local/bin/multica daemon start --foreground
ENTRY
podman run -d --name "$DAEMON_NAME" --network "$NET_NAME" \
  -e MULTICA_DAEMON_ID="$DAEMON_ID" -e MULTICA_AGENT_TIMEOUT=120s \
  -e MULTICA_CONTROLLED_SHELL_RULES=/tools-aifi45/skills/shared/controlled-shell/rules.json \
  -v "$TOOLS:/tools-aifi45:ro" -v "$TMP_WIN/pki:/certs:ro" \
  -v "$TMP_WIN/multica:/usr/local/bin/multica:ro" \
  -v "$TMP_WIN/runner-home:/root/.multica" \
  -v "$TMP_WIN/daemon-entry.sh:/entry/daemon-entry.sh:ro" \
  -v "$TMP_WIN/workspace:/workspace" -v "$TMP_WIN/signals:/signals" \
  --entrypoint /bin/sh "$NODE_IMAGE" -c 'sh /entry/daemon-entry.sh' >/dev/null
RUNTIME_ID=""
for i in $(seq 1 480); do
  RUNTIME_ID="$(psql_at "SELECT id FROM agent_runtime WHERE workspace_id='$WORKSPACE_ID' AND daemon_id='$DAEMON_ID' AND provider='pi' LIMIT 1" 2>/dev/null || true)"
  if [ -n "${RUNTIME_ID:-}" ]; then break; fi
  if ! podman inspect -f '{{.State.Running}}' "$DAEMON_NAME" 2>/dev/null | grep -q true; then
    podman logs "$DAEMON_NAME" 2>&1 | tail -100
    exit 1
  fi
  sleep 1
done
[ -n "$RUNTIME_ID" ] || { podman logs "$DAEMON_NAME" 2>&1 | tail -100; exit 1; }
# A daemon-token registration has no human runtime owner. Bind this disposable
# runtime to the seeded owner before the real claim can mint its mat_ token.
psql_q <<SQL
UPDATE agent_runtime SET owner_id='$USER_ID' WHERE id='$RUNTIME_ID';
SQL
AGENT_BODY="$(node -e 'console.log(JSON.stringify({name:"M2 real executor",description:"disposable real daemon executor",runtime_id:process.argv[1],model:"Gobao/deepseek-v4.1-flash",max_concurrent_tasks:1}))' "$RUNTIME_ID")"
api POST /api/agents "$AGENT_BODY" > "$OUT/agent-create.stdout.txt"
AGENT_ID="$(node -e 'const fs=require("fs");const t=fs.readFileSync(process.argv[1],"utf8").split("\nHTTP ")[0];try{const j=JSON.parse(t);console.log((j.agent&&j.agent.id)||j.id||"")}catch(e){console.log("")}' "$OUT_WIN/agent-create.stdout.txt")"
[ -n "$AGENT_ID" ] || { cat "$OUT/agent-create.stdout.txt"; exit 1; }
# Materialize the carrier only after its real executor exists. This is the
# declared initial queue seed, not a claim that the Runner dispatched it.
CONTEXT_JSON="$(node -e "const p=require('$TMP_WIN/pipeline-context.json');process.stdout.write(JSON.stringify(p.context))")"
psql_q <<SQL
INSERT INTO agent_task_queue (id,agent_id,runtime_id,issue_id,project_id,status,priority,context,originator_user_id,accountable_user_id,originator_source,trigger_comment_id,cr_id,pipeline_node_run_id)
VALUES ('$TASK_ID','$AGENT_ID','$RUNTIME_ID','$ISSUE_ID','$PROJECT_ID','queued',0,'$CONTEXT_JSON'::jsonb,'$USER_ID','$USER_ID','direct_human','$COMMENT_ID','$CR_ID','$NODE_RUN_ID');
SQL
# The carrier was seeded out-of-band, so restart to make the real daemon perform
# a fresh claim cycle instead of relying on a platform enqueue notification.
podman restart "$DAEMON_NAME" >/dev/null
{
  printf '$ real daemon registration and runtime owner binding\n'
  psql_at "SELECT id,daemon_id,name,provider,status,owner_id FROM agent_runtime WHERE id='$RUNTIME_ID';"
  printf '\n$ real executor\n'
  psql_at "SELECT id,workspace_id,name,runtime_id FROM agent WHERE id='$AGENT_ID';"
} > "$OUT/daemon-registration.stdout.txt" 2>&1
disk_free daemon_ready

echo '== [6/8] real claim -> trust-root delivery/install -> actual preflight outcome =='
POSITIVE_TASK_ID="$TASK_ID"
POSITIVE_CONSUMED=0
for i in $(seq 1 240); do
  COUNT="$(psql_at "SELECT count(*) FROM cr_execution_consumption WHERE workspace_id='$WORKSPACE_ID' AND cr_id='$CR_ID' AND task_id='$POSITIVE_TASK_ID'" 2>/dev/null || true)"
  if [ "$COUNT" = "1" ]; then POSITIVE_CONSUMED=1; break; fi
  STATUS="$(psql_at "SELECT status FROM agent_task_queue WHERE id='$POSITIVE_TASK_ID'" 2>/dev/null || true)"
  if [ "$STATUS" = "failed" ] || [ "$STATUS" = "completed" ] || [ "$STATUS" = "cancelled" ]; then break; fi
  if ! podman inspect -f '{{.State.Running}}' "$DAEMON_NAME" 2>/dev/null | grep -q true; then break; fi
  sleep 1
done
sleep 2
TRUST_ROOT="/root/.multica/execution-trust/$WORKSPACE_ID"
TRUST_DIR_HOST="$RUNNER_HOME/execution-trust/$WORKSPACE_ID/grants"
read -r GRANT_ID SCOPE_HASH SOURCE_EVENT_ID SOURCE_DIGEST <<< "$(node -e 'const fs=require("fs"),c=require("crypto");const t=fs.readFileSync(process.argv[1],"utf8").split("\nHTTP ")[0];const r=JSON.parse(t).record;const p=JSON.parse(Buffer.from(r.envelope.payload_b64,"base64"));const s=c.createHash("sha256").update(`execution-scope/v1\0${p.workspace_id}\0${p.project_id}\0${p.cr_id}`).digest("hex");console.log(p.grant_id,s,p.source_event_id,p.source_digest)' "$OUT_WIN/issue-authorization.stdout.txt")"
GRANT_NAME="$SCOPE_HASH-$GRANT_ID.execution-grant.json"
SOURCE_NAME="$SCOPE_HASH-$GRANT_ID.execution-source.json"
RECEIPT_NAME="$SCOPE_HASH-$GRANT_ID-authorization-bind.execution-receipt.json"
{
  printf '$ trust root and installed file metadata (no private key/token printed)\n'
  podman exec "$DAEMON_NAME" sh -c "if [ -d '$TRUST_ROOT' ]; then printf 'trust_root=%s\n' '$TRUST_ROOT'; find '$TRUST_ROOT' -maxdepth 3 -type f -print | sort; find '$TRUST_ROOT' -maxdepth 3 -type f -print0 | sort -z | xargs -0 -r sha256sum; else echo TRUST_ROOT_MISSING; fi"
  printf '\n$ workspace must not contain execution-trust material\n'
  podman exec "$DAEMON_NAME" sh -c "find /workspace -path '*/execution-trust*' -print"
  printf '\n$ real daemon log: claim / preparation / authorization / consumption\n'
  grep -iE 'picked task|claim|pipeline task preparation|EXECUTION_|authorization|grant|trust|consum' "$RUNNER_HOME/daemon.log" | tail -120 || true
  printf '\n$ real backend/proxy authorization delivery route\n'
  podman logs "$TLS_NAME" 2>&1 | grep -E 'execution-authorization|execution-claim' | tail -40 || true
} 2>&1 | tee "$OUT/trust-root-install.stdout.txt"
if [ "$POSITIVE_CONSUMED" -ne 1 ]; then
  printf 'Positive platform consumption was not observed.\n' | tee -a "$OUT/trust-root-install.stdout.txt"
  podman logs "$DAEMON_NAME" 2>&1 | tail -100 | tee -a "$OUT/trust-root-install.stdout.txt"
  exit 1
fi

{
  printf '$ real cr_execution_binding_issue row for the positive run\n'
  psql_at "SELECT id,workspace_id,cr_id,task_id,runtime_id,daemon_id,grant_digest,challenge,dispatched_at,created_at FROM cr_execution_binding_issue WHERE workspace_id='$WORKSPACE_ID' AND cr_id='$CR_ID' AND task_id='$POSITIVE_TASK_ID';"
  psql_at "SELECT envelope::text FROM cr_execution_binding_issue WHERE workspace_id='$WORKSPACE_ID' AND cr_id='$CR_ID' AND task_id='$POSITIVE_TASK_ID';" > "$TMPDIR_RUN/positive-binding-envelope.json"
  printf '\n$ signed payload decoded from that actual DB envelope\n'
  node -e 'const fs=require("fs");const e=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));const p=JSON.parse(Buffer.from(e.payload_b64,"base64"));console.log(JSON.stringify({schema:p.schema,key_id:p.key_id,workspace_id:p.workspace_id,project_id:p.project_id,cr_id:p.cr_id,operation:p.operation,challenge:p.challenge,install_root:p.install_root,operational_root:p.operational_root,head_digest:p.head_digest,authorization_revision:p.authorization_revision,runtime_id:p.runtime_id,task_id:p.task_id,daemon_id:p.daemon_id},null,2));if(p.operation!=="authorization-bind")process.exit(1)' "$TMP_WIN/positive-binding-envelope.json"
  printf '\n$ TLS proxy originals: daemon relay binding then platform consumption\n'
  podman logs "$TLS_NAME" 2>&1 | grep -E 'execution-authorization/(binding|consumption)' | tail -30 || true
  printf '\n$ daemon original lines for this task\n'
  grep -iE 'picked task|pipeline task preparation|EXECUTION_|authorization|consum|agent' "$RUNNER_HOME/daemon.log" | tail -120 || true
} 2>&1 | tee "$OUT/binding-relay.stdout.txt"

{
  printf '$ T-side receipt produced by requireControlAdmission/consumeExecutionAuthorization\n'
  printf 'receipt_path=%s/execution-consumptions/%s\n' "$TRUST_ROOT" "$RECEIPT_NAME"
  podman exec "$DAEMON_NAME" node -e 'const fs=require("fs");process.stdout.write(fs.readFileSync(process.argv[1],"utf8"))' "$TRUST_ROOT/execution-consumptions/$RECEIPT_NAME"
  printf '\n$ queue row after startup admission (agent may subsequently fail for provider reasons)\n'
  psql_at "SELECT id,status,dispatched_at,started_at,completed_at,coalesce(error,''),coalesce(failure_reason,'') FROM agent_task_queue WHERE id='$POSITIVE_TASK_ID';"
  printf '\n$ daemon log after the consumption gate\n'
  grep -iE 'picked task|pipeline task preparation|EXECUTION_|authorization|consum|starting|agent|provider|pi' "$RUNNER_HOME/daemon.log" | tail -140 || true
} 2>&1 | tee "$OUT/crctl-admission.stdout.txt"
cp "$RUNNER_HOME/daemon.log" "$TMPDIR_RUN/positive-daemon.log"
if grep -q 'EXECUTION_CONSUMPTION_REQUIRED' "$TMPDIR_RUN/positive-daemon.log"; then
  echo 'Positive run still emitted EXECUTION_CONSUMPTION_REQUIRED' >&2
  exit 1
fi
podman exec "$DAEMON_NAME" node -e 'const fs=require("fs");const r=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));if(r.operation!=="authorization-bind"||r.task_id!==process.argv[2]||!r.challenge||!r.receipt_id)process.exit(1);console.log(JSON.stringify({receipt_verified:true,operation:r.operation,stage:r.stage,task_id:r.task_id,challenge:r.challenge,receipt_id:r.receipt_id,changed_fact:"wx-created T receipt observed"},null,2))' "$TRUST_ROOT/execution-consumptions/$RECEIPT_NAME" "$POSITIVE_TASK_ID" >> "$OUT/crctl-admission.stdout.txt"

{
  printf '$ platform consumption row (actual table: cr_execution_consumption)\n'
  psql_at "SELECT id,workspace_id,cr_id,project_id,daemon_id,runtime_id,task_id,dispatched_at,grant_digest,challenge,created_at FROM cr_execution_consumption WHERE workspace_id='$WORKSPACE_ID' AND cr_id='$CR_ID' AND task_id='$POSITIVE_TASK_ID';"
  printf '\n$ positive consumption row count\n'
  psql_at "SELECT count(*) FROM cr_execution_consumption WHERE workspace_id='$WORKSPACE_ID' AND cr_id='$CR_ID' AND task_id='$POSITIVE_TASK_ID';"
  printf '\n$ exact T receipt content\n'
  podman exec "$DAEMON_NAME" node -e 'const fs=require("fs");process.stdout.write(fs.readFileSync(process.argv[1],"utf8"))' "$TRUST_ROOT/execution-consumptions/$RECEIPT_NAME"
} 2>&1 | tee "$OUT/db-consumption.stdout.txt"

task_status() { psql_at "SELECT status FROM agent_task_queue WHERE id='$1'" 2>/dev/null || true; }
wait_terminal() {
  local id="$1" status
  for _ in $(seq 1 180); do
    status="$(task_status "$id")"
    case "$status" in completed|failed|cancelled) printf '%s\n' "$status"; return 0;; esac
    if ! podman inspect -f '{{.State.Running}}' "$DAEMON_NAME" 2>/dev/null | grep -q true; then return 1; fi
    sleep 1
  done
  return 1
}
POSITIVE_STATUS="$(wait_terminal "$POSITIVE_TASK_ID")" || { echo 'positive task did not reach a terminal state'; exit 1; }
printf '\npositive_terminal_status=%s (post-admission agent outcome is separate)\n' "$POSITIVE_STATUS" | tee -a "$OUT/crctl-admission.stdout.txt"
disk_free positive

# Negative 1: delete only the disposable installed A packet so the real daemon
# delivers it again. A watcher changes one acceptance character immediately
# after installation; the signed grant and source digest/bindings stay old.
podman exec "$DAEMON_NAME" cp "$TRUST_ROOT/grants/$GRANT_NAME" /root/.multica/a-original-grant.json
podman exec "$DAEMON_NAME" cp "$TRUST_ROOT/grants/$SOURCE_NAME" /root/.multica/a-original-source.json
cat > "$RUNNER_HOME/tamper-source.js" <<'NODE'
const fs = require('fs');
const file = process.argv[2];
const record = JSON.parse(fs.readFileSync(file, 'utf8'));
const raw = Buffer.from(record.raw_b64, 'base64');
const before = raw.toString('utf8');
if (!before.includes('accepted_rules: allow-a')) throw new Error('expected acceptance not found');
const after = before.replace('accepted_rules: allow-a', 'accepted_rules: allow-b');
if (after.length !== before.length || after === before) throw new Error('not a one-character replacement');
record.raw_b64 = Buffer.from(after, 'utf8').toString('base64');
fs.writeFileSync(file, JSON.stringify(record));
fs.writeFileSync('/signals/tamper-facts.json', JSON.stringify({
  changed: 'accepted_rules: allow-a -> accepted_rules: allow-b',
  signed_digest_retained: record.digest,
  actual_tampered_sha256: require('crypto').createHash('sha256').update(after).digest('hex'),
  signature_modified: false,
}) + '\n');
NODE
cat > "$RUNNER_HOME/tamper-watch.sh" <<SH
#!/bin/sh
set -eu
while [ ! -f '$TRUST_ROOT/grants/$GRANT_NAME' ]; do sleep 0.005; done
node /root/.multica/tamper-source.js '$TRUST_ROOT/grants/$SOURCE_NAME'
touch /signals/tampered
SH
chmod +x "$RUNNER_HOME/tamper-watch.sh"
TAMPERED_TASK_ID="$(node -e "console.log(require('crypto').randomUUID())")"
podman exec "$DAEMON_NAME" rm -f "$TRUST_ROOT/grants/$GRANT_NAME" "$TRUST_ROOT/grants/$SOURCE_NAME" /signals/tampered /signals/tamper-facts.json
CONTEXT_JSON="$(node -e "const p=require('$TMP_WIN/pipeline-context.json');process.stdout.write(JSON.stringify(p.context))")"
podman exec -d "$DAEMON_NAME" sh /root/.multica/tamper-watch.sh
psql_q <<SQL
INSERT INTO agent_task_queue (id,agent_id,runtime_id,issue_id,project_id,status,priority,context,originator_user_id,accountable_user_id,originator_source,trigger_comment_id,cr_id,pipeline_node_run_id)
VALUES ('$TAMPERED_TASK_ID','$AGENT_ID','$RUNTIME_ID','$ISSUE_ID','$PROJECT_ID','queued',0,'$CONTEXT_JSON'::jsonb,'$USER_ID','$USER_ID','direct_human','$COMMENT_ID','$CR_ID','$NODE_RUN_ID');
SQL
TAMPERED_STATUS="$(wait_terminal "$TAMPERED_TASK_ID")" || { echo 'tampered task did not terminate'; exit 1; }
{
  printf 'REAL NEGATIVE: one acceptance character changed after real daemon delivery; grant/signature/source digest retained.\n'
  printf 'task_id=%s status=%s\n' "$TAMPERED_TASK_ID" "$TAMPERED_STATUS"
  printf '\n$ exact tamper facts\n'
  podman exec "$DAEMON_NAME" node -e 'process.stdout.write(require("fs").readFileSync("/signals/tamper-facts.json","utf8"))'
  printf '\n$ real queue error (T refusal propagated by daemon)\n'
  psql_at "SELECT id,status,coalesce(error,''),coalesce(failure_reason,'') FROM agent_task_queue WHERE id='$TAMPERED_TASK_ID';"
  printf '\n$ real daemon/T original log lines\n'
  grep -iE 'EXECUTION_SOURCE_INVALID|EXECUTION_CONSUMPTION_REQUIRED|pipeline task preparation|picked task' "$RUNNER_HOME/daemon.log" | tail -100 || true
  printf '\n$ negative side effects: platform consumption and T receipts for this run\n'
  psql_at "SELECT count(*) AS platform_consumption_for_tampered_task FROM cr_execution_consumption WHERE task_id='$TAMPERED_TASK_ID';"
  printf 'binding_issue_count_for_tampered_task='
  psql_at "SELECT count(*) FROM cr_execution_binding_issue WHERE task_id='$TAMPERED_TASK_ID';"
  printf 'receipt_files_now='
  podman exec "$DAEMON_NAME" sh -c "find '$TRUST_ROOT/execution-consumptions' -maxdepth 1 -type f -name '*authorization-bind*' | wc -l | tr -d ' '"
} 2>&1 | tee "$OUT/negative-tampered.stdout.txt"
grep -q 'EXECUTION_SOURCE_INVALID' "$OUT/negative-tampered.stdout.txt" || { echo 'real tampered refusal code not observed'; exit 1; }
[ "$(psql_at "SELECT count(*) FROM cr_execution_consumption WHERE task_id='$TAMPERED_TASK_ID'")" = "0" ] || { echo 'tampered task unexpectedly consumed'; exit 1; }
disk_free negative_tampered

# Create project B and obtain B's packet through the same real signing service,
# real daemon delivery and non-read-only admission. This is setup material for
# the cross-project negative, not a locally fabricated grant.
CR_ID_B="CR-2026-993"
mkdir -p "$TMP_WIN/workspace/change-requests/$CR_ID_B"
cat > "$TMP_WIN/workspace/change-requests/$CR_ID_B/cr.md" <<CRMD
---
id: $CR_ID_B
title: M2 cross-project donor
status: writing-back
execution-contract: authorized-execution/v1
---
# M2 cross-project donor
CRMD
TMP_WIN_M="$TMP_WIN" DAEMON_ID_M="$DAEMON_ID" CR_ID_B_M="$CR_ID_B" NONCE_M="$NONCE" node - <<'NODE'
const crypto = require('crypto');
const fs = require('fs');
const uuid = () => crypto.randomUUID();
const ids = { project_id: uuid(), issue_id: uuid(), resource_id: uuid(), run_id: uuid(), node_run_id: uuid(), comment_id: uuid(), task_id: uuid(), cr_id: process.env.CR_ID_B_M };
const old = JSON.parse(fs.readFileSync(process.env.TMP_WIN_M + '/ids.json', 'utf8'));
Object.assign(ids, { workspace_id: old.workspace_id, user_id: old.user_id });
const ref = { local_path: '/workspace', daemon_id: process.env.DAEMON_ID_M, kind: 'm2_real_root_b', execution_mode: 'in_place' };
const identity = { daemon_id: process.env.DAEMON_ID_M, local_path: '/workspace', execution_mode: 'in_place' };
const projection = { resource_id: ids.resource_id, workspace_id: ids.workspace_id, project_id: ids.project_id, resource_type: 'local_directory', identity_b64: Buffer.from(JSON.stringify(identity)).toString('base64') };
ids.resource_ref = ref;
ids.binding_digest = crypto.createHash('sha256').update('project-resource-binding/v1\0').update(JSON.stringify(projection)).digest('hex');
fs.writeFileSync(process.env.TMP_WIN_M + '/ids-b.json', JSON.stringify(ids, null, 2));
const strictComment = ['run this archive node', '', '```yaml', 'context:', '  execution:', '    contract: authorized-execution/v1', '```', ''].join('\n');
const context = { type: 'pipeline_node', schema: 'ai-first.pipeline-task/v1', workspace_id: ids.workspace_id, cr_id: ids.cr_id, run_id: ids.run_id, node_id: '00000000-0000-0000-0013-000000000005', pipeline_id: 'feature-writeback', attempt: 1, prompt: 'real daemon cross-project donor' };
fs.writeFileSync(process.env.TMP_WIN_M + '/pipeline-context-b.json', JSON.stringify(context));
fs.writeFileSync(process.env.TMP_WIN_M + '/seed-b.sql', `
INSERT INTO project (id,workspace_id,title) VALUES ('${ids.project_id}','${ids.workspace_id}','M2 project B');
INSERT INTO issue (id,workspace_id,project_id,title,creator_type,creator_id,number) VALUES ('${ids.issue_id}','${ids.workspace_id}','${ids.project_id}','M2 shell B','member','${ids.user_id}',2);
INSERT INTO project_resource (id,workspace_id,project_id,resource_type,resource_ref,label) VALUES ('${ids.resource_id}','${ids.workspace_id}','${ids.project_id}','local_directory','${JSON.stringify(ref)}'::jsonb,'M2 real root B');
INSERT INTO cr (workspace_id,cr_id,title,status,shell_issue_id) VALUES ('${ids.workspace_id}','${ids.cr_id}','M2 cross project donor','writing-back','${ids.issue_id}');
INSERT INTO comment (id,workspace_id,issue_id,author_type,author_id,content) VALUES ('${ids.comment_id}','${ids.workspace_id}','${ids.issue_id}','member','${ids.user_id}','${strictComment}');
INSERT INTO pipeline_run (id,workspace_id,pipeline_id,cr_id,issue_id,status,inputs,execution_context,started_by)
VALUES ('${ids.run_id}','${ids.workspace_id}','feature-writeback','${ids.cr_id}','${ids.issue_id}','running','{"cr_id":"${ids.cr_id}"}'::jsonb,'{"template_digest":"sha256:6a63a222146eb018564cd0487e8b1ab5352f832fd3d972f6c065ff7010c01108"}'::jsonb,'${ids.user_id}');
INSERT INTO pipeline_node_run (id,run_id,node_id,ref,kind,seq,status,attempt)
VALUES ('${ids.node_run_id}','${ids.run_id}','00000000-0000-0000-0013-000000000005','cr-archive','skill',5,'running',1);
`);
NODE
psql_q < "$TMPDIR_RUN/seed-b.sql"
read -r PROJECT_ID_B ISSUE_ID_B RESOURCE_ID_B BINDING_DIGEST_B RUN_ID_B NODE_RUN_ID_B COMMENT_ID_B TASK_ID_B <<< "$(node -e "const i=require('$TMP_WIN/ids-b.json'); console.log(i.project_id,i.issue_id,i.resource_id,i.binding_digest,i.run_id,i.node_run_id,i.comment_id,i.task_id)")"
IDS_FILE="$TMP_WIN/ids-b.json" SOURCE_FILE="$TMP_WIN/source-request-b.json" node - <<'NODE'
const fs = require('fs');
const ids = JSON.parse(fs.readFileSync(process.env.IDS_FILE, 'utf8'));
const selection = { resource_id: ids.resource_id, binding_digest: ids.binding_digest };
const body = { goal: 'M2 real cross-project donor', scope_revision: 1,
  allowed_repositories: ['kb'], allowed_paths: { kb: ['change-requests'] },
  delivery_targets: ['review branch'], acceptance: ['accepted_rules: allow-b'],
  prohibitions: ['no production'], sensitive_actions: [], policy_version: 'authorized-execution/v1',
  policy_digest: 'a'.repeat(64), template_digest: 'b'.repeat(64), target_version: 'v1.0.0',
  target_spec_id: 'm2-real-loop-b', repair_limit: 1,
  repository_selections: { kb: selection }, coordinator_selection: selection };
fs.writeFileSync(process.env.SOURCE_FILE, JSON.stringify(body, null, 2));
NODE
SOURCE_BODY_B="$(cat "$TMPDIR_RUN/source-request-b.json")"
api POST "/api/workspaces/$WORKSPACE_ID/crs/$CR_ID_B/execution-authorization" "$SOURCE_BODY_B" | tee "$OUT/issue-cross-project.stdout.txt"
grep -q '^HTTP 201' "$OUT/issue-cross-project.stdout.txt" || { echo 'project B authorization did not return 201'; exit 1; }
read -r GRANT_ID_B SCOPE_HASH_B KEY_ID_B <<< "$(node -e 'const fs=require("fs"),c=require("crypto");const t=fs.readFileSync(process.argv[1],"utf8").split("\nHTTP ")[0];const r=JSON.parse(t).record;const p=JSON.parse(Buffer.from(r.envelope.payload_b64,"base64"));const s=c.createHash("sha256").update(`execution-scope/v1\0${p.workspace_id}\0${p.project_id}\0${p.cr_id}`).digest("hex");console.log(p.grant_id,s,r.envelope.key_id)' "$OUT_WIN/issue-cross-project.stdout.txt")"
GRANT_NAME_B="$SCOPE_HASH_B-$GRANT_ID_B.execution-grant.json"
CONTEXT_JSON_B="$(node -e "process.stdout.write(JSON.stringify(require('$TMP_WIN/pipeline-context-b.json')))")"
psql_q <<SQL
INSERT INTO agent_task_queue (id,agent_id,runtime_id,issue_id,project_id,status,priority,context,originator_user_id,accountable_user_id,originator_source,trigger_comment_id,cr_id,pipeline_node_run_id)
VALUES ('$TASK_ID_B','$AGENT_ID','$RUNTIME_ID','$ISSUE_ID_B','$PROJECT_ID_B','queued',0,'$CONTEXT_JSON_B'::jsonb,'$USER_ID','$USER_ID','direct_human','$COMMENT_ID_B','$CR_ID_B','$NODE_RUN_ID_B');
SQL
B_CONSUMED=0
for _ in $(seq 1 240); do
  [ "$(psql_at "SELECT count(*) FROM cr_execution_consumption WHERE task_id='$TASK_ID_B'" 2>/dev/null || true)" = "1" ] && { B_CONSUMED=1; break; }
  STATUS_B="$(task_status "$TASK_ID_B")"
  case "$STATUS_B" in failed|completed|cancelled) break;; esac
  sleep 1
done
[ "$B_CONSUMED" -eq 1 ] || { podman logs "$DAEMON_NAME" 2>&1 | tail -100; echo 'project B donor was not admitted'; exit 1; }
B_STATUS="$(wait_terminal "$TASK_ID_B")" || { echo 'project B donor did not terminate'; exit 1; }
podman exec "$DAEMON_NAME" test -f "$TRUST_ROOT/grants/$GRANT_NAME_B" || { echo 'real daemon did not install project B grant'; exit 1; }
podman exec "$DAEMON_NAME" cp "$TRUST_ROOT/grants/$GRANT_NAME_B" /root/.multica/cross-b-grant.json
{
  printf '\n$ project B donor was really signed/delivered/consumed (cross-project setup)\n'
  printf 'project_b=%s cr_b=%s grant_b=%s donor_status=%s\n' "$PROJECT_ID_B" "$CR_ID_B" "$GRANT_NAME_B" "$B_STATUS"
  psql_at "SELECT id,cr_id,project_id,task_id,grant_digest,challenge FROM cr_execution_consumption WHERE task_id='$TASK_ID_B';"
} 2>&1 | tee -a "$OUT/db-consumption.stdout.txt"

# Negative 2: static --check sees freshly delivered A. After the real platform
# commits A's binding, the proxy holds the unchanged response for 750ms; the
# watcher swaps A's grant file to same-key B. T's pre-write CAS re-read must reject.
cat > "$RUNNER_HOME/cross-watch.sh" <<SH
#!/bin/sh
set -eu
while [ ! -f '$TRUST_ROOT/grants/$GRANT_NAME' ]; do sleep 0.005; done
while [ ! -f /signals/binding-returned ]; do sleep 0.002; done
cp /root/.multica/cross-b-grant.json '$TRUST_ROOT/grants/$GRANT_NAME'
touch /signals/cross-swapped
SH
chmod +x "$RUNNER_HOME/cross-watch.sh"
CROSS_TASK_ID="$(node -e "console.log(require('crypto').randomUUID())")"
podman exec "$DAEMON_NAME" rm -f "$TRUST_ROOT/grants/$GRANT_NAME" "$TRUST_ROOT/grants/$SOURCE_NAME" /signals/binding-returned /signals/cross-swapped
podman exec "$TLS_NAME" rm -f /signals/binding-returned /signals/cross-swapped
podman exec "$TLS_NAME" touch /signals/arm-cross
podman exec -d "$DAEMON_NAME" sh /root/.multica/cross-watch.sh
psql_q <<SQL
INSERT INTO agent_task_queue (id,agent_id,runtime_id,issue_id,project_id,status,priority,context,originator_user_id,accountable_user_id,originator_source,trigger_comment_id,cr_id,pipeline_node_run_id)
VALUES ('$CROSS_TASK_ID','$AGENT_ID','$RUNTIME_ID','$ISSUE_ID','$PROJECT_ID','queued',0,'$CONTEXT_JSON'::jsonb,'$USER_ID','$USER_ID','direct_human','$COMMENT_ID','$CR_ID','$NODE_RUN_ID');
SQL
CROSS_STATUS="$(wait_terminal "$CROSS_TASK_ID")" || { echo 'cross-project task did not terminate'; exit 1; }
{
  printf 'REAL NEGATIVE: valid same-key project B grant replaced A grant after real A binding issuance and before T consumption CAS.\n'
  printf 'task_id=%s status=%s project_a=%s project_b=%s cr_a=%s cr_b=%s key_b=%s\n' "$CROSS_TASK_ID" "$CROSS_STATUS" "$PROJECT_ID" "$PROJECT_ID_B" "$CR_ID" "$CR_ID_B" "$KEY_ID_B"
  printf 'cross_swap_observed='; if podman exec "$DAEMON_NAME" test -f /signals/cross-swapped; then echo true; else echo false; fi
  printf '\n$ real queue error (T refusal propagated by daemon)\n'
  psql_at "SELECT id,status,coalesce(error,''),coalesce(failure_reason,'') FROM agent_task_queue WHERE id='$CROSS_TASK_ID';"
  printf '\n$ real daemon/T original log lines\n'
  grep -iE 'EXECUTION_GRANT_SCOPE_MISMATCH|EXECUTION_CONSUMPTION_REQUIRED|pipeline task preparation|picked task' "$RUNNER_HOME/daemon.log" | tail -120 || true
  printf '\n$ proxy proves unchanged real binding response was delayed, not replaced\n'
  podman logs "$TLS_NAME" 2>&1 | grep -E 'execution-authorization/(binding|consumption)' | tail -30 || true
  printf '\n$ negative side effects\n'
  psql_at "SELECT count(*) AS platform_consumption_for_cross_project_task FROM cr_execution_consumption WHERE task_id='$CROSS_TASK_ID';"
  printf 'binding_issue_count_for_cross_project_task='
  psql_at "SELECT count(*) FROM cr_execution_binding_issue WHERE task_id='$CROSS_TASK_ID';"
  printf 'receipt_files_now='
  podman exec "$DAEMON_NAME" sh -c "find '$TRUST_ROOT/execution-consumptions' -maxdepth 1 -type f -name '*authorization-bind*' | wc -l | tr -d ' '"
} 2>&1 | tee "$OUT/negative-cross-project.stdout.txt"
grep -q 'EXECUTION_GRANT_SCOPE_MISMATCH' "$OUT/negative-cross-project.stdout.txt" || { echo 'real cross-project refusal code not observed'; exit 1; }
podman exec "$DAEMON_NAME" test -f /signals/cross-swapped || { echo 'cross-project swap did not occur'; exit 1; }
[ "$(psql_at "SELECT count(*) FROM cr_execution_consumption WHERE task_id='$CROSS_TASK_ID'")" = "0" ] || { echo 'cross-project task unexpectedly consumed'; exit 1; }
podman exec "$TLS_NAME" rm -f /signals/arm-cross
disk_free negative_cross_project

IMAGE_ID="$(podman image inspect "$BACKEND_IMAGE" --format '{{.Id}}')"
FINAL_COUNTS="$(psql_at "SELECT (SELECT count(*) FROM cr_execution_consumption WHERE workspace_id='$WORKSPACE_ID'),(SELECT count(*) FROM cr_execution_binding_issue WHERE workspace_id='$WORKSPACE_ID')")"
RUN_STATUS="passed-real-bind-and-two-real-negatives"
OUT_WIN_M="$OUT_WIN" RUN_STATUS_M="$RUN_STATUS" BACKEND_IMAGE_M="$BACKEND_IMAGE" IMAGE_ID_M="$IMAGE_ID" \
  SOURCE_EVENT_ID_M="$SOURCE_EVENT_ID" SOURCE_DIGEST_M="$SOURCE_DIGEST" WORKSPACE_ID_M="$WORKSPACE_ID" PROJECT_ID_M="$PROJECT_ID" PROJECT_ID_B_M="$PROJECT_ID_B" \
  CR_ID_M="$CR_ID" CR_ID_B_M="$CR_ID_B" POSITIVE_TASK_ID_M="$POSITIVE_TASK_ID" TAMPERED_TASK_ID_M="$TAMPERED_TASK_ID" CROSS_TASK_ID_M="$CROSS_TASK_ID" \
  RUNTIME_ID_M="$RUNTIME_ID" TRUST_ROOT_M="$TRUST_ROOT" FINAL_COUNTS_M="$FINAL_COUNTS" node - <<'NODE'
const fs = require('fs');
const e = process.env;
const facts = {
  schema: 'aifi45-m2-real-loop-facts/v2', measured_at: new Date().toISOString(), result: e.RUN_STATUS_M,
  image: { tag: e.BACKEND_IMAGE_M, id: e.IMAGE_ID_M, cleanup: 'trap podman image rm -f; see image-cleanup.stdout.txt' },
  authorization: { source_event_id: e.SOURCE_EVENT_ID_M, source_digest: e.SOURCE_DIGEST_M, workspace_id: e.WORKSPACE_ID_M, project_id: e.PROJECT_ID_M, cr_id: e.CR_ID_M },
  positive: { task_id: e.POSITIVE_TASK_ID_M, runtime_id: e.RUNTIME_ID_M, real_non_readonly_bind: true, require_control_admission: true, t_receipt: true, platform_consumption: true, startup_consumption_required: false },
  negatives: { tampered: { task_id: e.TAMPERED_TASK_ID_M, code: 'EXECUTION_SOURCE_INVALID', platform_consumption_rows: 0 }, cross_project: { task_id: e.CROSS_TASK_ID_M, donor_project_id: e.PROJECT_ID_B_M, donor_cr_id: e.CR_ID_B_M, code: 'EXECUTION_GRANT_SCOPE_MISMATCH', platform_consumption_rows: 0 } },
  final_consumption_and_binding_counts: e.FINAL_COUNTS_M.trim(),
  trust_root: e.TRUST_ROOT_M,
  boundary: 'Disposable same-UID containers, self-signed CA and seeded initial workspace/project/CR/queue carriers. Positive proves authorization-bind admission and its existing consumption write, not advance/repair/register/archive. B donor admission is setup for the real cross-project negative.',
};
fs.writeFileSync(e.OUT_WIN_M + '/run-facts.json', JSON.stringify(facts, null, 2) + '\n');
NODE

cat > "$OUT/README.md" <<EOF
# AIFI-45 M2 真实跨端闭环复跑（四条件启动门）

## 结论

**本次目标链走通**：真实 daemon 在当前 head、未撤销、claim 一致后，亲启非只读
\`authorization-bind --binding-stdio\`，T 的 \`requireControlAdmission\` 通过既有消费写事务生成
receipt，平台 \`cr_execution_consumption\` 写入对应行，daemon 未再因
\`EXECUTION_CONSUMPTION_REQUIRED\` 停住。两条后续真实 task 负例分别得到 T 的
\`EXECUTION_SOURCE_INVALID\` 与 \`EXECUTION_GRANT_SCOPE_MISMATCH\`，平台消费均为 0 行。

- A source_event_id：\`$SOURCE_EVENT_ID\`
- A source_digest：\`$SOURCE_DIGEST\`
- A project / CR：\`$PROJECT_ID\` / \`$CR_ID\`
- B donor project / CR：\`$PROJECT_ID_B\` / \`$CR_ID_B\`
- 镜像：\`$BACKEND_IMAGE\`
- 镜像 ID：\`$IMAGE_ID\`
- 镜像清理由 EXIT trap 强制执行；结果见 \`image-cleanup.stdout.txt\` 与 \`podman-ps-after.stdout.txt\`。

## 箭头与证据

| 箭头 / 事实 | 真实结果 | 证据 |
|---|---|---|
| 当前源码（白名单 + 四条件门）→ 强制新镜像 | 真实，\`podman build --rm\` | \`build.stdout.txt\` |
| tmpfs PG → 真迁移 → HTTPS health | 真实 | \`migrate.stdout.txt\`, \`health.stdout.txt\` |
| 原 structured-human-request bytes → 真实签发 | 真实，A/B 均 HTTP 201、同一签名服务 | \`issue-authorization.stdout.txt\`, \`issue-cross-project.stdout.txt\` |
| DB 归属 / source_event_id / 原 bytes digest / bindings | 真实 | \`db-grant-row.stdout.txt\` |
| daemon GET → daemon-owned trust root → 静态 check | 真实 | \`trust-root-install.stdout.txt\` |
| daemon stdio relay → 非只读 authorization-bind | 真实，签名 operation 为 authorization-bind | \`binding-relay.stdout.txt\` |
| T requireControlAdmission → 既有消费写事务 | 真实，T receipt 含 operation/stage/challenge/task/receipt_id | \`crctl-admission.stdout.txt\` |
| 平台消费事实 | 真实，A 正例 1 行；B donor 1 行；两负例各 0 行 | \`db-consumption.stdout.txt\` |
| daemon 启动门 | 真实放行；正例日志无 EXECUTION_CONSUMPTION_REQUIRED，后续 agent 成败不属于准入门 | \`crctl-admission.stdout.txt\` |
| acceptance 改一个字符、旧签名 | 真实拒绝 \`EXECUTION_SOURCE_INVALID\` | \`negative-tampered.stdout.txt\` |
| 同 key 的 project B grant 替换 A | 真实拒绝 \`EXECUTION_GRANT_SCOPE_MISMATCH\` | \`negative-cross-project.stdout.txt\` |
| 容器/网络/tmp 文件/本次镜像销毁 | trap 真实执行 | \`podman-ps-after.stdout.txt\`, \`image-cleanup.stdout.txt\` |

## 负例构造边界

篡改例在真实 daemon 重新投递 A 后修改 source sidecar 内原始请求 bytes 的
\`accepted_rules: allow-a\` 为 \`allow-b\`，保留 grant、签名、digest 与 bindings；真实 T 在非只读
准入验源时拒绝。跨 project 例先让 B 经真实签发/投递/准入取得材料；A 的静态 check 和平台 binding
均真实完成后，临时代理仅延迟未修改的响应 750ms，watcher 将 A grant 文件替换为同 key B grant，
T 消费前 CAS 重读拒绝。没有伪造路由、签名、receipt、DB 行，也没有宿主直接启动 crctl 替代 daemon。

## 边界

一次性实例、自签 CA、同 UID 容器及 seed 的初始 workspace/project/CR/pipeline 队列不等于生产部署、
生产信任链或 Runner 完整业务分发证据。正例只覆盖 authorization-bind 的既有消费事务，没有声称
advance 或修复/注册/归档业务事务已跑。后续 agent provider 的成功与否不改变启动准入事实。

## TC-TAC-001..010：本次没有一条可单独据此升整条

| TC | 能否升整条 | 本次补强与仍缺内容 |
|---|---|---|
| TC-TAC-001 | 否 | 已有真实 bind/receipt/consumption；仍缺真实 advance、全部 AND 与完整业务/零副作用矩阵。 |
| TC-TAC-002 | 否 | 已有同 key B→A 的真实 bind 拒绝；仍缺两个首次写入口/五入口、整根复制及全量零副作用。 |
| TC-TAC-003 | 否 | 未跑 env/sidecar/endpoint/路径 pin/坏 key/根包含等伪造矩阵。 |
| TC-TAC-004 | 否 | 真实篡改拒绝已补强；仍缺机器凭据/错误 actor、跨 DB project 拒签及对应 DB 零变化。 |
| TC-TAC-005 | 否 | 本次没有不同 OS/UID/SID 的内核写拒绝；不能补 Windows 或部署隔离。 |
| TC-TAC-006 | 否 | 未跑旧 head、撤销、失联、恢复、普通读与重放完整矩阵。 |
| TC-TAC-007 | 否 | repair-admit/resume 正例、预算/origin/stop 与崩溃恢复未跑。 |
| TC-TAC-008 | 否 | repair/resume 负例矩阵未跑。 |
| TC-TAC-009 | 否 | registration key、register/archive 正例与重放未跑。 |
| TC-TAC-010 | 否 | register/archive 负例与零副作用未跑。 |

因此本证据不支持生产启用或 ADJ-AIFI45-001/002/003 自动关闭。
EOF

printf '== [8/8] %s ==\n' "$RUN_STATUS"
disk_free before_cleanup
exit 0

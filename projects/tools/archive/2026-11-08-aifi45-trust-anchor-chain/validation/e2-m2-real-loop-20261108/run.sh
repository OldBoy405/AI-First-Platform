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
  "$OUT/daemon.log.txt" "$OUT/negative-tampered.stdout.txt" "$OUT/negative-cross-project.stdout.txt"
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

manifest() {
  set +e
  RUN_STATUS="$RUN_STATUS" BLOCKER="$BLOCKER" OUT_WIN_M="$OUT_WIN" BACKEND_IMAGE_M="$BACKEND_IMAGE" node - <<'NODE'
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const out = process.env.OUT_WIN_M;
const names = [
  'run.sh', 'build.stdout.txt', 'migrate.stdout.txt', 'health.stdout.txt',
  'issue-authorization.stdout.txt', 'db-grant-row.stdout.txt',
  'trust-root-install.stdout.txt', 'crctl-admission.stdout.txt',
  'negative-tampered.stdout.txt', 'negative-cross-project.stdout.txt',
  'podman-ps-after.stdout.txt', 'run-facts.json', 'README.md',
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
  set +e
  if [ -n "${RUNNER_HOME:-}" ] && [ -f "$RUNNER_HOME/daemon.log" ]; then cp "$RUNNER_HOME/daemon.log" "$OUT/daemon.log.txt"; fi
  podman logs "$DAEMON_NAME" > "$OUT/daemon-container.log.txt" 2>&1
  podman logs "$BACKEND_NAME" > "$OUT/backend.log.txt" 2>&1
  podman logs "$TLS_NAME" > "$OUT/tls-proxy.log.txt" 2>&1
  podman rm -f "$DAEMON_NAME" "$TLS_NAME" "$BACKEND_NAME" "$PG_NAME" >/dev/null 2>&1
  podman network rm "$NET_NAME" >/dev/null 2>&1
  rm -rf "$TMPDIR_RUN"
  podman ps -a --format '{{.Names}}\t{{.Status}}\t{{.Image}}' > "$OUT/podman-ps-after.stdout.txt" 2>&1
  podman images --digests --format '{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Digest}}' | grep -F "$BACKEND_IMAGE" >> "$OUT/podman-ps-after.stdout.txt" 2>&1
  manifest
}
trap cleanup EXIT

podman ps -a --format '{{.Names}}\t{{.Status}}\t{{.Image}}' > "$OUT/podman-ps-before.stdout.txt"
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
    printf '$ podman build --pull=never -t %s -f Dockerfile .\n' "$BACKEND_IMAGE"
    printf 'source_HEAD=%s\n' "$(git rev-parse HEAD)"
    printf 'source_dirty_entries=%s\n' "$(git status --porcelain | wc -l | tr -d ' ')"
    podman build --pull=never \
      --build-arg "VERSION=m2-$NONCE" --build-arg "COMMIT=$(git rev-parse HEAD)" \
      -t "$BACKEND_IMAGE" -f Dockerfile .
    printf 'build_exit=0\n'
    printf '\n$ podman image inspect %s --format {{.Id}}\n' "$BACKEND_IMAGE"
    podman image inspect "$BACKEND_IMAGE" --format '{{.Id}}'
    printf '\n$ podman images (exact tag)\n'
    podman images --digests --format '{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Digest}}' | grep -F "$BACKEND_IMAGE"
  } 2>&1 | tee "$OUT/build.stdout.txt"
)

echo '== [2/8] disposable network / CA / tmpfs PG / real migrations =='
cat > "$TMPDIR_RUN/tlsproxy.go" <<'GO'
package main
import (
  "flag"
  "log"
  "net/http"
  "net/http/httputil"
  "net/url"
)
func main() {
  listen := flag.String("listen", ":8443", "listen")
  target := flag.String("target", "http://backend:8080", "target")
  cert := flag.String("cert", "/certs/server.crt", "cert")
  key := flag.String("key", "/certs/server.key", "key")
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
  -v "$TMP_WIN/pki:/certs:ro" --entrypoint /usr/local/bin/tlsproxy "$NODE_IMAGE" \
  --listen :8443 --target http://backend:8080 --cert /certs/server.crt --key /certs/server.key >/dev/null
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
  -v "$TMP_WIN/workspace:/workspace" \
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

echo '== [6/8] real claim -> trust-root delivery/install -> actual preflight outcome =='
OBSERVED=0
for i in $(seq 1 240); do
  if grep -q 'EXECUTION_CONSUMPTION_REQUIRED' "$RUNNER_HOME/daemon.log" 2>/dev/null; then OBSERVED=1; break; fi
  STATUS="$(psql_at "SELECT status FROM agent_task_queue WHERE id='$TASK_ID'" 2>/dev/null || true)"
  if [ "$STATUS" = "failed" ] || [ "$STATUS" = "completed" ] || [ "$STATUS" = "cancelled" ]; then OBSERVED=1; break; fi
  if ! podman inspect -f '{{.State.Running}}' "$DAEMON_NAME" 2>/dev/null | grep -q true; then break; fi
  sleep 1
done
sleep 3
TRUST_ROOT="/root/.multica/execution-trust/$WORKSPACE_ID"
{
  printf '$ trust root and installed file metadata (no key/source/grant contents printed)\n'
  podman exec "$DAEMON_NAME" sh -c "if [ -d '$TRUST_ROOT' ]; then printf 'trust_root=%s\n' '$TRUST_ROOT'; find '$TRUST_ROOT' -maxdepth 2 -type f -print | sort; find '$TRUST_ROOT' -maxdepth 2 -type f -print0 | sort -z | xargs -0 -r sha256sum; else echo TRUST_ROOT_MISSING; fi"
  printf '\n$ workspace must not contain execution-trust material\n'
  podman exec "$DAEMON_NAME" sh -c "find /workspace -path '*/execution-trust*' -print"
  printf '\n$ real daemon log: claim / preparation / consumption gate\n'
  grep -iE 'picked task|claim|pipeline task preparation|EXECUTION_|authorization|grant|trust' "$RUNNER_HOME/daemon.log" | tail -100 || true
  printf '\n$ real backend/proxy authorization delivery route\n'
  podman logs "$TLS_NAME" 2>&1 | grep -E 'execution-authorization|execution-claim' | tail -30 || true
} 2>&1 | tee "$OUT/trust-root-install.stdout.txt"
[ "$OBSERVED" -eq 1 ] || {
  printf 'No terminal preflight observation within timeout\n' | tee -a "$OUT/trust-root-install.stdout.txt"
  podman logs "$DAEMON_NAME" 2>&1 | tail -100 | tee -a "$OUT/trust-root-install.stdout.txt"
  exit 1
}

echo '== [7/8] record actual stop; do not fabricate control admission or negatives =='
RUN_STATUS="blocked-before-control-admission"
BLOCKER="daemon prepareClaimedPipelineTask returned EXECUTION_CONSUMPTION_REQUIRED after trust installation and crctl --check; no binding challenge or business write was reached"
{
  printf 'OBSERVED BLOCKER: %s\n\n' "$BLOCKER"
  printf '$ daemon log excerpt (original lines)\n'
  grep -iE 'picked task|pipeline task preparation|EXECUTION_|authorization|grant|trust' "$RUNNER_HOME/daemon.log" | tail -120 || true
  printf '\n$ real queue terminal row\n'
  psql_at "SELECT id,status,dispatched_at,started_at,completed_at,coalesce(error,''),coalesce(failure_reason,'') FROM agent_task_queue WHERE id='$TASK_ID';"
  printf '\n$ binding/consumption/business facts after the stop\n'
  psql_at "SELECT 'binding_issue',count(*) FROM cr_execution_binding_issue WHERE workspace_id='$WORKSPACE_ID' AND cr_id='$CR_ID' UNION ALL SELECT 'platform_consumption',count(*) FROM cr_execution_consumption WHERE workspace_id='$WORKSPACE_ID' AND cr_id='$CR_ID';"
  printf '\n$ CR file bytes / Git and receipts after the stop\n'
  podman exec "$DAEMON_NAME" sh -c "sha256sum '/workspace/change-requests/$CR_ID/cr.md'; if [ -d /workspace/.git ]; then git -C /workspace rev-parse HEAD; git -C /workspace status --porcelain=v1; else echo NO_GIT_REPOSITORY_SEEDED; fi; find '$TRUST_ROOT/execution-consumptions' -maxdepth 2 -type f -print 2>/dev/null || true"
} 2>&1 | tee "$OUT/crctl-admission.stdout.txt"
for name in negative-tampered negative-cross-project; do
  {
    printf 'NOT RUN — prerequisite positive control admission was not reached.\n'
    printf 'Observed blocker: %s\n' "$BLOCKER"
    printf 'No local source rewrite, grant copy, fake binding endpoint, or host-spawned crctl was substituted for the real daemon child.\n'
  } > "$OUT/$name.stdout.txt"
done
cp "$RUNNER_HOME/daemon.log" "$OUT/daemon.log.txt" 2>/dev/null || true

SOURCE_EVENT_ID="$(node -e 'const fs=require("fs");const t=fs.readFileSync(process.argv[1],"utf8").split("\nHTTP ")[0];const r=JSON.parse(t).record;const p=JSON.parse(Buffer.from(r.envelope.payload_b64,"base64"));console.log(p.source_event_id)' "$OUT_WIN/issue-authorization.stdout.txt")"
SOURCE_DIGEST="$(node -e 'const fs=require("fs");const t=fs.readFileSync(process.argv[1],"utf8").split("\nHTTP ")[0];const r=JSON.parse(t).record;const p=JSON.parse(Buffer.from(r.envelope.payload_b64,"base64"));console.log(p.source_digest)' "$OUT_WIN/issue-authorization.stdout.txt")"
BINDING_COUNT="$(node -e 'const fs=require("fs");const t=fs.readFileSync(process.argv[1],"utf8").split("\nHTTP ")[0];console.log(Object.keys(JSON.parse(t).record.source.bindings).length)' "$OUT_WIN/issue-authorization.stdout.txt")"
TASK_STATUS="$(psql_at "SELECT status FROM agent_task_queue WHERE id='$TASK_ID'")"
IMAGE_ID="$(podman image inspect "$BACKEND_IMAGE" --format '{{.Id}}')"
RUN_STATUS="$RUN_STATUS" BLOCKER="$BLOCKER" OUT_WIN_M="$OUT_WIN" \
  SOURCE_EVENT_ID_M="$SOURCE_EVENT_ID" SOURCE_DIGEST_M="$SOURCE_DIGEST" BINDING_COUNT_M="$BINDING_COUNT" \
  TRUST_ROOT_M="$TRUST_ROOT" TASK_STATUS_M="$TASK_STATUS" BACKEND_IMAGE_M="$BACKEND_IMAGE" IMAGE_ID_M="$IMAGE_ID" \
  WORKSPACE_ID_M="$WORKSPACE_ID" PROJECT_ID_M="$PROJECT_ID" CR_ID_M="$CR_ID" TASK_ID_M="$TASK_ID" RUNTIME_ID_M="$RUNTIME_ID" \
  node - <<'NODE'
const fs = require('fs');
const e = process.env;
const facts = {
  schema: 'aifi45-m2-real-loop-facts/v1', measured_at: new Date().toISOString(),
  result: e.RUN_STATUS, blocker: e.BLOCKER,
  image: { tag: e.BACKEND_IMAGE_M, id: e.IMAGE_ID_M },
  authorization: {
    source_event_id: e.SOURCE_EVENT_ID_M, source_digest: e.SOURCE_DIGEST_M,
    source_digest_prefix: e.SOURCE_DIGEST_M.slice(0, 16), source_bindings_count: Number(e.BINDING_COUNT_M),
    workspace_id: e.WORKSPACE_ID_M, project_id: e.PROJECT_ID_M, cr_id: e.CR_ID_M,
  },
  daemon: { trust_root: e.TRUST_ROOT_M, runtime_id: e.RUNTIME_ID_M, task_id: e.TASK_ID_M, task_status: e.TASK_STATUS_M },
  control_admission: { reached: false, binding_challenge_observed: false, business_consumption_observed: false },
  negatives: { tampered: 'not-run: positive prerequisite blocked', cross_project: 'not-run: positive prerequisite blocked' },
  initial_data_boundary: 'workspace/project/CR and one pipeline queue carrier were seeded in the disposable real DB; daemon claim, claim revalidation, delivery, install, crctl --check and terminal callback used real routes',
};
fs.writeFileSync(e.OUT_WIN_M + '/run-facts.json', JSON.stringify(facts, null, 2) + '\n');
NODE

cat > "$OUT/README.md" <<EOF
# AIFI-45 M2 真实跨端闭环取证（当前代码实跑）

## 结论：闭环未走通，已按真实阻断点停止

真实完成：当前源码镜像构建、tmpfs PG 真迁移、真实 HTTP 签发出 201、真实
\`approval_record\`/CR/project 行、真实 daemon claim 与 claim 复核、真实授权 GET、
daemon-owned trust root 安装 key/grant/source、daemon 亲启 crctl \`--check\`。

**未走通**：daemon 随后在当前代码的严格 preflight 固定返回
\`EXECUTION_CONSUMPTION_REQUIRED\`，未进入 binding challenge、\`requireControlAdmission\`、
业务消费或 advance/register。两条 T 侧负例因此均为 **NOT RUN**，没有用本地注入替代。

- source_event_id：\`$SOURCE_EVENT_ID\`
- source_digest：\`$SOURCE_DIGEST\`（前缀 \`${SOURCE_DIGEST:0:16}\`）
- bindings 字段数：\`$BINDING_COUNT\`
- trust root：\`$TRUST_ROOT\`
- 镜像：\`$BACKEND_IMAGE\`
- 镜像 ID：\`$IMAGE_ID\`
- 任务终态：\`$TASK_STATUS\`

## 箭头与证据文件

| 箭头 / 事实 | 结果 | 原始证据 |
|---|---|---|
| 当前源码 → backend 镜像 | 真实 | \`build.stdout.txt\` |
| tmpfs PG → 真迁移 → health | 真实 | \`migrate.stdout.txt\`, \`health.stdout.txt\` |
| structured-human-request 原 bytes → 真实签发 route | 真实，HTTP 201 | \`issue-authorization.stdout.txt\`, \`source-request.json\` |
| 签发行与 DB 归属 / source_event_id / digest / bindings | 真实 | \`db-grant-row.stdout.txt\` |
| daemon 授权 GET → daemon-owned trust root | 真实 | \`trust-root-install.stdout.txt\`, \`daemon.log.txt\` |
| daemon 亲启 crctl 静态 \`--check\` | 真实，但不是控制准入 | \`trust-root-install.stdout.txt\` |
| binding endpoint → requireControlAdmission → 业务消费 | **未走通**：前置固定门禁 | \`crctl-admission.stdout.txt\` |
| tampered source 负例 | **NOT RUN** | \`negative-tampered.stdout.txt\` |
| cross-project 负例 | **NOT RUN** | \`negative-cross-project.stdout.txt\` |
| 清理后容器与镜像 ID | 真实 | \`podman-ps-after.stdout.txt\` |

## 边界

一次性实例、自签 CA、同 UID 容器和 seed 的初始 workspace/project/CR/pipeline 队列
**不等于生产部署或生产信任链**。claim、二次 claim 校验、授权 delivery、安装、
crctl --check 和终态回调来自真实路由/DB/daemon；脚本没有声称 pipeline 队列由完整
Runner 业务链产生。没有临时私钥、PAT、daemon token、JWT 或 DB 密码写入证据。
所有随机容器、网络与 tmpfs DB 均由 trap 销毁；既有 \`multica-postgres\`、
\`multica-backend\`、\`multica-internal\` 未作为运行资源使用。

## TC-TAC-001..010：没有一条可据此升整条

- **TC-TAC-001**：缺 daemon 亲启的非只读 admission、真实业务事务与消费事实。
- **TC-TAC-002**：真实两 project grant 替换与零副作用未跑。
- **TC-TAC-003**：本次只有真实 daemon 静态 check；不能替代各伪造输入下的真实 admission。
- **TC-TAC-004**：真实 route/source/DB 子句得到补强；篡改来源经 daemon/T 的拒绝未跑，仍只能条款级。
- **TC-TAC-005**：本次没有不同 OS 身份写保护证据；既有 Linux 半侧不能补 Windows。
- **TC-TAC-006**：旧 head、撤销、失联、恢复矩阵未在真实链跑完。
- **TC-TAC-007**：repair-admit/resume 正例及故障恢复未经真实 daemon。
- **TC-TAC-008**：repair 负例矩阵未经真实 daemon。
- **TC-TAC-009**：预分配 registration key、register/archive 正例与重放未跑。
- **TC-TAC-010**：register/archive 负例与零副作用未跑。

因此这份证据不能支持生产启用、ADJ-AIFI45-001/002/003 关闭或任何整条 TC 升级。
EOF

echo "== [8/8] $RUN_STATUS =="
printf '%s\n' "$BLOCKER"
exit 42

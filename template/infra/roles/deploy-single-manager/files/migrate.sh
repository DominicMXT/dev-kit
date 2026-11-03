#!/usr/bin/env bash
set -euo pipefail

stack="$1"
image="$2"
env_file="$3"
timeout_s="${4:-300}"
network="${stack}_default"
service="${stack}_migrate"

if ! docker network inspect "$network" >/dev/null 2>&1; then
    echo "network $network not found: first deploy, migrations run inside the stack"
    exit 0
fi

docker service rm "$service" >/dev/null 2>&1 || true
docker service create --detach --quiet --name "$service" --network "$network" \
    --restart-condition none --env-file "$env_file" --with-registry-auth "$image" >/dev/null

deadline=$((SECONDS + timeout_s))
state=""
while (( SECONDS < deadline )); do
    state="$(docker service ps "$service" --no-trunc --format '{{.CurrentState}}' | head -n 1)"
    case "$state" in
        Complete*|Failed*|Rejected*) break ;;
    esac
    sleep 2
done

docker service logs --raw "$service" 2>&1 || true
docker service rm "$service" >/dev/null 2>&1 || true

case "$state" in
    Complete*) echo "migrations complete" ;;
    *) echo "migrations failed: ${state:-no task}" >&2; exit 1 ;;
esac

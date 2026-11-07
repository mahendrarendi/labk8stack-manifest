#!/usr/bin/env bash
set -euo pipefail

namespace="labk8stack"
database_namespace="cnpg-system"
database_secret="labk8stack-pgcluster-app"
config_secret="labk8stack-config"
challenge_image="${LAB_APP_IMAGE:-registry.k8s.io/echoserver:1.10}"
challenge_good_tags="${LAB_APP_GOOD_TAGS:-1.10,latest}"

for executable in kubectl base64 openssl; do
  command -v "$executable" >/dev/null || {
    printf 'Missing required command: %s\n' "$executable" >&2
    exit 1
  }
done

temporary_directory="$(mktemp -d)"
chmod 700 "$temporary_directory"
trap 'rm -rf "$temporary_directory"' EXIT

if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
  kubectl create namespace "$namespace"
fi

if ! kubectl -n "$namespace" get secret "$database_secret" >/dev/null 2>&1; then
  kubectl -n "$database_namespace" get secret "$database_secret" \
    -o go-template='{{index .data "fqdn-uri"}}' \
    | base64 --decode > "$temporary_directory/fqdn-uri"
  if [[ ! -s "$temporary_directory/fqdn-uri" ]]; then
    printf 'CNPG Secret is missing its fqdn-uri key.\n' >&2
    exit 1
  fi
  kubectl -n "$namespace" create secret generic "$database_secret" \
    --from-file="fqdn-uri=$temporary_directory/fqdn-uri"
else
  printf 'Database Secret already exists in %s; leaving it unchanged.\n' "$namespace"
fi

if ! kubectl -n "$namespace" get secret "$config_secret" >/dev/null 2>&1; then
  umask 077
  printf 'SECRET_KEY=%s\nLAB_APP_IMAGE=%s\nLAB_APP_GOOD_TAGS=%s\n' \
    "$(openssl rand -hex 32)" "$challenge_image" "$challenge_good_tags" \
    > "$temporary_directory/config.env"
  kubectl -n "$namespace" create secret generic "$config_secret" \
    --from-env-file="$temporary_directory/config.env"
else
  printf 'Application Secret already exists in %s; leaving it unchanged.\n' "$namespace"
fi

kubectl -n "$namespace" get secret "$database_secret" "$config_secret"
printf 'Initial provisioning is complete. Review the Secrets, then sync the Argo CD Application.\n'
printf 'The CNPG Secret copy is one-time; set up credential synchronization before rotation.\n'

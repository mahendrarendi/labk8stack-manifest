#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd)"
gateway_namespace="nginx-gateway"
gateway_name="public-gateway"
listener_name="lab-https"
hostname="lab.mahendrarendi.cloud"

kubectl -n "$gateway_namespace" get gateway "$gateway_name" >/dev/null
kubectl get clusterissuer letsencrypt-prod >/dev/null

existing_hostname="$(kubectl -n "$gateway_namespace" get gateway "$gateway_name" \
  -o go-template='{{range .spec.listeners}}{{if eq .name "lab-https"}}{{.hostname}}{{end}}{{end}}')"

if [[ -n "$existing_hostname" && "$existing_hostname" != "$hostname" ]]; then
  printf 'Gateway listener %s already exists for %s; refusing to change it.\n' \
    "$listener_name" "$existing_hostname" >&2
  exit 1
fi

kubectl apply -f "$script_directory/lab-certificate.yaml"

if [[ -z "$existing_hostname" ]]; then
  kubectl -n "$gateway_namespace" patch gateway "$gateway_name" \
    --type=json --patch-file="$script_directory/lab-gateway-listener.json"
else
  printf 'Gateway listener %s already exists for %s.\n' "$listener_name" "$hostname"
fi

kubectl -n "$gateway_namespace" get certificate lab-tls
kubectl -n "$gateway_namespace" get gateway "$gateway_name"
printf 'Wait for Certificate lab-tls to become Ready before syncing the application route.\n'

#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

validation_repo="ghcr.io/example/labk8stack"
validation_digest="sha256:$(printf '%064d' 0)"
validation_dir="$(mktemp -d)"
trap 'rm -rf "$validation_dir"' EXIT

for environment in development production; do
  release="labk8stack"
  namespace="labk8stack"
  if [[ "$environment" == development ]]; then
    release="labk8stack-dev"
    namespace="labk8stack-dev"
  fi

  values="environments/$environment/values.yaml"
  helm lint . --strict -f "$values" \
    --set-string "image.repository=$validation_repo" \
    --set-string "image.digest=$validation_digest"
  rendered="$validation_dir/${release}-rendered.yaml"
  helm template "$release" . -n "$namespace" -f "$values" \
    --set-string "image.repository=$validation_repo" \
    --set-string "image.digest=$validation_digest" > "$rendered"

  grep -q 'kind: ValidatingAdmissionPolicyBinding' "$rendered"
  grep -q 'kind: PodDisruptionBudget' "$rendered"
  grep -q 'kind: ConfigMap' "$rendered"
  grep -q 'configMapKeyRef:' "$rendered"
  grep -q "${validation_repo}@${validation_digest}" "$rendered"
done

# Validate the optional Gateway API route used by production.
helm template labk8stack . -n labk8stack \
  -f environments/production/values.yaml \
  --set gateway.enabled=true > "$validation_dir/gateway-rendered.yaml"
grep -q 'kind: HTTPRoute' "$validation_dir/gateway-rendered.yaml"
grep -q 'lab.mahendrarendi.cloud' "$validation_dir/gateway-rendered.yaml"

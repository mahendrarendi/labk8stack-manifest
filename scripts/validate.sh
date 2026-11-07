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
  grep -q "${validation_repo}@${validation_digest}" "$rendered"
done

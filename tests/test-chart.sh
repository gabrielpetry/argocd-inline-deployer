#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
HELM="${HELM:-helm}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

"$HELM" lint --strict .
"$HELM" lint --strict . -f tests/fixtures/manifests.yaml
"$HELM" template test . > "$workdir/empty.yaml"
if grep -q '[^[:space:]]' "$workdir/empty.yaml"; then
  echo 'FAIL: default values must render no resources' >&2
  exit 1
fi

"$HELM" template test . -f tests/fixtures/manifests.yaml > "$workdir/rendered.yaml"
# Helm 3 and 4 differ in blank lines between documents; resource content must match.
diff -u -B tests/fixtures/expected.yaml "$workdir/rendered.yaml"

assert_invalid() {
  printf '%s\n' "$2" > "$workdir/invalid.yaml"
  if "$HELM" template test . -f "$workdir/invalid.yaml" > "$workdir/output" 2> "$workdir/error"; then
    echo "FAIL: accepted invalid values ($1)" >&2
    exit 1
  fi
  # Ensure the rejection comes from values validation, not an unrelated failure.
  grep -qi 'schema' "$workdir/error"
}
assert_invalid 'non-array manifests' 'manifests: {}'
assert_invalid 'scalar resource' 'manifests: [not-a-resource]'
assert_invalid 'missing kind' 'manifests: [{apiVersion: v1}]'
assert_invalid 'empty apiVersion' 'manifests: [{apiVersion: "", kind: ConfigMap}]'
assert_invalid 'invalid metadata' 'manifests: [{apiVersion: v1, kind: ConfigMap, metadata: []}]'

"$HELM" package . --destination "$workdir"
archive="$(find "$workdir" -maxdepth 1 -name '*.tgz' -print)"
"$HELM" lint --strict "$archive"
"$HELM" template test "$archive" -f tests/fixtures/manifests.yaml > "$workdir/packaged.yaml"
diff -u -B tests/fixtures/expected.yaml "$workdir/packaged.yaml"
if tar -tzf "$archive" | grep -E '/(tests|\.github|\.git)/'; then
  echo 'FAIL: development files included in chart package' >&2
  exit 1
fi
printf 'PASS: empty values, literal multi-resource rendering, schema validation, and packaged chart\n'

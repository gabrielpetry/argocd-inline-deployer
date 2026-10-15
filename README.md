# argocd-inline-deployer

A minimal Helm chart that renders the Kubernetes objects in `manifests` as separate YAML documents. No generated names, labels, namespaces, or template evaluation are added to your resources.

## Use

Requires Helm 3.8+ (OCI support); CI tests Helm 3.19.0.

Create `my-values.yaml`:

```yaml
manifests:
  - apiVersion: v1
    kind: ConfigMap
    metadata:
      name: app-config
    data:
      greeting: hello
```

Render locally:

```sh
helm template example . --namespace default -f my-values.yaml
```

Install the published chart (available after the first release):

```sh
helm upgrade --install example \
  oci://ghcr.io/gabrielpetry/argocd-inline-deployer \
  --version 0.2.0 --namespace default -f my-values.yaml
```

`manifests` defaults to `[]`, rendering no resources. Each entry must be an object with non-empty `apiVersion` and `kind`. The schema validates the envelope, not the full Kubernetes API: validate resource-specific fields against your target cluster.

Secrets are rejected by default with `Secrets are disallowed you must enable the variable: allow_secrets: true`. To explicitly allow `kind: Secret` resources, set the top-level boolean `allow_secrets: true` in your values.

Values are literal data: strings such as `{{ .Release.Name }}` are **not** evaluated. Set resource names and any explicit namespaces yourself. Namespaced objects without `metadata.namespace` use the deployment namespace. Only supply trusted manifests; installation can create any resources permitted by the deploying identity. Do not commit secrets to values files.

## Argo CD

After publishing the chart and making the GHCR package public, use a Helm source:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: inline-example
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ghcr.io/gabrielpetry
    chart: argocd-inline-deployer
    targetRevision: 0.2.0
    helm:
      valuesObject:
        manifests:
          - apiVersion: v1
            kind: ConfigMap
            metadata:
              name: app-config
            data:
              greeting: hello
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
```

Argo CD's Helm OCI `repoURL` omits `oci://`. Configure a repository with `enableOCI: "true"` and credentials when required by your Argo CD setup or a private GHCR package. The destination namespace must exist, or configure Argo CD's `CreateNamespace=true` sync option.

## Validate and build

```sh
bash tests/test-chart.sh
helm package . --destination dist
```

Tests check empty defaults, multiple resources, literal strings, invalid values, Secret rejection and opt-in, and rendering from the packaged chart. Packaging excludes CI and test files.

## Release to GHCR

1. Set `version` in `Chart.yaml` to the desired semantic version (currently `0.2.0`).
2. Commit and push the chart to `main`.
3. Create and push a matching tag:

   ```sh
   git tag v0.2.0
   git push origin v0.2.0
   ```

Pull requests and pushes to `main` run linting, rendering tests, and packaging; the package is uploaded as a workflow artifact. A `v*` tag runs the same checks, verifies the tag matches the chart version, and publishes to `oci://ghcr.io/<owner>/argocd-inline-deployer` using `GITHUB_TOKEN`. No separate registry secret is required. GitHub Actions must be allowed to write packages.

The published artifact is an **OCI Helm chart**, not a runnable container image. GHCR packages may initially be private: set package visibility to public for anonymous pulls, or authenticate with `helm registry login ghcr.io`. If an existing package denies publishing, grant this repository Actions access in that package's settings.

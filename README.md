# example-kind

This repository contains manifests and configuration for a simple Kubernetes demo using `kind`, `docker-desktop`, and `helm` on Windows.

## Prerequisites ✅

Before you begin, ensure your local machine meets the following requirements:

1. **Windows 10/11** with WSL2 enabled (Cgroup v2 recommended).
2. **Docker Desktop** installed and running. Set the backend to WSL2 (if applicable) and make sure the built-in Kubernetes is **disabled** — `kind` will create/manage clusters for you.
3. **kind** (Kubernetes IN Docker) installed globally. You can install via `choco install kind` or follow the instructions at https://kind.sigs.k8s.io/.
4. **kubectl** CLI on your PATH. The `kind` installer usually drops a copy in the same directory, but if you have other contexts you may want to install/upgrade via `choco install kubernetes-cli`.
5. **Helm** installed globally. Install via `choco install kubernetes-helm` or from https://helm.sh/docs/intro/install/.
6. **Go** (the language) installed globally. Install via `choco install golang` (not the JetBrains IDE `Goland`).

> 💡 All commands in this readme are meant to be run from a PowerShell terminal.

## Setting up a local kind cluster 🔧
```go
// Installing Cloud Provider KIND (optional helper)
go install sigs.k8s.io/cloud-provider-kind@latest
```

```powershell
# create a cluster named "kind-demo-cluster" using the default config
kind create cluster --name kind-demo-cluster

# verify the cluster is running (context will be "kind-kind-demo-cluster")
kubectl cluster-info --context kind-kind-demo-cluster
```

`kubectl` is provided by `kind`; ensure it’s on your PATH after installing kind.

## Using Helm with the cluster 🚀

Once the cluster is up you can use Helm to deploy charts. For example:

```powershell
helm repo add stable https://charts.helm.sh/stable
helm repo update

# install nginx ingress controller (example)
helm install nginx-ingress stable/nginx-ingress \
  --set controller.publishService.enabled=true
```

Replace the example chart above with any chart you need.

## Setup Argocd and Expose UI on NodePort
```
kubectl create namespace argocd  # if you haven’t already
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```
# Get default pw from powershell
```
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | %{[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_))}
```

# (Optional) Update argocd to use nodeports
- Expose the argocd-server service using NodePorts
  ```
  kubectl edit svc argocd-server -n argocd
  ```
- Update the spec to to point to the NodePorts set in the cluster config and the type to a NodePort.
  - Node: The ports need to exist on the cluster
  ```
    ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 8080
    nodePort: 30080
  - name: https
    port: 443
    protocol: TCP
    targetPort: 8080
    nodePort: 30443
  selector:
    app.kubernetes.io/name: argocd-server
  sessionAffinity: None
  type: NodePort
  ```

## Manifests & charts in this repository 📁

- `docker-desktop-cluster/charts/k8s-demo/` – contains YAML manifests used in demonstrations and experiments:
  - `deployment-nginx.yaml` – basic nginx deployment
  - `ns-argocd.yaml` – namespace for Argo CD
  - `svc-nginx.yaml` – service for nginx deployment
  - `ingress.yaml` – ingress for the cluster
- `docker-desktop-cluster/cluster`
  - `kind-config.yaml` – config for the kind cluster
- `docker-desktop-cluster/argocd`
  - `app-argocd.yaml` – sample application manifest for Argo CD (templated via Helm values)

The GitHub Actions workflow that runs on pull requests validates YAML files; it now targets the chart directory and skips any files containing Helm template markers (`{{…}}`).  This keeps the linter from choking on templated manifests while still catching syntax problems in the top‑level chart files.

## Cluster config (`kind`) 🧩

This repository includes a `kind` cluster configuration that creates a single control-plane node and maps host ports so an ingress controller can bind to the host HTTP/S ports.

- **File:** `docker-desktop-cluster/cluster/kind-config.yaml`
- **Cluster name:** `kind-demo-cluster` (configured via `name:` in the file)
- **Host port mappings:** `30000 -> 30000, 30080 -> 30080, 30443 -> 30443` on the control-plane node (`extraPortMappings`) ([kind documentation](https://kind.sigs.k8s.io/docs/user/using-wsl2/#accessing-a-kubernetes-service-running-in-wsl2)).

To recreate the cluster using this config:

```powershell
kind delete cluster --name kind-demo-cluster
kind create cluster --config .\docker-desktop-cluster\cluster\kind-config.yaml --name kind-demo-cluster
```

## Deploying Envoy Gateway via Argo CD 🚪

This repository includes an Argo CD Application manifest that deploys **Envoy Gateway**, a modern, feature-rich ingress and gateway controller based on the Gateway API standard.

### Prerequisites

- Argo CD must be installed in the cluster (see **Setup Argocd** section above).
- Gateway API CRDs should already be installed (done as part of standard Argo CD setup).

### Deploy Envoy Gateway

Apply the Envoy Gateway application manifest via Argo CD:

```powershell
kubectl apply -f .\docker-desktop-cluster\argocd\app-envoy-gateway.yaml
```

Argo CD will detect the application and begin syncing. Check the status:

```powershell
# see application status
kubectl get application -n argocd envoy-gateway

# watch pods coming up in the envoy-gateway-system namespace
kubectl get pods -n envoy-gateway-system -w
```

Once the pods are running (typically a minute or two), Envoy Gateway is ready to route traffic.

### Creating Gateway and HTTPRoute resources

With Envoy Gateway running, you can now define gateways and routes to expose your services.

Example:

```yaml
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: my-gateway
  namespace: default
spec:
  gatewayClassName: envoy
  listeners:
  - name: http
    port: 80
    protocol: HTTP
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-route
  namespace: default
spec:
  parentRefs:
  - name: my-gateway
  hostnames:
  - "example.com"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: my-service
      port: 80
```

See [Gateway API documentation](https://gateway-api.sigs.k8s.io/) for more details on available resources and configuration options.

### EnvoyProxy configuration (NodePort 30000)

This repo uses an `EnvoyProxy` custom resource to control how Envoy Gateway exposes the generated data-plane Service.

- `GatewayClass` `cluster-gateway` references an `EnvoyProxy` via `parametersRef`.
- `EnvoyProxy` `custom-proxy-config` sets the Envoy Service type to `NodePort`.
- A service patch pins the HTTP listener NodePort to `30000`.

Relevant manifests:

- `docker-desktop-cluster/cluster-gateway/templates/cluster-gateway` (Helm template without `.yaml` extension defining the `GatewayClass`)
- `docker-desktop-cluster/cluster-gateway/templates/proxy-config.yaml`
- `docker-desktop-cluster/cluster-gateway/templates/gateway.yaml`
- `docker-desktop-cluster/k8s-demo/templates/http-route.yaml`

Apply/sync the `cluster-gateway` Argo CD application, then validate:

```powershell
kubectl get gatewayclass cluster-gateway -o yaml
kubectl get envoyproxy -n envoy-gateway-system custom-proxy-config -o yaml
kubectl get svc -n envoy-gateway-system
```

You should see the generated Envoy Service with port mapping similar to:

```text
8080:30000/TCP
```

Then test the route:

```powershell
curl.exe http://localhost:30000/songs
```

If the route is accepted but traffic fails, confirm:

- `kind` config maps host `30000 -> 30000` in `docker-desktop-cluster/cluster/kind-config.yaml`.
- The `k8s-demo-dev` Argo CD application has been synced/applied so that the `dev` namespace, `HTTPRoute`, and `go-api-svc` Service are created.
- `HTTPRoute` backend service (`go-api-svc`) exists in namespace `dev`.
- `Gateway` listener has `allowedRoutes.namespaces.from: All` for cross-namespace routes.

## Tearing down the cluster 🧹

```powershell
kind delete cluster --name kind-demo-cluster
```

## Notes 📝

* You do not need a remote Kubernetes provider; everything runs locally inside Docker Desktop.
* If you have existing Kubernetes contexts, kind will add a `kind-<name>` context, e.g. `kind-demo`.
* Helm communicates over the kubeconfig from `kubectl` and therefore automatically targets the active context.

Feel free to adapt the configuration and manifests for your own experiments.

## CI / Release pipeline 🔁

A GitHub Actions workflow has been added to automate semantic versioning using [release-me](https://github.com/semantic-release/release-me).

* **Location:** `.github/workflows/release.yml`
* **Trigger:** pushes to the `main` branch (typically merges).
* **Behavior:** bumps the version based on conventional commits and creates a GitHub release.
* **Requirements:** `GITHUB_TOKEN` is supplied automatically by GitHub Actions. Make sure the workflow permissions allow commenting on issues/PRs (see `issues: write` and `pull-requests: write` in the GitHub Actions config).

You can extend the workflow with tests/build steps as needed or adjust branch filters.


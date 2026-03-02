# demo clusters

This repository contains manifests and configuration for a simple Kubernetes demos using `kind`, `k3d`, and `helm` on Windows.

## Global setup (shared by kind + k3d) 🌐

### Prerequisites ✅

Before you begin, ensure your local machine meets the following requirements:

1. **Windows 10/11** with WSL2 enabled (Cgroup v2 recommended).
2. **A Docker-compatible container engine** installed and running (Docker Desktop, Rancher Desktop with `dockerd`, etc.). Set the backend to WSL2 (if applicable) and make sure any built-in Kubernetes is **disabled**.
3. **Distributions** 
  - **kind** (Kubernetes IN Docker) installed globally. You can install via `choco install kind` or follow the instructions at https://kind.sigs.k8s.io/.
  - **k3d** installed globally. You can install via `choco install k3d` or follow the instructions at https://k3d.io/.
4. **kubectl** CLI on your PATH. You can install/upgrade via `choco install kubernetes-cli`.
5. **Helm** installed globally. Install via `choco install kubernetes-helm` or from https://helm.sh/docs/intro/install/.
6. **Go** (the language) installed globally. Install via `choco install golang` (not the JetBrains IDE `Goland`).

> 💡 All commands in this readme are meant to be run from a PowerShell terminal.

## Manifests & charts in this repository 📁

### Global resources (shared by kind + k3d)

- `README.md` – setup and workflow documentation
- `LICENSE` – project license
- `package.json` – repo-level Node metadata/scripts

### kind-cluster resources

- `docker-desktop-cluster/cluster/kind-config.yaml` – kind cluster configuration
- `docker-desktop-cluster/argocd/` – Argo CD application manifests for the kind flow
- `docker-desktop-cluster/k8s-demo/` – demo Helm chart/manifests used by the kind flow
- `docker-desktop-cluster/cluster-gateway/` – Gateway API/Envoy gateway resources for kind

### k3d-cluster resources

- `k3d-cluster/cluster/config.yaml` – k3d cluster configuration
- `k3d-cluster/argocd/` – Argo CD manifests for the k3d flow
- `k3d-cluster/api-demo/` – Helm chart/manifests for apis hosted in the cluster

## kind-specific setup & resources 🔧

### Setting up a local kind cluster
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

## Global: Using Helm with the cluster 🚀

Once the cluster is up you can use Helm to deploy charts. For example:

```powershell
helm repo add stable https://charts.helm.sh/stable
helm repo update

# install nginx ingress controller (example)
helm install nginx-ingress stable/nginx-ingress \
  --set controller.publishService.enabled=true
```

Replace the example chart above with any chart you need.

## kind: Cluster config 🧩

This repository includes a `kind` cluster configuration that creates a single control-plane node and maps host ports so an ingress controller can bind to the host HTTP/S ports.

- **File:** `docker-desktop-cluster/cluster/kind-config.yaml`
- **Cluster name:** `kind-demo-cluster` (configured via `name:` in the file)
- **Host port mappings:** `30000 -> 30000, 30080 -> 30080, 30443 -> 30443` on the control-plane node (`extraPortMappings`) ([kind documentation](https://kind.sigs.k8s.io/docs/user/using-wsl2/#accessing-a-kubernetes-service-running-in-wsl2)).

### Prerequisites

- Argo CD must be installed in the cluster (see the **Argo CD Setup** section below).
- Gateway API CRDs should already be installed (see the **Envoy Gateway Setup** section below).

To recreate the cluster using this config:

```powershell
kind delete cluster --name kind-demo-cluster
kind create cluster --config .\docker-desktop-cluster\cluster\kind-config.yaml --name kind-demo-cluster
```

### kind: Deploying Envoy Gateway via Argo CD 🚪

This repository includes an Argo CD Application manifest that deploys **Envoy Gateway**, a modern, feature-rich ingress and gateway controller based on the Gateway API standard.

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
- A Service patch pins the Envoy data-plane Service's NodePort for the HTTP listener port to `30000`.

Relevant manifests:

- `docker-desktop-cluster/cluster-gateway/templates/cluster-gateway` (Helm template without `.yaml` extension defining the `GatewayClass`)
- `docker-desktop-cluster/cluster-gateway/templates/proxy-config.yaml`
- `docker-desktop-cluster/cluster-gateway/templates/gateway.yaml`
- `docker-desktop-cluster/k8s-demo/templates/http-route.yaml`

Validate the changes:

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

### kind: Tearing down the cluster 🧹

```powershell
kind delete cluster --name kind-demo-cluster
```

## k3d-specific setup & resources 🐳

### Setting up a local k3d cluster

This repository also includes a k3d cluster manifest:

- `k3d-cluster/cluster/config.yaml`

Create the cluster from this config:

```powershell
k3d cluster create --config .\k3d-cluster\cluster\config.yaml
```

For the k3d flow, Traefik is enabled by default and the demo API is exposed via Kubernetes `Ingress` on `/songs` through the k3d load balancer port mapping (`127.0.0.1:8080 -> :80`).

Verify access:

```powershell
kubectl config get-contexts
kubectl cluster-info --context k3d-demo-k3-cluster
```

Delete the cluster when finished:

```powershell
k3d cluster delete demo-k3-cluster
```
## Platform add-ons (Argo CD, Envoy Gateway, etc.)

These are the platform add-ons used in the k3 and kind clusters.

### Argocd Setup

#### Installing Argo CD into the cluster

```
kubectl create namespace argocd  # if you haven’t already
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

#### Get default pw from powershell

```
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | %{[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_))}
```

#### (Optional setup for kind) Update argocd to use nodeports
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

The GitHub Actions workflow that runs on pull requests validates Kubernetes YAML manifests under `docker-desktop-cluster/k8s-demo/*.yaml`, helping catch syntax issues in the demo resources.

### Envoy Gateway Setup (Kind Cluster)

Instructions can be found at [Envoy Gateway](https://gateway.envoyproxy.io/docs/install/install-yaml/)

```
kubectl apply --server-side -f https://github.com/envoyproxy/gateway/releases/download/v1.7.0/install.yaml
```

## Notes 📝

* You do not need a remote Kubernetes provider; everything runs locally using a Docker-compatible engine (Docker Desktop, Rancher Desktop with `dockerd`, etc.).
* If you have existing Kubernetes contexts, kind and k3d will each add their own context names (for example `kind-<name>` and `k3d-<name>`).
* Helm communicates over the kubeconfig from `kubectl` and therefore automatically targets the active context.

Feel free to adapt the configuration and manifests for your own experiments.

## CI / Release pipeline 🔁

A GitHub Actions workflow has been added to automate semantic versioning using [release-me](https://github.com/semantic-release/release-me).

* **Location:** `.github/workflows/release.yml`
* **Trigger:** pushes to the `main` branch (typically merges).
* **Behavior:** bumps the version based on conventional commits and creates a GitHub release.
* **Requirements:** `GITHUB_TOKEN` is supplied automatically by GitHub Actions. Make sure the workflow permissions allow commenting on issues/PRs (see `issues: write` and `pull-requests: write` in the GitHub Actions config).

You can extend the workflow with tests/build steps as needed or adjust branch filters.


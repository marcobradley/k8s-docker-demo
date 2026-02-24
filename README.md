# example-kind

This repository contains manifests and configuration for a simple Kubernetes demo using `kind`, `docker-desktop`, and `helm` on Windows.

## Prerequisites ✅

Before you begin, ensure your local machine meets the following requirements:

1. **Windows 10/11** with WSL2 enabled (optional but recommended).
2. **Docker Desktop** installed and running. Set the backend to use WSL2 (if applicable) and ensure Kubernetes is **disabled** in Docker Desktop since `kind` will manage clusters.
3. **kind** (Kubernetes IN Docker) installed globally. You can install via `choco install kind` or follow the instructions at https://kind.sigs.k8s.io/.
4. **Helm** installed globally. Install via `choco install kubernetes-helm` or from https://helm.sh/docs/intro/install/.

> 💡 All commands in this readme are meant to be run from a PowerShell terminal.

## Setting up a local kind cluster 🔧

```powershell
# create a cluster named "demo"
kind create cluster --name demo

# verify the cluster is running
kubectl cluster-info --context kind-demo
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

## Manifests in this repository 📁

- `docker-desktop-cluster/` – contains YAML manifests used in demonstrations and experiments:
  - `app-argocd.yaml` – sample application manifest for Argocd
  - `deployment-nginx.yaml` – basic nginx deployment
  - `ns-argocd.yaml` – namespace for argocd
  - `svc-nginx.yaml` – service for nginx deployment

  ## Cluster config (`kind`) 🧩

  This repository includes a `kind` cluster configuration that creates a single control-plane node that maps host ports 80 and 443 into the node so an ingress controller can bind to the host HTTP/S ports.

  - **File:** `docker-desktop-cluster/kind-confg.yaml`
  - **Cluster name:** `kind-demo-cluster` (set via `name:` in the config)
  - **Host port mappings:** `80 -> 80`, `443 -> 443` on the control-plane node (`extraPortMappings`)

  To recreate the cluster using this config:

  ```powershell
  kind delete cluster --name kind-demo-cluster
  kind create cluster --config .\docker-desktop-cluster\kind-confg.yaml --name kind-demo-cluster
  ```

  After the cluster is running install an ingress controller (example with `ingress-nginx`):

  ```powershell
  kubectl create namespace ingress-nginx
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
  helm repo update
  helm install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx
  ```

  The ingress controller will be able to serve on ports 80 and 443 from the host because of the `extraPortMappings` in the `kind` config.

## Tearing down the cluster 🧹

```powershell
kind delete cluster --name demo
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


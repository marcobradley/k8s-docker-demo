# demo clusters

This repository contains manifests and configuration for a simple Kubernetes demos using `k3d`, `Prometheus`, and `helm`,  on Windows.

## Global setup 🌐

### Prerequisites ✅

Before you begin, ensure your local machine meets the following requirements:

1. **Windows 10/11** with WSL2 enabled (Cgroup v2 recommended).
2. **A Docker-compatible container engine** installed and running (Docker Desktop, Rancher Desktop with `dockerd`, etc.). Set the backend to WSL2 (if applicable) and make sure any built-in Kubernetes is **disabled**.
3. **Distributions** 
  - **k3d** installed globally. You can install via `choco install k3d` or follow the instructions at https://k3d.io/.
4. **kubectl** CLI on your PATH. You can install/upgrade via `choco install kubernetes-cli`.
5. **Helm** installed globally. Install via `choco install kubernetes-helm` or from https://helm.sh/docs/intro/install/.
6. **Go** (the language) installed globally. Install via `choco install golang` (not the JetBrains IDE `Goland`).

> 💡 All commands in this readme are meant to be run from a PowerShell terminal.

## Manifests & charts in this repository 📁

### Global resources

- `README.md` – setup and workflow documentation
- `LICENSE` – project license
- `package.json` – repo-level Node metadata/scripts

### Cluster resources

- `k3d-cluster/cluster/config.yaml` – k3d cluster configuration
- `k3d-cluster/argocd/` – Argo CD Application manifests for the k3d flow (core + workloads)
- `k3d-cluster/argocd-core/` – Argo CD core runtime manifests (ingress + cmd params)
- `k3d-cluster/api-demo/` – Helm chart/manifests for apis hosted in the cluster
- `k3d-cluster/cluster-rbac/` – cluster-scoped RBAC chart (ClusterRole/ClusterRoleBinding)
- `k3d-cluster/workload-rbac/` – namespace/workload RBAC chart (Role/RoleBinding)
- `k3d-cluster/external-secrets/` – SecretStore/ExternalSecret examples for 1Password + ESO

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

## Setup & resources 🐳

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

### Backup and restore (local k3d)

This single-server k3d setup uses k3s sqlite datastore (not etcd). A helper script is included for consistent backups:

```powershell
.\scripts\backup-k3d-k3s.ps1
```

Include local-path PV data:

```powershell
.\scripts\backup-k3d-k3s.ps1 -IncludePvData
```

Restore runbook:

- `docs/restore-k3d-k3s.md`

## Platform add-ons (Argo CD, Prometheus, Grafana, etc.)

These are the platform add-ons used in the cluster.

### Argocd Setup

#### Installing Argo CD into the cluster

```
kubectl create namespace argocd  # if you haven’t already
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

#### k3d split: core app + workloads app

Apply Argo CD core first (manages `argocd-cmd-params-cm` + ingress), then workloads:

```powershell
kubectl apply -f .\k3d-cluster\argocd\app-argocd-core.yaml
kubectl apply -f .\k3d-cluster\argocd\app-argocd-dev.yaml
```

#### k3d RBAC split: cluster-wide + workload-scoped

RBAC is managed as two separate Argo CD applications:

- `k3d-cluster/argocd/app-cluster-rbac.yaml` for cluster-scoped permissions.
- `k3d-cluster/argocd/app-workload-rbac-dev.yaml` for workload/namespace-scoped permissions.

Apply both RBAC apps:

```powershell
kubectl apply -f .\k3d-cluster\argocd\app-cluster-rbac.yaml
kubectl apply -f .\k3d-cluster\argocd\app-workload-rbac-dev.yaml
```

Verify Argo CD application health:

```powershell
kubectl get application -n argocd app-cluster-rbac
kubectl get application -n argocd app-workload-rbac-dev
```

Verify RBAC resources were created:

```powershell
kubectl get clusterrole secret-reader
kubectl get clusterrolebinding secret-reader-binding
kubectl get role,rolebinding -n dev
```

#### k3d monitoring: Prometheus + Grafana

Deploy monitoring stack via Argo CD:

```powershell
kubectl apply -f .\k3d-cluster\argocd\app-monitoring-k3d.yaml
kubectl get application -n argocd monitoring-k3d
kubectl get pods -n monitoring
```

Monitoring Helm values are stored in:

- `k3d-cluster/monitoring/values.yaml`

Update that file to keep Grafana ingress, Prometheus ingress, datasource defaults, and admission webhook settings across fresh installs.

Access endpoints (Traefik TLS / host port `8443`):

- Grafana: `https://grafana.localhost:8443`
- Prometheus: `https://prometheus.localhost:8443`

Default Grafana login for this local setup:

- username: `admin`
- password: `admin`

If browser cert warning appears, proceed (local/self-signed TLS).

After the first core sync, restart `argocd-server` once so `server.insecure=true` is picked up:

```powershell
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout status deployment argocd-server -n argocd --timeout=180s
```

#### Get default pw from powershell

```
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | %{[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_))}
```

#### GitHub OAuth login for local Argo CD

You can enable Argo CD SSO with GitHub OAuth for this local setup.
1. Create an OAuth app in your GitHub org
  - [Argocd Documentation](https://argo-cd.readthedocs.io/en/release-1.8/operator-manual/user-management/#:~:text=Once%20installed%20Argo%20CD%20has,users%20or%20configure%20SSO%20integration.)
2. Create a GitHub OAuth App:
  - Homepage URL: `https://argocd.localhost:8443`
  - Authorization callback URL: `https://argocd.localhost:8443/api/dex/callback`

3. Update Argo CD OAuth config files in this repo:
  - `k3d-cluster/argocd-core/argocd-cm.yaml`
  - `k3d-cluster/argocd-core/secret-argocd-github-oauth.yaml`

4. Set your GitHub values:
  - In `argocd-cm.yaml`, set `org.name` to your GitHub org or username.
  - In `secret-argocd-github-oauth.yaml`, set:
    - `dex.github.clientID`
    - `dex.github.clientSecret`

5. Apply the manifests:

```powershell
kubectl apply -f .\k3d-cluster\argocd-core\argocd-cm.yaml
kubectl apply -f .\k3d-cluster\argocd-core\secret-argocd-github-oauth.yaml
```

5. Restart Argo CD server to pick up changes:

```powershell
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout status deployment argocd-server -n argocd --timeout=180s
```

6. Open Argo CD and sign in with GitHub:
  - URL: `https://argocd.localhost:8443`

If the login button does not appear, check the `argocd-cm` and `argocd-secret`
resources and then re-sync or re-apply Argo CD core manifests.

#### Optional: 1Password as secrets manager (External Secrets Operator)

This optional flow follows the same architecture shown in:
https://dev.to/3deep5me/using-1password-with-external-secrets-operator-in-a-gitops-way-4lo4

Apply Argo CD apps for 1Password Connect and External Secrets Operator:

```powershell
kubectl apply -f .\k3d-cluster\argocd\app-1password-connect.yaml
kubectl apply -f .\k3d-cluster\argocd\app-external-secrets-operator.yaml
kubectl get pods -n external-secrets
```

Create a 1Password vault + connect server (requires `op` CLI):

```powershell
op vault create "K8s"
op connect server create "Kubernetes" --vaults "K8s"
```

Create the Connect credentials secret in Kubernetes (`op-credentials`):

```powershell
kubectl create secret generic op-credentials -n external-secrets --from-file=1password-credentials.json="C:\path\to\1password-credentials.json"
```

Create a token for External Secrets Operator and store it in Kubernetes:

```powershell
$token = op connect token create "external-secret-operator" --server "Kubernetes" --vault "K8s"
kubectl create secret generic onepassword-connect-token -n external-secrets --from-literal=token="$token"
```

Apply the SecretStore configuration:

```powershell
kubectl apply -f .\k3d-cluster\external-secrets\clustersecretstore-1password.yaml
kubectl get clustersecretstore onepassword-k8s
```

End-to-end test with an example item + ExternalSecret:

```powershell
op item create --vault "K8s" --title "Scaleway Credentials" --category login accessKeyId="token-xyz" secretKey="xyz"
kubectl apply -f .\k3d-cluster\external-secrets\externalsecret-example.yaml
kubectl get externalsecret -n default scaleway-credentials
kubectl get secret -n default scaleway-credentials
```

Notes:
- Keep `connect.serviceType=ClusterIP` (already set in `app-1password-connect.yaml`).
- Do not commit real 1Password credentials/token files into git.

## Notes 📝

* You do not need a remote Kubernetes provider; everything runs locally using a Docker-compatible engine (Docker Desktop, Rancher Desktop with `dockerd`, etc.).
* If you have existing Kubernetes contexts, k3d will add their own context name (for example `k3d-<name>`).
* Helm communicates over the kubeconfig from `kubectl` and therefore automatically targets the active context.

Feel free to adapt the configuration and manifests for your own experiments.

## Run GitAction checks locally

Prerequisites for local checks:

- `yamllint` installed and available on `PATH`
- `helm` installed and available on `PATH`
- `nodejs` installed and available on `PATH`

Install `yamllint` (Windows PowerShell):

```powershell
py -m pip install --user yamllint
yamllint --version
```

If `yamllint` is not recognized, either open a new terminal or run it via Python:

```powershell
py -m yamllint --version
```

Run all local checks:

```powershell
npm run check:local
```

Run checks individually:

```powershell
npm run check:yaml
npm run check:helm
```

## Pre-commit hooks

This repo uses [`pre-commit`](https://pre-commit.com/) with a `commit-msg` hook
(`commitizen`) to enforce Conventional Commit messages.

Install `pre-commit` (Windows PowerShell):

```powershell
py -m pip install --user pre-commit
pre-commit --version
```

Install hooks in this repository:

```powershell
pre-commit install
```

Because `.pre-commit-config.yaml` sets `default_install_hook_types: [commit-msg]`,
this command installs the commit message hook automatically.

Use it in your normal workflow:

```powershell
git add .
git commit -m "feat: add monitoring docs"
```

If the commit message does not follow the expected format, the commit is blocked.
Update the message and commit again.

Optional: run all configured hooks manually:

```powershell
pre-commit run --all-files
```

## API image references

The API container images used by this cluster come from the following repositories.
Use these repositories as the source of truth for endpoint details and contract behavior.

- `csharp-api`: https://github.com/marcobradley/csharp-api-demo
- `golang-api`: https://github.com/marcobradley/golang-api-demo
- `ollama-api`: https://github.com/marcobradley/ollama-llm

## CI / Release pipeline 🔁

A GitHub Actions workflow has been added to automate semantic versioning using [release-me](https://github.com/semantic-release/release-me).

* **Location:** `.github/workflows/release.yml`
* **Trigger:** pushes to the `main` branch (typically merges).
* **Behavior:** bumps the version based on conventional commits and creates a GitHub release.
* **Requirements:** `GITHUB_TOKEN` is supplied automatically by GitHub Actions. Make sure the workflow permissions allow commenting on issues/PRs (see `issues: write` and `pull-requests: write` in the GitHub Actions config).

### Commit message conventions
commit messages are used by [cycjimmy/semantic-release-action](https://github.com/cycjimmy/semantic-release-action) to push the new version tag to the main branch.

- **Patch release:** `fix: correct ingress path`
- **Minor release:** `feat: add k3d ingress manifest`
- **Major release (breaking):** `feat!: change API route contract`
- **Alternative major format:**

```text
feat: change API route contract

BREAKING CHANGE: route /songs now requires auth
```

You can extend the workflow with tests/build steps as needed or adjust branch filters.


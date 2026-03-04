# Restore guide (k3d + k3s sqlite)

This runbook restores a local `k3d` cluster that uses k3s sqlite datastore (single-server setup).

## Assumptions

- Backup created by `scripts/backup-k3d-k3s.ps1`
- Cluster name: `demo-k3-cluster`
- Server container name: `k3d-demo-k3-cluster-server-0`

## 1) Create/ensure cluster exists

If needed, recreate from config:

```powershell
k3d cluster create --config .\k3d-cluster\cluster\config.yaml
```

## 2) Stop cluster before restore

```powershell
k3d cluster stop demo-k3-cluster
```

## 3) Restore sqlite datastore files

Replace `<BACKUP_DIR>` with your backup folder (contains `k3s-server-db`).

```powershell
docker cp <BACKUP_DIR>\k3s-server-db\. k3d-demo-k3-cluster-server-0:/var/lib/rancher/k3s/server/db/
```

If you backed up PV data (`-IncludePvData`), also restore it:

```powershell
docker cp <BACKUP_DIR>\k3s-storage\. k3d-demo-k3-cluster-server-0:/var/lib/rancher/k3s/storage/
```

## 4) Start cluster

```powershell
k3d cluster start demo-k3-cluster
kubectl wait --for=condition=Ready node --all --timeout=120s
```

## 5) Validate

```powershell
kubectl get nodes
kubectl get ns
kubectl get applications -n argocd
kubectl get pods -A
```

## Optional: re-apply GitOps apps

If Argo CD apps are missing (for example, restoring to a fresh install path):

```powershell
kubectl apply -f .\k3d-cluster\argocd\app-argocd-core.yaml
kubectl apply -f .\k3d-cluster\argocd\app-argocd-dev.yaml
kubectl apply -f .\k3d-cluster\argocd\app-monitoring-k3d.yaml
```

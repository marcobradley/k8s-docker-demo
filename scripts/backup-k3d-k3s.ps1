param(
    [string]$ClusterName = "demo-k3-cluster",
    [string]$OutputRoot = ".\backups",
    [string[]]$Namespaces = @("argocd", "dev", "monitoring"),
    [switch]$IncludePvData,
    [switch]$NoArchive,
    [switch]$NoClusterStop
)

$ErrorActionPreference = "Stop"

function Require-Command {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found on PATH."
    }
}

Require-Command kubectl
Require-Command k3d
Require-Command docker

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = Join-Path $OutputRoot "$ClusterName-$timestamp"
$null = New-Item -Path $backupDir -ItemType Directory -Force

$serverContainer = "k3d-$ClusterName-server-0"
$containerId = docker ps -a --filter "name=^/$serverContainer$" --format "{{.ID}}"
if (-not $containerId) {
    throw "Could not find server container '$serverContainer'. Check cluster name."
}

Write-Host "[1/5] Exporting cluster metadata and namespace resources..."

kubectl config current-context | Out-File -FilePath (Join-Path $backupDir "context.txt") -Encoding utf8
kubectl get nodes -o wide | Out-File -FilePath (Join-Path $backupDir "nodes.txt") -Encoding utf8
kubectl version -o yaml | Out-File -FilePath (Join-Path $backupDir "kubectl-version.yaml") -Encoding utf8

foreach ($namespace in $Namespaces) {
    $nsOut = Join-Path $backupDir "$namespace-resources.yaml"
    try {
        kubectl get all,configmap,secret,serviceaccount,ingress,pvc,role,rolebinding -n $namespace -o yaml | Out-File -FilePath $nsOut -Encoding utf8
        Write-Host "  Exported namespace '$namespace' -> $nsOut"
    }
    catch {
        Write-Warning "Skipping namespace '$namespace' export: $($_.Exception.Message)"
    }
}

Write-Host "[2/5] Exporting CRDs and Argo CD applications..."
kubectl get crd -o yaml | Out-File -FilePath (Join-Path $backupDir "crds.yaml") -Encoding utf8

try {
    kubectl get applications.argoproj.io -n argocd -o yaml | Out-File -FilePath (Join-Path $backupDir "argocd-applications.yaml") -Encoding utf8
}
catch {
    Write-Warning "Could not export Argo CD applications: $($_.Exception.Message)"
}

if (-not $NoClusterStop) {
    Write-Host "[3/5] Stopping cluster '$ClusterName' for consistent sqlite backup..."
    k3d cluster stop $ClusterName | Out-Null
}
else {
    Write-Warning "Skipping cluster stop. sqlite backup may be inconsistent if writes are in progress."
}

Write-Host "[4/5] Copying k3s datastore files from server container..."
$dbTarget = Join-Path $backupDir "k3s-server-db"
$null = New-Item -Path $dbTarget -ItemType Directory -Force
docker cp "${serverContainer}:/var/lib/rancher/k3s/server/db/." $dbTarget

if ($IncludePvData) {
    Write-Host "Copying local-path PV data..."
    $pvTarget = Join-Path $backupDir "k3s-storage"
    $null = New-Item -Path $pvTarget -ItemType Directory -Force
    docker cp "${serverContainer}:/var/lib/rancher/k3s/storage/." $pvTarget
}

if (-not $NoClusterStop) {
    Write-Host "[5/5] Starting cluster '$ClusterName'..."
    k3d cluster start $ClusterName | Out-Null
    kubectl wait --for=condition=Ready node --all --timeout=120s | Out-Null
}

if (-not $NoArchive) {
    $zipPath = "$backupDir.zip"
    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force
    }
    Compress-Archive -Path "$backupDir\*" -DestinationPath $zipPath -CompressionLevel Optimal
    Write-Host "Backup archive created: $zipPath"
}

Write-Host "Backup completed: $backupDir"

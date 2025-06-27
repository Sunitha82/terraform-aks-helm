# AKS Helm Deployment Test Script - PowerShell Version
Write-Host " Starting AKS + Helm deployment testing..." -ForegroundColor Cyan

# Function to check command success
function Check-Status {
    param(
        [string]$Message,
        [int]$ExitCode = $LASTEXITCODE
    )
    
    if ($ExitCode -eq 0) {
        Write-Host " $Message - SUCCESS" -ForegroundColor Green
    } else {
        Write-Host "$Message - FAILED" -ForegroundColor Red
        exit 1
    }
}

# Function to wait for pods
function Wait-ForPods {
    param(
        [string]$Namespace,
        [string]$Label,
        [int]$Timeout = 300
    )
    
    Write-Host " Waiting for pods in namespace '$Namespace' with label '$Label'..." -ForegroundColor Yellow
    kubectl wait --for=condition=ready pod -l $Label -n $Namespace --timeout="${Timeout}s"
    Check-Status "Pods ready in $Namespace"
}

Write-Host " 1. Checking Terraform deployment..." -ForegroundColor Cyan
terraform show > $null 2>&1
Check-Status "Terraform state exists"

Write-Host " 2. Checking AKS cluster..." -ForegroundColor Cyan
$clusterState = az aks show --resource-group rg-aks-terraform --name aks-terraform-cluster --query provisioningState -o tsv
Check-Status "AKS cluster is running"

Write-Host "  3. Getting cluster credentials..." -ForegroundColor Cyan
az aks get-credentials --resource-group rg-aks-terraform --name aks-terraform-cluster --overwrite-existing
Check-Status "Cluster credentials retrieved"

Write-Host "  4. Checking cluster nodes..." -ForegroundColor Cyan
kubectl get nodes
Check-Status "Cluster nodes accessible"

Write-Host "  5. Checking Helm releases..." -ForegroundColor Cyan
helm list --all-namespaces
Check-Status "Helm releases listed"

Write-Host "  6. Testing Ingress Controller..." -ForegroundColor Cyan
Wait-ForPods "ingress-nginx" "app.kubernetes.io/name=ingress-nginx"

# Get external IP
$externalIP = kubectl get svc -n ingress-nginx nginx-ingress-ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null

if ([string]::IsNullOrEmpty($externalIP)) {
    Write-Host "    External IP not yet assigned, waiting..." -ForegroundColor Yellow
    Start-Sleep -Seconds 30
    $externalIP = kubectl get svc -n ingress-nginx nginx-ingress-ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
}

if (-not [string]::IsNullOrEmpty($externalIP)) {
    Write-Host "   External IP: $externalIP" -ForegroundColor Green
} else {
    Write-Host "   External IP not found" -ForegroundColor Red
}

Write-Host "  7. Testing Monitoring Stack..." -ForegroundColor Cyan
Wait-ForPods "monitoring" "app.kubernetes.io/name=grafana"

Write-Host "  8. Testing Cert-Manager..." -ForegroundColor Cyan
Wait-ForPods "cert-manager" "app.kubernetes.io/name=cert-manager"

Write-Host "  9. Deploying test application..." -ForegroundColor Cyan
kubectl apply -f test-app.yaml
Check-Status "Test application deployed"
Wait-ForPods "default" "app=test-app"

Write-Host "  10. Testing application accessibility..." -ForegroundColor Cyan
if (-not [string]::IsNullOrEmpty($externalIP)) {
    Write-Host "Testing HTTP access..." -ForegroundColor Yellow
    try {
        $response = Invoke-WebRequest -Uri "http://$externalIP/" -Headers @{"Host" = "test-app.local"} -TimeoutSec 10 -UseBasicParsing
        $httpStatus = $response.StatusCode
        
        if ($httpStatus -eq 200) {
            Write-Host " Application accessible via HTTP" -ForegroundColor Green
        } else {
            Write-Host " HTTP Status: $httpStatus" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "    HTTP request failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host "  11. Resource summary..." -ForegroundColor Cyan
Write-Host "=== NAMESPACES ===" -ForegroundColor White
kubectl get namespaces

Write-Host "=== DEPLOYMENTS ===" -ForegroundColor White
kubectl get deployments --all-namespaces

Write-Host "=== SERVICES ===" -ForegroundColor White
kubectl get services --all-namespaces

Write-Host "=== INGRESS ===" -ForegroundColor White
kubectl get ingress --all-namespaces

Write-Host "=== HELM RELEASES ===" -ForegroundColor White
helm list --all-namespaces

Write-Host ""
Write-Host " Testing completed!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Access Grafana: kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80" -ForegroundColor White
Write-Host "2. Access test app: Add '$externalIP test-app.local' to your hosts file" -ForegroundColor White
Write-Host "3. View logs: kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx" -ForegroundColor White
Write-Host "4. Clean up test app: kubectl delete -f test-app.yaml" -ForegroundColor White

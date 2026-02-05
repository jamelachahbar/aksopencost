#############################################################################
# Load Generator Script for OpenCost Demo
# 
# This script generates traffic and resource usage to demonstrate
# OpenCost cost monitoring capabilities.
#############################################################################

Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "OpenCost Load Generator" -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan

# Get the nginx service external IP
Write-Host "`nGetting nginx service external IP..." -ForegroundColor Yellow
$NGINX_IP = kubectl get service nginx-sample-service -n sample-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null

if (-not $NGINX_IP) {
    Write-Host "External IP not available. Using port-forward instead..." -ForegroundColor Yellow
    Write-Host "Starting port-forward in background..." -ForegroundColor Gray
    Start-Job -ScriptBlock { kubectl port-forward service/nginx-sample-service 8080:80 -n sample-app } | Out-Null
    Start-Sleep -Seconds 3
    $NGINX_URL = "http://localhost:8080"
} else {
    $NGINX_URL = "http://$NGINX_IP"
    Write-Host "Nginx URL: $NGINX_URL" -ForegroundColor Green
}

# ============================================================================
# Deploy Load Generator Pod
# ============================================================================
Write-Host "`nDeploying load generator pod..." -ForegroundColor Cyan

$loadGeneratorYaml = @"
apiVersion: v1
kind: Pod
metadata:
  name: load-generator
  namespace: sample-app
  labels:
    app: load-generator
spec:
  containers:
  - name: busybox
    image: busybox:latest
    command: ["/bin/sh"]
    args: ["-c", "while true; do wget -q -O- http://nginx-sample-service.sample-app.svc.cluster.local > /dev/null 2>&1; done"]
    resources:
      requests:
        cpu: "50m"
        memory: "32Mi"
      limits:
        cpu: "100m"
        memory: "64Mi"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: stress-test
  namespace: sample-app
  labels:
    app: stress-test
spec:
  replicas: 2
  selector:
    matchLabels:
      app: stress-test
  template:
    metadata:
      labels:
        app: stress-test
    spec:
      containers:
      - name: stress
        image: progrium/stress
        command: ["stress"]
        args: ["--cpu", "1", "--vm", "1", "--vm-bytes", "64M", "--timeout", "3600s"]
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "200m"
            memory: "256Mi"
---
apiVersion: batch/v1
kind: Job
metadata:
  name: http-load-test
  namespace: sample-app
spec:
  parallelism: 3
  completions: 10
  template:
    metadata:
      labels:
        app: http-load-test
    spec:
      containers:
      - name: curl
        image: curlimages/curl:latest
        command: ["/bin/sh"]
        args:
        - "-c"
        - |
          for i in `$(seq 1 1000); do
            curl -s -o /dev/null http://nginx-sample-service.sample-app.svc.cluster.local
            sleep 0.1
          done
        resources:
          requests:
            cpu: "25m"
            memory: "32Mi"
          limits:
            cpu: "50m"
            memory: "64Mi"
      restartPolicy: Never
  backoffLimit: 4
"@

$loadGeneratorYaml | Out-File -FilePath "load-generator.yaml" -Encoding UTF8
kubectl apply -f load-generator.yaml

Write-Host "`nLoad generators deployed!" -ForegroundColor Green

# ============================================================================
# Generate HTTP Traffic from Local Machine
# ============================================================================
Write-Host "`n============================================================================" -ForegroundColor Cyan
Write-Host "Generating HTTP traffic for 60 seconds..." -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan

$duration = 60
$startTime = Get-Date
$requestCount = 0

while ((Get-Date) -lt $startTime.AddSeconds($duration)) {
    try {
        Invoke-WebRequest -Uri $NGINX_URL -UseBasicParsing -TimeoutSec 5 | Out-Null
        $requestCount++
    } catch {
        # Ignore errors, keep trying
    }
    
    if ($requestCount % 50 -eq 0) {
        $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
        Write-Host "  Requests sent: $requestCount (${elapsed}s elapsed)" -ForegroundColor Gray
    }
    
    Start-Sleep -Milliseconds 100
}

Write-Host "`nCompleted $requestCount requests in $duration seconds" -ForegroundColor Green

# ============================================================================
# Show Current Resource Usage
# ============================================================================
Write-Host "`n============================================================================" -ForegroundColor Cyan
Write-Host "Current Resource Usage" -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan

Write-Host "`n=== Pods in sample-app namespace ===" -ForegroundColor Yellow
kubectl get pods -n sample-app

Write-Host "`n=== Resource usage (kubectl top) ===" -ForegroundColor Yellow
kubectl top pods -n sample-app 2>$null

Write-Host "`n=== Node resource usage ===" -ForegroundColor Yellow
kubectl top nodes 2>$null

# ============================================================================
# Instructions
# ============================================================================
Write-Host "`n============================================================================" -ForegroundColor Green
Write-Host "LOAD GENERATION ACTIVE!" -ForegroundColor Green
Write-Host "============================================================================" -ForegroundColor Green

Write-Host "`nThe following load generators are running in your cluster:" -ForegroundColor Cyan
Write-Host "  - load-generator: Continuous HTTP requests to nginx" -ForegroundColor White
Write-Host "  - stress-test (2 replicas): CPU and memory stress" -ForegroundColor White  
Write-Host "  - http-load-test (Job): Batch HTTP requests" -ForegroundColor White

Write-Host "`nTo check OpenCost allocation, wait 5-10 minutes then:" -ForegroundColor Cyan
Write-Host "  curl `"http://<OPENCOST_IP>:9003/allocation/compute?window=30m&aggregate=namespace`"" -ForegroundColor White

Write-Host "`nTo stop the load generators:" -ForegroundColor Cyan
Write-Host "  kubectl delete -f load-generator.yaml" -ForegroundColor White

Write-Host "`nTo monitor resource usage:" -ForegroundColor Cyan
Write-Host "  kubectl top pods -n sample-app --watch" -ForegroundColor White
Write-Host "  kubectl top nodes --watch" -ForegroundColor White

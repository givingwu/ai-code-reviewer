#!/bin/bash

# Cleanup script for AI Code Reviewer deployment
# This script removes all resources from the test environment

set -e

NAMESPACE="test"
APP_NAME="ai-code-reviewer"

echo "🧹 Starting cleanup of $APP_NAME from $NAMESPACE namespace..."

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed or not in PATH"
    exit 1
fi

# Delete deployment
echo "🚢 Deleting Deployment..."
kubectl delete -f deployment.yaml --ignore-not-found=true

# Delete ingress
echo "🔗 Deleting Ingress..."
kubectl delete -f ingress.yaml --ignore-not-found=true

# Delete service
echo "🌐 Deleting Service..."
kubectl delete -f service.yaml --ignore-not-found=true

# Delete PVC (this will also delete the PV and data)
echo "💾 Deleting PersistentVolumeClaim..."
kubectl delete -f pvc.yaml --ignore-not-found=true

# Delete secret
echo "🔐 Deleting Secret..."
kubectl delete -f secret.yaml --ignore-not-found=true

# Delete configmap
echo "⚙️  Deleting ConfigMap..."
kubectl delete -f configmap.yaml --ignore-not-found=true

# Optionally delete namespace (uncomment if you want to remove the entire namespace)
# echo "📦 Deleting namespace..."
# kubectl delete -f namespace.yaml --ignore-not-found=true

echo "✅ Cleanup completed successfully!"
echo ""
echo "📝 Note: The namespace '$NAMESPACE' was not deleted."
echo "To delete it manually, run: kubectl delete namespace $NAMESPACE"
# Kubernetes 部署文档

本目录包含将 AI 代码审查应用部署到阿里云 Kubernetes 集群所需的所有资源清单文件。

## 文件结构

```
k8s/
├── namespace.yaml      # 测试环境命名空间
├── configmap.yaml      # 应用程序配置
├── secret.yaml         # 敏感信息存储
├── pvc.yaml           # 持久化存储声明
├── deployment.yaml     # 应用程序部署
├── service.yaml       # 服务定义
├── ingress.yaml       # 外部访问配置
├── deploy.sh          # 部署脚本
├── cleanup.sh         # 清理脚本
└── README.md          # 本文档
```

## 部署前准备

### 1. 环境要求

- Kubernetes 集群 (版本 1.19+)
- kubectl 命令行工具
- 阿里云容器镜像服务 (ACR) 访问权限
- Nginx Ingress Controller
- cert-manager (用于 TLS 证书)

### 2. 配置更新

在部署前，需要更新以下配置：

#### 更新镜像地址
编辑 `deployment.yaml`，将镜像地址替换为实际的 ACR 地址：
```yaml
image: registry.cn-hangzhou.aliyuncs.com/your-namespace/ai-code-reviewer:latest
```

#### 更新域名
编辑 `ingress.yaml`，将域名替换为实际域名：
```yaml
- host: ai-code-reviewer.test.your-domain.com
```

#### 配置密钥
部署后需要更新 Secret 中的实际令牌值：
```bash
# GitLab Token
kubectl patch secret ai-code-reviewer-secrets -n test --type='json' \
  -p='[{"op": "replace", "path": "/data/gitlab-token", "value":"'$(echo -n "your-gitlab-token" | base64)'"}]'

# Dify Token
kubectl patch secret ai-code-reviewer-secrets -n test --type='json' \
  -p='[{"op": "replace", "path": "/data/dify-token", "value":"'$(echo -n "your-dify-token" | base64)'"}]'

# TV Bot ID
kubectl patch secret ai-code-reviewer-secrets -n test --type='json' \
  -p='[{"op": "replace", "path": "/data/tv-bot-id", "value":"'$(echo -n "your-tv-bot-id" | base64)'"}]'

# TV Bot Token
kubectl patch secret ai-code-reviewer-secrets -n test --type='json' \
  -p='[{"op": "replace", "path": "/data/tv-bot-token", "value":"'$(echo -n "your-tv-bot-token" | base64)'"}]'
```

## 部署步骤

### 1. 快速部署
```bash
# 使用部署脚本
./deploy.sh
```

### 2. 手动部署
```bash
# 1. 创建命名空间
kubectl apply -f namespace.yaml

# 2. 创建配置
kubectl apply -f configmap.yaml

# 3. 创建密钥
kubectl apply -f secret.yaml

# 4. 创建存储
kubectl apply -f pvc.yaml

# 5. 创建服务
kubectl apply -f service.yaml

# 6. 创建 Ingress
kubectl apply -f ingress.yaml

# 7. 创建部署
kubectl apply -f deployment.yaml
```

## 验证部署

### 1. 检查 Pod 状态
```bash
kubectl get pods -n test -l app=ai-code-reviewer
```

### 2. 查看日志
```bash
kubectl logs -n test -l app=ai-code-reviewer -f
```

### 3. 检查服务
```bash
kubectl get svc -n test -l app=ai-code-reviewer
```

### 4. 检查 Ingress
```bash
kubectl get ingress -n test -l app=ai-code-reviewer
```

### 5. 测试健康检查
```bash
# 端口转发到本地
kubectl port-forward -n test svc/ai-code-reviewer-service 8081:8081

# 测试健康检查端点
curl http://localhost:8081/health
curl http://localhost:8081/ready
curl http://localhost:8081/startup
```

### 6. 测试 Webhook 端点
```bash
# 通过 Ingress 测试
curl -X POST https://ai-code-reviewer.test.your-domain.com/webhook \
  -H "Content-Type: application/json" \
  -d '{"test": "data"}'
```

## 资源配置说明

### Deployment 配置
- **副本数**: 1 (测试环境)
- **资源请求**: CPU 200m, Memory 256Mi
- **资源限制**: CPU 500m, Memory 512Mi
- **重启策略**: Always
- **更新策略**: Recreate

### 健康检查配置
- **存活探针**: `/health` 端点，30秒后开始检查
- **就绪探针**: `/ready` 端点，10秒后开始检查
- **启动探针**: `/startup` 端点，支持慢启动应用

### 存储配置
- **PVC 大小**: 10Gi
- **访问模式**: ReadWriteOnce
- **存储类**: alicloud-disk-ssd

### 网络配置
- **Service 类型**: ClusterIP
- **端口映射**: 80 -> 4195 (HTTP), 8081 (健康检查), 9090 (指标)
- **Ingress**: 支持 HTTPS，自动重定向

## 故障排除

### 1. Pod 无法启动
```bash
# 查看 Pod 事件
kubectl describe pod -n test -l app=ai-code-reviewer

# 查看详细日志
kubectl logs -n test -l app=ai-code-reviewer --previous
```

### 2. 健康检查失败
```bash
# 检查健康检查端点
kubectl exec -n test -it deployment/ai-code-reviewer -- curl localhost:8081/health
```

### 3. 存储问题
```bash
# 检查 PVC 状态
kubectl get pvc -n test

# 检查存储类
kubectl get storageclass
```

### 4. 网络连接问题
```bash
# 检查服务端点
kubectl get endpoints -n test

# 测试服务连接
kubectl run test-pod --rm -i --tty --image=busybox -- /bin/sh
# 在 Pod 内测试: wget -qO- ai-code-reviewer-service.test.svc.cluster.local
```

## 清理部署

### 1. 快速清理
```bash
./cleanup.sh
```

### 2. 手动清理
```bash
kubectl delete -f deployment.yaml
kubectl delete -f ingress.yaml
kubectl delete -f service.yaml
kubectl delete -f pvc.yaml
kubectl delete -f secret.yaml
kubectl delete -f configmap.yaml
# kubectl delete -f namespace.yaml  # 可选：删除整个命名空间
```

## 安全注意事项

1. **密钥管理**: 确保所有敏感信息都存储在 Kubernetes Secret 中
2. **网络策略**: 考虑实施网络策略限制 Pod 间通信
3. **RBAC**: 配置适当的角色和权限
4. **镜像安全**: 定期扫描和更新容器镜像
5. **TLS 配置**: 确保所有外部通信都使用 HTTPS

## 监控和日志

- 应用程序日志会输出到标准输出，可通过 `kubectl logs` 查看
- 健康检查端点：`/health`, `/ready`, `/startup`
- 指标端点：`:9090/metrics` (如果配置了 Prometheus)
- 建议配置日志收集系统（如 Fluent Bit）进行集中日志管理
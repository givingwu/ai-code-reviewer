# AI 代码审查应用部署指南

## 概述

本文档提供了将 AI 代码审查应用部署到阿里云 Kubernetes 集群的完整步骤和配置说明。该应用基于 Benthos 消息处理器和 Dify AI 工作流，通过 GitLab Webhook 接收代码审查请求。

## 前置条件

### 环境要求

- 阿里云 Kubernetes 集群 (ACK)
- Jenkins 服务器
- 阿里云容器镜像服务 (ACR) 访问权限
- kubectl 命令行工具
- Docker 环境

### 必需的访问凭据

- GitLab Private Token
- Dify API Token
- TV Bot 配置信息
- 阿里云 ACR 访问密钥

## 部署步骤

### 第一步：准备 Kubernetes 集群

1. **创建命名空间**
```bash
kubectl create namespace test
kubectl config set-context --current --namespace=test
```

2. **验证集群连接**
```bash
kubectl cluster-info
kubectl get nodes
```

### 第二步：配置 Secret 和 ConfigMap

1. **创建 Secret 资源**
```bash
# 创建包含敏感信息的 Secret
kubectl create secret generic ai-code-reviewer-secrets \
  --from-literal=gitlab-token="your-gitlab-token" \
  --from-literal=dify-token="your-dify-token" \
  --from-literal=tv-bot-id="your-tv-bot-id" \
  --namespace=test
```

2. **应用 ConfigMap**
```bash
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/configmap-env.yaml
```

### 第三步：部署应用程序

1. **创建持久化存储**
```bash
kubectl apply -f k8s/pvc.yaml
```

2. **部署应用程序**
```bash
kubectl apply -f k8s/deployment.yaml
```

3. **创建服务**
```bash
kubectl apply -f k8s/service.yaml
```

4. **配置 Ingress**
```bash
kubectl apply -f k8s/ingress.yaml
```

### 第四步：验证部署

1. **检查 Pod 状态**
```bash
kubectl get pods -l app=ai-code-reviewer
kubectl describe pod <pod-name>
```

2. **检查服务状态**
```bash
kubectl get svc ai-code-reviewer
kubectl get ingress ai-code-reviewer
```

3. **验证应用程序健康状态**
```bash
# 通过 port-forward 测试健康检查端点
kubectl port-forward svc/ai-code-reviewer 8080:80
curl http://localhost:8080/health
```

### 第五步：配置 Jenkins 流水线

1. **创建 Jenkins 凭据**
   - 在 Jenkins 中添加阿里云 ACR 凭据
   - 添加 Kubernetes 集群访问凭据
   - 添加 GitLab 访问凭据

2. **配置 Jenkins 流水线**
   - 创建新的流水线项目
   - 配置 Git 仓库连接
   - 使用项目根目录的 Jenkinsfile

3. **测试流水线**
   - 手动触发构建
   - 验证各个阶段执行成功
   - 检查部署结果

## 配置文件说明

### Deployment 配置

```yaml
# k8s/deployment.yaml 关键配置项
spec:
  replicas: 1                    # 副本数量
  template:
    spec:
      containers:
      - name: ai-code-reviewer
        image: your-registry/ai-code-reviewer:latest
        ports:
        - containerPort: 4195    # Benthos HTTP 服务端口
        resources:
          requests:
            cpu: 200m            # CPU 请求
            memory: 256Mi        # 内存请求
          limits:
            cpu: 500m            # CPU 限制
            memory: 512Mi        # 内存限制
```

### Service 配置

```yaml
# k8s/service.yaml 关键配置项
spec:
  type: ClusterIP
  ports:
  - port: 80                     # 服务端口
    targetPort: 4195             # 容器端口
    protocol: TCP
  selector:
    app: ai-code-reviewer        # Pod 选择器
```

### Ingress 配置

```yaml
# k8s/ingress.yaml 关键配置项
spec:
  tls:
  - hosts:
    - ai-code-reviewer.test.example.com
    secretName: tls-secret       # TLS 证书 Secret
  rules:
  - host: ai-code-reviewer.test.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ai-code-reviewer
            port:
              number: 80
```

## 环境变量配置

### 必需的环境变量

| 变量名 | 描述 | 示例值 | 来源 |
|--------|------|--------|------|
| `GITLAB_TOKEN` | GitLab 私有访问令牌 | `glpat-xxxxxxxxxxxx` | Secret |
| `DIFY_TOKEN` | Dify API 访问令牌 | `app-xxxxxxxxxxxx` | Secret |
| `TV_BOT_ID` | TV Bot 配置 ID | `bot-xxxxxxxxxxxx` | Secret |
| `LOG_LEVEL` | 日志级别 | `INFO` | ConfigMap |
| `TIMEOUT` | 请求超时时间（秒） | `1800` | ConfigMap |
| `MAX_PAYLOAD_SIZE` | 最大负载大小（字节） | `102400` | ConfigMap |

### 可选的环境变量

| 变量名 | 描述 | 默认值 | 来源 |
|--------|------|--------|------|
| `HTTP_PORT` | HTTP 服务端口 | `4195` | ConfigMap |
| `HEALTH_CHECK_PATH` | 健康检查路径 | `/health` | ConfigMap |
| `METRICS_ENABLED` | 启用指标收集 | `true` | ConfigMap |
| `DEBUG_MODE` | 调试模式 | `false` | ConfigMap |

## 网络配置

### 端口配置

- **容器端口**: 4195 (Benthos HTTP 服务器)
- **服务端口**: 80 (Kubernetes Service)
- **Ingress 端口**: 443 (HTTPS), 80 (HTTP 重定向)

### 域名配置

- **测试环境**: `ai-code-reviewer.test.example.com`
- **生产环境**: `ai-code-reviewer.prod.example.com`

### 防火墙规则

确保以下端口在集群中可访问：
- 入站：443 (HTTPS), 80 (HTTP)
- 出站：443 (HTTPS 到外部 API), 80 (HTTP)

## 安全配置

### RBAC 配置

```yaml
# 为应用程序创建 ServiceAccount
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ai-code-reviewer
  namespace: test
---
# 创建最小权限的 Role
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ai-code-reviewer-role
  namespace: test
rules:
- apiGroups: [""]
  resources: ["configmaps", "secrets"]
  verbs: ["get", "list"]
```

### 容器安全

```yaml
# Deployment 中的安全配置
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 2000
  capabilities:
    drop:
    - ALL
  readOnlyRootFilesystem: true
```

## 监控配置

### 健康检查

```yaml
# Deployment 中的健康检查配置
livenessProbe:
  httpGet:
    path: /health
    port: 4195
  initialDelaySeconds: 30
  periodSeconds: 10
readinessProbe:
  httpGet:
    path: /ready
    port: 4195
  initialDelaySeconds: 5
  periodSeconds: 5
startupProbe:
  httpGet:
    path: /startup
    port: 4195
  initialDelaySeconds: 10
  periodSeconds: 10
  failureThreshold: 30
```

### 资源监控

```yaml
# 资源限制和请求
resources:
  requests:
    cpu: 200m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

## 备份和恢复

### 配置备份

```bash
# 备份所有配置
kubectl get all,configmap,secret,ingress -n test -o yaml > backup-$(date +%Y%m%d).yaml

# 备份特定资源
kubectl get configmap ai-code-reviewer-config -n test -o yaml > configmap-backup.yaml
kubectl get secret ai-code-reviewer-secrets -n test -o yaml > secret-backup.yaml
```

### 恢复配置

```bash
# 从备份恢复
kubectl apply -f backup-20240101.yaml

# 恢复特定资源
kubectl apply -f configmap-backup.yaml
kubectl apply -f secret-backup.yaml
```

## 更新和升级

### 应用程序更新

1. **构建新镜像**
```bash
# 通过 Jenkins 流水线自动构建
# 或手动构建
docker build -t your-registry/ai-code-reviewer:v1.1.0 .
docker push your-registry/ai-code-reviewer:v1.1.0
```

2. **更新部署**
```bash
kubectl set image deployment/ai-code-reviewer \
  ai-code-reviewer=your-registry/ai-code-reviewer:v1.1.0 \
  -n test
```

3. **验证更新**
```bash
kubectl rollout status deployment/ai-code-reviewer -n test
kubectl get pods -l app=ai-code-reviewer -n test
```

### 配置更新

1. **更新 ConfigMap**
```bash
kubectl apply -f k8s/configmap.yaml
```

2. **重启应用程序以加载新配置**
```bash
kubectl rollout restart deployment/ai-code-reviewer -n test
```

## 性能调优

### 资源调优

根据实际使用情况调整资源配置：

```yaml
# 高负载环境
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 1Gi

# 低负载环境
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi
```

### 并发调优

在 ConfigMap 中调整 Benthos 配置：

```yaml
# 高并发配置
input:
  http_server:
    address: "0.0.0.0:4195"
    path: /webhook
    allowed_verbs: [POST]
    timeout: "30s"
    rate_limit: "100/s"
```

## 故障排除快速参考

### 常见问题

1. **Pod 无法启动**
   - 检查镜像是否存在
   - 验证 Secret 和 ConfigMap 配置
   - 查看 Pod 事件和日志

2. **服务无法访问**
   - 检查 Service 和 Ingress 配置
   - 验证网络策略
   - 测试 DNS 解析

3. **健康检查失败**
   - 检查健康检查端点
   - 验证应用程序启动状态
   - 调整探针参数

### 有用的命令

```bash
# 查看 Pod 日志
kubectl logs -f deployment/ai-code-reviewer -n test

# 进入 Pod 调试
kubectl exec -it <pod-name> -n test -- /bin/sh

# 查看事件
kubectl get events -n test --sort-by='.lastTimestamp'

# 端口转发测试
kubectl port-forward svc/ai-code-reviewer 8080:80 -n test
```
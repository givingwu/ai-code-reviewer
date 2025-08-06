# 配置参数参考文档

## 概述

本文档详细描述了 AI 代码审查应用的所有环境变量、配置参数和设置选项。该应用基于 Benthos 消息处理器和 Dify AI 工作流，部署在 Kubernetes 环境中。

## 环境变量

### 必需的环境变量

这些环境变量是应用程序正常运行所必需的，必须在部署前配置。

#### GitLab 集成配置

| 变量名 | 描述 | 示例值 | 来源 | 验证方法 |
|--------|------|--------|------|----------|
| `GITLAB_TOKEN` | GitLab 私有访问令牌，用于访问 GitLab API | `glpat-xxxxxxxxxxxxxxxxxxxx` | Secret | `curl -H "PRIVATE-TOKEN: $GITLAB_TOKEN" https://gitlab.com/api/v4/user` |
| `GITLAB_URL` | GitLab 实例的基础 URL | `https://gitlab.com` | ConfigMap | `curl -I $GITLAB_URL` |
| `GITLAB_PROJECT_ID` | GitLab 项目 ID（可选，用于特定项目） | `12345` | ConfigMap | 在 GitLab 项目设置中查看 |

#### Dify AI 服务配置

| 变量名 | 描述 | 示例值 | 来源 | 验证方法 |
|--------|------|--------|------|----------|
| `DIFY_TOKEN` | Dify API 访问令牌 | `app-xxxxxxxxxxxxxxxxxxxx` | Secret | `curl -H "Authorization: Bearer $DIFY_TOKEN" https://api.dify.ai/v1/workflows` |
| `DIFY_API_URL` | Dify API 基础 URL | `https://api.dify.ai` | ConfigMap | `curl -I $DIFY_API_URL` |
| `DIFY_WORKFLOW_ID` | Dify 工作流 ID | `workflow-xxxxxxxxxxxx` | ConfigMap | 在 Dify 控制台中查看 |

#### TV Bot 配置

| 变量名 | 描述 | 示例值 | 来源 | 验证方法 |
|--------|------|--------|------|----------|
| `TV_BOT_ID` | TV Bot 配置 ID | `bot-xxxxxxxxxxxxxxxxxxxx` | Secret | 根据 TV Bot API 文档验证 |
| `TV_BOT_URL` | TV Bot API 端点 | `https://api.tvbot.com` | ConfigMap | `curl -I $TV_BOT_URL` |

### 可选的环境变量

这些环境变量有默认值，可以根据需要进行调整。

#### 应用程序配置

| 变量名 | 描述 | 默认值 | 示例值 | 来源 |
|--------|------|--------|--------|------|
| `HTTP_PORT` | HTTP 服务器监听端口 | `4195` | `8080` | ConfigMap |
| `LOG_LEVEL` | 日志级别 | `INFO` | `DEBUG`, `WARN`, `ERROR` | ConfigMap |
| `TIMEOUT` | 请求超时时间（秒） | `1800` | `3600` | ConfigMap |
| `MAX_PAYLOAD_SIZE` | 最大负载大小（字节） | `102400` | `204800` | ConfigMap |
| `WORKER_THREADS` | 工作线程数 | `4` | `8` | ConfigMap |

#### 健康检查配置

| 变量名 | 描述 | 默认值 | 示例值 | 来源 |
|--------|------|--------|--------|------|
| `HEALTH_CHECK_PATH` | 健康检查端点路径 | `/health` | `/healthz` | ConfigMap |
| `READY_CHECK_PATH` | 就绪检查端点路径 | `/ready` | `/readiness` | ConfigMap |
| `STARTUP_CHECK_PATH` | 启动检查端点路径 | `/startup` | `/startup` | ConfigMap |
| `HEALTH_CHECK_INTERVAL` | 健康检查间隔（秒） | `10` | `30` | ConfigMap |

#### 性能调优配置

| 变量名 | 描述 | 默认值 | 示例值 | 来源 |
|--------|------|--------|--------|------|
| `MAX_CONCURRENT_REQUESTS` | 最大并发请求数 | `10` | `50` | ConfigMap |
| `REQUEST_QUEUE_SIZE` | 请求队列大小 | `100` | `500` | ConfigMap |
| `CONNECTION_POOL_SIZE` | 连接池大小 | `20` | `50` | ConfigMap |
| `IDLE_TIMEOUT` | 空闲连接超时（秒） | `300` | `600` | ConfigMap |

#### 调试和开发配置

| 变量名 | 描述 | 默认值 | 示例值 | 来源 |
|--------|------|--------|--------|------|
| `DEBUG_MODE` | 启用调试模式 | `false` | `true` | ConfigMap |
| `METRICS_ENABLED` | 启用指标收集 | `true` | `false` | ConfigMap |
| `PROFILING_ENABLED` | 启用性能分析 | `false` | `true` | ConfigMap |
| `TRACE_ENABLED` | 启用请求跟踪 | `false` | `true` | ConfigMap |

## Kubernetes 配置

### ConfigMap 配置

#### 主配置文件 (ai-code-reviewer-config)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ai-code-reviewer-config
  namespace: test
data:
  # Benthos 接收器配置
  receiver.yaml: |
    input:
      http_server:
        address: "0.0.0.0:4195"
        path: /webhook
        allowed_verbs: [POST]
        timeout: "30s"
        rate_limit: "100/s"
        cors:
          enabled: true
          allowed_origins: ["*"]
          allowed_headers: ["Content-Type", "Authorization"]
    
    pipeline:
      processors:
        - log:
            level: INFO
            message: "Received webhook request"
        - catch:
            - log:
                level: ERROR
                message: "Error processing request: ${! error() }"
    
    output:
      http_client:
        url: "http://localhost:8080/process"
        verb: POST
        headers:
          Content-Type: "application/json"
        timeout: "30m"
        retry_period: "5s"
        max_retry_backoff: "30s"
        retries: 3
  
  # 应用程序配置
  app-config.yaml: |
    # 基础配置
    timeout: 1800
    max_payload_size: 102400
    log_level: INFO
    worker_threads: 4
    
    # HTTP 服务器配置
    http:
      port: 4195
      read_timeout: 30
      write_timeout: 30
      idle_timeout: 120
    
    # 外部服务配置
    services:
      gitlab:
        url: "https://gitlab.com"
        timeout: 30
        retry_attempts: 3
      
      dify:
        url: "https://api.dify.ai"
        timeout: 1800
        retry_attempts: 3
      
      tv_bot:
        url: "https://api.tvbot.com"
        timeout: 30
        retry_attempts: 3
    
    # 性能配置
    performance:
      max_concurrent_requests: 10
      request_queue_size: 100
      connection_pool_size: 20
      idle_timeout: 300
    
    # 监控配置
    monitoring:
      metrics_enabled: true
      health_check_interval: 10
      profiling_enabled: false
      trace_enabled: false
```

#### 环境特定配置 (ai-code-reviewer-env)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ai-code-reviewer-env
  namespace: test
data:
  # 环境变量
  HTTP_PORT: "4195"
  LOG_LEVEL: "INFO"
  TIMEOUT: "1800"
  MAX_PAYLOAD_SIZE: "102400"
  WORKER_THREADS: "4"
  
  # 健康检查配置
  HEALTH_CHECK_PATH: "/health"
  READY_CHECK_PATH: "/ready"
  STARTUP_CHECK_PATH: "/startup"
  HEALTH_CHECK_INTERVAL: "10"
  
  # 性能配置
  MAX_CONCURRENT_REQUESTS: "10"
  REQUEST_QUEUE_SIZE: "100"
  CONNECTION_POOL_SIZE: "20"
  IDLE_TIMEOUT: "300"
  
  # 功能开关
  DEBUG_MODE: "false"
  METRICS_ENABLED: "true"
  PROFILING_ENABLED: "false"
  TRACE_ENABLED: "false"
  
  # 外部服务 URL
  GITLAB_URL: "https://gitlab.com"
  DIFY_API_URL: "https://api.dify.ai"
  TV_BOT_URL: "https://api.tvbot.com"
```

### Secret 配置

#### 敏感信息配置 (ai-code-reviewer-secrets)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ai-code-reviewer-secrets
  namespace: test
type: Opaque
data:
  # GitLab 配置（Base64 编码）
  gitlab-token: Z2xwYXQteHh4eHh4eHh4eHh4eHh4eHh4eHh4eA==
  gitlab-project-id: MTIzNDU=
  
  # Dify 配置（Base64 编码）
  dify-token: YXBwLXh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eA==
  dify-workflow-id: d29ya2Zsb3cteHh4eHh4eHh4eHh4eA==
  
  # TV Bot 配置（Base64 编码）
  tv-bot-id: Ym90LXh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eA==
  
  # 数据库配置（如果需要）
  database-url: cG9zdGdyZXNxbDovL3VzZXI6cGFzc0Bsb2NhbGhvc3Q6NTQzMi9kYg==
  
  # 加密密钥
  encryption-key: bXlfc2VjcmV0X2VuY3J5cHRpb25fa2V5XzEyMw==
```

### Deployment 配置

#### 资源配置

```yaml
# 资源请求和限制
resources:
  requests:
    cpu: 200m          # 最小 CPU 需求
    memory: 256Mi      # 最小内存需求
  limits:
    cpu: 500m          # 最大 CPU 限制
    memory: 512Mi      # 最大内存限制
    ephemeral-storage: 1Gi  # 临时存储限制

# 不同环境的资源配置建议
# 开发环境
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi

# 测试环境
resources:
  requests:
    cpu: 200m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi

# 生产环境
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 1Gi
```

#### 健康检查配置

```yaml
# 存活探针
livenessProbe:
  httpGet:
    path: /health
    port: 4195
    scheme: HTTP
  initialDelaySeconds: 30    # 初始延迟
  periodSeconds: 10          # 检查间隔
  timeoutSeconds: 5          # 超时时间
  successThreshold: 1        # 成功阈值
  failureThreshold: 3        # 失败阈值

# 就绪探针
readinessProbe:
  httpGet:
    path: /ready
    port: 4195
    scheme: HTTP
  initialDelaySeconds: 5
  periodSeconds: 5
  timeoutSeconds: 3
  successThreshold: 1
  failureThreshold: 3

# 启动探针
startupProbe:
  httpGet:
    path: /startup
    port: 4195
    scheme: HTTP
  initialDelaySeconds: 10
  periodSeconds: 10
  timeoutSeconds: 5
  successThreshold: 1
  failureThreshold: 30       # 允许更长的启动时间
```

#### 安全配置

```yaml
# 安全上下文
securityContext:
  runAsNonRoot: true         # 不以 root 用户运行
  runAsUser: 1000           # 指定用户 ID
  runAsGroup: 2000          # 指定组 ID
  fsGroup: 2000             # 文件系统组 ID
  capabilities:
    drop:
    - ALL                   # 删除所有能力
    add:
    - NET_BIND_SERVICE      # 仅添加必需的能力
  readOnlyRootFilesystem: true  # 只读根文件系统
  allowPrivilegeEscalation: false  # 禁止权限提升

# 网络策略
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ai-code-reviewer-netpol
spec:
  podSelector:
    matchLabels:
      app: ai-code-reviewer
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 4195
  egress:
  - to: []  # 允许所有出站流量
    ports:
    - protocol: TCP
      port: 443  # HTTPS
    - protocol: TCP
      port: 80   # HTTP
    - protocol: UDP
      port: 53   # DNS
```

## 配置验证

### 环境变量验证脚本

```bash
#!/bin/bash
# validate-config.sh

echo "=== 验证环境变量配置 ==="

# 检查必需的环境变量
REQUIRED_VARS=(
    "GITLAB_TOKEN"
    "DIFY_TOKEN"
    "TV_BOT_ID"
)

for var in "${REQUIRED_VARS[@]}"; do
    if kubectl get secret ai-code-reviewer-secrets -n test -o jsonpath="{.data.$var}" | base64 -d > /dev/null 2>&1; then
        echo "✓ $var 已配置"
    else
        echo "✗ $var 未配置或无效"
    fi
done

# 检查可选的环境变量
OPTIONAL_VARS=(
    "HTTP_PORT"
    "LOG_LEVEL"
    "TIMEOUT"
    "MAX_PAYLOAD_SIZE"
)

for var in "${OPTIONAL_VARS[@]}"; do
    if kubectl get configmap ai-code-reviewer-env -n test -o jsonpath="{.data.$var}" > /dev/null 2>&1; then
        value=$(kubectl get configmap ai-code-reviewer-env -n test -o jsonpath="{.data.$var}")
        echo "✓ $var = $value"
    else
        echo "! $var 使用默认值"
    fi
done

echo "=== 验证外部服务连接 ==="

# 测试 GitLab 连接
GITLAB_TOKEN=$(kubectl get secret ai-code-reviewer-secrets -n test -o jsonpath='{.data.gitlab-token}' | base64 -d)
if curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" https://gitlab.com/api/v4/user > /dev/null; then
    echo "✓ GitLab API 连接正常"
else
    echo "✗ GitLab API 连接失败"
fi

# 测试 Dify 连接
DIFY_TOKEN=$(kubectl get secret ai-code-reviewer-secrets -n test -o jsonpath='{.data.dify-token}' | base64 -d)
if curl -s -H "Authorization: Bearer $DIFY_TOKEN" https://api.dify.ai/v1/workflows > /dev/null; then
    echo "✓ Dify API 连接正常"
else
    echo "✗ Dify API 连接失败"
fi

echo "=== 验证 Kubernetes 资源 ==="

# 检查 ConfigMap
if kubectl get configmap ai-code-reviewer-config -n test > /dev/null 2>&1; then
    echo "✓ ConfigMap ai-code-reviewer-config 存在"
else
    echo "✗ ConfigMap ai-code-reviewer-config 不存在"
fi

# 检查 Secret
if kubectl get secret ai-code-reviewer-secrets -n test > /dev/null 2>&1; then
    echo "✓ Secret ai-code-reviewer-secrets 存在"
else
    echo "✗ Secret ai-code-reviewer-secrets 不存在"
fi

# 检查 Deployment
if kubectl get deployment ai-code-reviewer -n test > /dev/null 2>&1; then
    echo "✓ Deployment ai-code-reviewer 存在"
    
    # 检查 Pod 状态
    POD_STATUS=$(kubectl get pods -l app=ai-code-reviewer -n test -o jsonpath='{.items[0].status.phase}')
    if [ "$POD_STATUS" = "Running" ]; then
        echo "✓ Pod 状态正常"
    else
        echo "✗ Pod 状态异常: $POD_STATUS"
    fi
else
    echo "✗ Deployment ai-code-reviewer 不存在"
fi

echo "=== 验证完成 ==="
```

### 配置模板生成脚本

```bash
#!/bin/bash
# generate-config.sh

# 生成 Secret 模板
cat > secret-template.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: ai-code-reviewer-secrets
  namespace: test
type: Opaque
data:
  gitlab-token: $(echo -n "YOUR_GITLAB_TOKEN" | base64)
  dify-token: $(echo -n "YOUR_DIFY_TOKEN" | base64)
  tv-bot-id: $(echo -n "YOUR_TV_BOT_ID" | base64)
EOF

# 生成 ConfigMap 模板
cat > configmap-template.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ai-code-reviewer-env
  namespace: test
data:
  HTTP_PORT: "4195"
  LOG_LEVEL: "INFO"
  TIMEOUT: "1800"
  MAX_PAYLOAD_SIZE: "102400"
  GITLAB_URL: "https://gitlab.com"
  DIFY_API_URL: "https://api.dify.ai"
  TV_BOT_URL: "https://api.tvbot.com"
EOF

echo "配置模板已生成:"
echo "- secret-template.yaml"
echo "- configmap-template.yaml"
echo ""
echo "请编辑这些文件并填入实际的配置值，然后运行:"
echo "kubectl apply -f secret-template.yaml"
echo "kubectl apply -f configmap-template.yaml"
```

## 配置最佳实践

### 安全最佳实践

1. **敏感信息管理**
   - 所有敏感信息（令牌、密码）必须存储在 Kubernetes Secret 中
   - 使用 Base64 编码存储敏感数据
   - 定期轮换访问令牌和密钥
   - 限制 Secret 的访问权限

2. **权限最小化**
   - 为应用程序创建专用的 ServiceAccount
   - 使用 RBAC 限制最小必需权限
   - 启用 Pod 安全策略
   - 使用非 root 用户运行容器

3. **网络安全**
   - 使用网络策略限制 Pod 间通信
   - 启用 TLS 加密所有外部通信
   - 配置适当的防火墙规则
   - 使用 Ingress 控制外部访问

### 性能最佳实践

1. **资源配置**
   - 根据实际负载设置合适的资源请求和限制
   - 使用 HPA 实现自动扩缩容
   - 监控资源使用情况并及时调整
   - 配置适当的 QoS 类别

2. **连接管理**
   - 配置合适的连接池大小
   - 设置适当的超时时间
   - 使用连接复用减少开销
   - 实现重试和熔断机制

3. **缓存策略**
   - 缓存频繁访问的数据
   - 使用适当的缓存过期策略
   - 实现缓存预热机制
   - 监控缓存命中率

### 监控最佳实践

1. **指标收集**
   - 收集应用程序关键指标
   - 监控基础设施资源使用
   - 设置适当的告警阈值
   - 实现分布式链路跟踪

2. **日志管理**
   - 使用结构化日志格式
   - 实现日志级别动态调整
   - 配置日志轮转和清理
   - 集中化日志收集和分析

3. **健康检查**
   - 实现全面的健康检查端点
   - 配置适当的探针参数
   - 监控健康检查状态
   - 实现优雅的服务降级

## 故障排除

### 配置相关问题

1. **环境变量未生效**
   ```bash
   # 检查环境变量是否正确设置
   kubectl exec deployment/ai-code-reviewer -n test -- env | grep -E "(GITLAB|DIFY|TV_BOT)"
   
   # 重启 Pod 以重新加载环境变量
   kubectl rollout restart deployment/ai-code-reviewer -n test
   ```

2. **ConfigMap 更新未生效**
   ```bash
   # 检查 ConfigMap 内容
   kubectl get configmap ai-code-reviewer-config -n test -o yaml
   
   # 重启 Deployment 以重新挂载 ConfigMap
   kubectl rollout restart deployment/ai-code-reviewer -n test
   ```

3. **Secret 访问失败**
   ```bash
   # 检查 Secret 是否存在
   kubectl get secret ai-code-reviewer-secrets -n test
   
   # 检查 ServiceAccount 权限
   kubectl auth can-i get secrets --as=system:serviceaccount:test:ai-code-reviewer -n test
   ```

### 性能问题

1. **资源不足**
   ```bash
   # 检查资源使用情况
   kubectl top pod -l app=ai-code-reviewer -n test
   
   # 调整资源限制
   kubectl patch deployment ai-code-reviewer -n test -p '{"spec":{"template":{"spec":{"containers":[{"name":"ai-code-reviewer","resources":{"limits":{"memory":"1Gi","cpu":"1000m"}}}]}}}}'
   ```

2. **连接超时**
   ```bash
   # 检查网络连接
   kubectl exec deployment/ai-code-reviewer -n test -- curl -I https://api.dify.ai
   
   # 调整超时配置
   kubectl patch configmap ai-code-reviewer-env -n test -p '{"data":{"TIMEOUT":"3600"}}'
   ```

## 版本兼容性

### 支持的版本

- **Kubernetes**: 1.20+
- **Docker**: 20.10+
- **Benthos**: 4.0+
- **Jenkins**: 2.400+

### 升级注意事项

1. **配置格式变更**
   - 检查新版本的配置格式变化
   - 更新配置文件以匹配新格式
   - 测试配置兼容性

2. **API 变更**
   - 检查外部 API 的版本兼容性
   - 更新 API 调用代码
   - 测试 API 集成功能

3. **依赖更新**
   - 更新基础镜像和依赖包
   - 检查安全漏洞和修复
   - 测试功能完整性
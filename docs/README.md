# AI 代码审查应用文档

## 文档概述

本目录包含 AI 代码审查应用的完整文档，涵盖部署、运维和配置管理的各个方面。

## 文档结构

### 📋 [部署指南](deployment-guide.md)
完整的部署步骤和配置说明，包括：
- 前置条件和环境准备
- Kubernetes 资源部署
- Jenkins CI/CD 流水线配置
- 网络和安全配置
- 性能调优建议

### 🔧 [运维手册](operations-manual.md)
日常运维和故障排除指南，包括：
- 健康状态检查
- 日志管理和分析
- 故障排除流程
- 维护操作指南
- 监控和告警配置
- 备份和恢复流程

### ⚙️ [配置参考](configuration-reference.md)
详细的配置参数说明，包括：
- 环境变量完整列表
- Kubernetes 配置详解
- 配置验证和最佳实践
- 安全配置指南
- 性能优化参数

## 快速开始

### 1. 部署应用程序

```bash
# 克隆项目
git clone <repository-url>
cd <project-directory>

# 配置环境变量
cp k8s/secret.yaml.template k8s/secret.yaml
# 编辑 secret.yaml 填入实际的令牌和配置

# 执行部署
./k8s/deploy.sh test

# 验证部署
./k8s/validate-config.sh test
```

### 2. 验证应用程序

```bash
# 检查 Pod 状态
kubectl get pods -l app=ai-code-reviewer -n test

# 查看应用程序日志
kubectl logs -f deployment/ai-code-reviewer -n test

# 测试健康检查
kubectl port-forward svc/ai-code-reviewer 8080:80 -n test
curl http://localhost:8080/health
```

### 3. 配置 GitLab Webhook

1. 在 GitLab 项目中进入 Settings > Webhooks
2. 添加 Webhook URL: `https://ai-code-reviewer.test.example.com/webhook`
3. 选择触发事件: Merge request events
4. 测试 Webhook 连接

## 架构概览

```
GitLab Webhook → Ingress → Service → Pod (Benthos + 处理器) → Dify API
                                  ↓
                              ConfigMap/Secret
```

### 核心组件

- **Benthos 接收器**: 处理 GitLab Webhook 请求
- **请求处理器**: 调用 Dify AI 进行代码审查
- **Jenkins 流水线**: 自动化 CI/CD 流程
- **Kubernetes 资源**: 提供容器化运行环境

## 环境配置

### 测试环境
- **命名空间**: `test`
- **域名**: `ai-code-reviewer.test.example.com`
- **副本数**: 1
- **资源限制**: CPU 500m, Memory 512Mi

### 生产环境
- **命名空间**: `prod`
- **域名**: `ai-code-reviewer.prod.example.com`
- **副本数**: 3
- **资源限制**: CPU 1000m, Memory 1Gi

## 关键配置

### 必需的环境变量

| 变量名 | 描述 | 获取方式 |
|--------|------|----------|
| `GITLAB_TOKEN` | GitLab 私有访问令牌 | GitLab Settings > Access Tokens |
| `DIFY_TOKEN` | Dify API 访问令牌 | Dify 控制台 > API Keys |
| `TV_BOT_ID` | TV Bot 配置 ID | TV Bot 管理界面 |

### 重要的配置文件

- `k8s/configmap.yaml`: Benthos 和应用程序配置
- `k8s/secret.yaml`: 敏感信息配置
- `k8s/deployment.yaml`: 应用程序部署配置
- `Jenkinsfile`: CI/CD 流水线定义

## 监控和日志

### 健康检查端点

- `/health`: 应用程序健康状态
- `/ready`: 应用程序就绪状态
- `/startup`: 应用程序启动状态

### 日志查看

```bash
# 实时查看应用程序日志
kubectl logs -f deployment/ai-code-reviewer -n test

# 查看特定时间范围的日志
kubectl logs --since=1h deployment/ai-code-reviewer -n test

# 搜索错误日志
kubectl logs deployment/ai-code-reviewer -n test | grep -i error
```

### 资源监控

```bash
# 查看 Pod 资源使用
kubectl top pod -l app=ai-code-reviewer -n test

# 查看节点资源使用
kubectl top nodes
```

## 故障排除

### 常见问题

1. **Pod 无法启动**
   - 检查镜像是否存在
   - 验证 Secret 和 ConfigMap 配置
   - 查看 Pod 事件: `kubectl describe pod <pod-name> -n test`

2. **Webhook 请求失败**
   - 检查 Ingress 配置
   - 验证 TLS 证书
   - 测试网络连接

3. **外部 API 调用失败**
   - 验证 API 令牌
   - 检查网络策略
   - 测试 DNS 解析

### 调试命令

```bash
# 进入 Pod 进行调试
kubectl exec -it deployment/ai-code-reviewer -n test -- /bin/sh

# 查看 Pod 详细信息
kubectl describe pod <pod-name> -n test

# 查看服务端点
kubectl get endpoints ai-code-reviewer -n test

# 测试服务连接
kubectl run test-pod --image=busybox -it --rm --restart=Never -n test -- wget -qO- http://ai-code-reviewer/health
```

## 安全注意事项

### 敏感信息管理

- 所有敏感信息必须存储在 Kubernetes Secret 中
- 定期轮换 API 令牌和密钥
- 使用 RBAC 限制资源访问权限
- 启用网络策略限制 Pod 间通信

### 容器安全

- 使用非 root 用户运行容器
- 启用只读根文件系统
- 定期更新基础镜像
- 进行容器镜像安全扫描

## 性能优化

### 资源配置

根据实际负载调整资源配置：

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

### 自动扩缩容

```bash
# 配置 HPA
kubectl autoscale deployment ai-code-reviewer \
  --cpu-percent=70 \
  --min=1 \
  --max=5 \
  -n test
```

## 备份和恢复

### 配置备份

```bash
# 备份所有配置
kubectl get all,configmap,secret,ingress -n test -o yaml > backup-$(date +%Y%m%d).yaml

# 恢复配置
kubectl apply -f backup-20240101.yaml
```

### 数据备份

```bash
# 备份持久化数据
kubectl exec deployment/ai-code-reviewer -n test -- tar czf - /data | gzip > data-backup-$(date +%Y%m%d).tar.gz
```

## 更新和升级

### 应用程序更新

```bash
# 更新镜像
kubectl set image deployment/ai-code-reviewer \
  ai-code-reviewer=your-registry/ai-code-reviewer:v1.1.0 \
  -n test

# 监控更新进度
kubectl rollout status deployment/ai-code-reviewer -n test

# 回滚到上一版本
kubectl rollout undo deployment/ai-code-reviewer -n test
```

### 配置更新

```bash
# 更新 ConfigMap
kubectl apply -f k8s/configmap.yaml -n test

# 重启应用程序以加载新配置
kubectl rollout restart deployment/ai-code-reviewer -n test
```

## 支持和联系

### 技术支持

- **DevOps 团队**: devops@company.com
- **开发团队**: dev-team@company.com
- **系统管理员**: sysadmin@company.com

### 相关资源

- **监控面板**: https://monitoring.company.com/ai-code-reviewer
- **日志系统**: https://logs.company.com/ai-code-reviewer
- **问题跟踪**: https://issues.company.com/ai-code-reviewer
- **知识库**: https://wiki.company.com/ai-code-reviewer

## 版本历史

| 版本 | 日期 | 变更内容 |
|------|------|----------|
| 1.0.0 | 2024-01-01 | 初始版本发布 |
| 1.1.0 | 2024-02-01 | 添加健康检查和监控 |
| 1.2.0 | 2024-03-01 | 优化性能和安全配置 |

## 许可证

本项目采用 MIT 许可证，详见 [LICENSE](../LICENSE) 文件。
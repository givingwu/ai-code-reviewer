# AI 代码审查应用运维手册

## 概述

本运维手册提供了 AI 代码审查应用在 Kubernetes 环境中的故障排除、维护操作和监控指南。该手册面向 DevOps 工程师和系统管理员。

## 系统架构概览

```
GitLab Webhook → Ingress → Service → Pod (Benthos + 处理器) → Dify API
                                  ↓
                              ConfigMap/Secret
```

## 日常维护操作

### 健康状态检查

#### 应用程序健康检查

```bash
# 检查 Pod 状态
kubectl get pods -l app=ai-code-reviewer -n test

# 检查 Pod 详细信息
kubectl describe pod <pod-name> -n test

# 检查应用程序日志
kubectl logs -f deployment/ai-code-reviewer -n test

# 测试健康检查端点
kubectl port-forward svc/ai-code-reviewer 8080:80 -n test
curl http://localhost:8080/health
curl http://localhost:8080/ready
curl http://localhost:8080/startup
```

#### 服务状态检查

```bash
# 检查服务状态
kubectl get svc ai-code-reviewer -n test
kubectl describe svc ai-code-reviewer -n test

# 检查 Ingress 状态
kubectl get ingress ai-code-reviewer -n test
kubectl describe ingress ai-code-reviewer -n test

# 检查端点
kubectl get endpoints ai-code-reviewer -n test
```

#### 配置检查

```bash
# 检查 ConfigMap
kubectl get configmap ai-code-reviewer-config -n test -o yaml

# 检查 Secret（不显示敏感数据）
kubectl get secret ai-code-reviewer-secrets -n test

# 验证环境变量
kubectl exec deployment/ai-code-reviewer -n test -- env | grep -E "(GITLAB|DIFY|TV_BOT)"
```

### 日志管理

#### 日志查看

```bash
# 实时查看日志
kubectl logs -f deployment/ai-code-reviewer -n test

# 查看最近的日志
kubectl logs --tail=100 deployment/ai-code-reviewer -n test

# 查看特定时间范围的日志
kubectl logs --since=1h deployment/ai-code-reviewer -n test

# 查看所有容器的日志
kubectl logs deployment/ai-code-reviewer -n test --all-containers=true
```

#### 日志分析

```bash
# 搜索错误日志
kubectl logs deployment/ai-code-reviewer -n test | grep -i error

# 搜索特定关键词
kubectl logs deployment/ai-code-reviewer -n test | grep -i "webhook\|dify\|gitlab"

# 统计错误数量
kubectl logs deployment/ai-code-reviewer -n test | grep -c "ERROR"
```

### 性能监控

#### 资源使用监控

```bash
# 查看 Pod 资源使用情况
kubectl top pod -l app=ai-code-reviewer -n test

# 查看节点资源使用情况
kubectl top nodes

# 查看详细资源信息
kubectl describe pod <pod-name> -n test | grep -A 10 "Requests\|Limits"
```

#### 网络监控

```bash
# 检查网络连接
kubectl exec deployment/ai-code-reviewer -n test -- netstat -tlnp

# 测试外部连接
kubectl exec deployment/ai-code-reviewer -n test -- curl -I https://api.dify.ai
kubectl exec deployment/ai-code-reviewer -n test -- nslookup gitlab.com
```

## 故障排除指南

### Pod 相关问题

#### Pod 无法启动

**症状**: Pod 状态为 `Pending`、`CrashLoopBackOff` 或 `ImagePullBackOff`

**诊断步骤**:
```bash
# 查看 Pod 状态和事件
kubectl describe pod <pod-name> -n test

# 查看 Pod 日志
kubectl logs <pod-name> -n test --previous

# 检查镜像是否存在
kubectl get pod <pod-name> -n test -o jsonpath='{.spec.containers[0].image}'
```

**常见原因和解决方案**:

1. **镜像拉取失败**
   ```bash
   # 检查镜像仓库凭据
   kubectl get secret -n test | grep docker
   
   # 重新创建镜像拉取凭据
   kubectl create secret docker-registry acr-secret \
     --docker-server=your-registry.com \
     --docker-username=your-username \
     --docker-password=your-password \
     --namespace=test
   ```

2. **资源不足**
   ```bash
   # 检查节点资源
   kubectl describe nodes
   
   # 调整资源请求
   kubectl patch deployment ai-code-reviewer -n test -p '{"spec":{"template":{"spec":{"containers":[{"name":"ai-code-reviewer","resources":{"requests":{"cpu":"100m","memory":"128Mi"}}}]}}}}'
   ```

3. **配置错误**
   ```bash
   # 检查 ConfigMap 和 Secret
   kubectl get configmap,secret -n test
   
   # 验证挂载路径
   kubectl describe pod <pod-name> -n test | grep -A 10 "Mounts\|Volumes"
   ```

#### Pod 频繁重启

**症状**: Pod 重启次数不断增加

**诊断步骤**:
```bash
# 查看重启历史
kubectl get pod <pod-name> -n test -o wide

# 查看重启前的日志
kubectl logs <pod-name> -n test --previous

# 检查健康检查配置
kubectl describe pod <pod-name> -n test | grep -A 5 "Liveness\|Readiness"
```

**解决方案**:

1. **调整健康检查参数**
   ```bash
   # 增加初始延迟和超时时间
   kubectl patch deployment ai-code-reviewer -n test -p '{"spec":{"template":{"spec":{"containers":[{"name":"ai-code-reviewer","livenessProbe":{"initialDelaySeconds":60,"timeoutSeconds":10}}]}}}}'
   ```

2. **检查内存泄漏**
   ```bash
   # 监控内存使用
   kubectl top pod <pod-name> -n test --containers
   
   # 增加内存限制
   kubectl patch deployment ai-code-reviewer -n test -p '{"spec":{"template":{"spec":{"containers":[{"name":"ai-code-reviewer","resources":{"limits":{"memory":"1Gi"}}}]}}}}'
   ```

### 网络相关问题

#### 服务无法访问

**症状**: 外部无法访问应用程序

**诊断步骤**:
```bash
# 检查服务端点
kubectl get endpoints ai-code-reviewer -n test

# 测试服务内部访问
kubectl run test-pod --image=busybox -it --rm --restart=Never -n test -- wget -qO- http://ai-code-reviewer/health

# 检查 Ingress 状态
kubectl describe ingress ai-code-reviewer -n test
```

**解决方案**:

1. **服务选择器问题**
   ```bash
   # 检查标签匹配
   kubectl get pod -l app=ai-code-reviewer -n test --show-labels
   kubectl get svc ai-code-reviewer -n test -o yaml | grep selector
   ```

2. **端口配置问题**
   ```bash
   # 验证端口配置
   kubectl get svc ai-code-reviewer -n test -o yaml | grep -A 5 ports
   kubectl describe pod <pod-name> -n test | grep Port
   ```

3. **Ingress 配置问题**
   ```bash
   # 检查 Ingress 控制器
   kubectl get pods -n ingress-nginx
   
   # 检查 TLS 证书
   kubectl get secret tls-secret -n test -o yaml
   ```

#### DNS 解析问题

**症状**: 应用程序无法解析外部域名

**诊断步骤**:
```bash
# 测试 DNS 解析
kubectl exec deployment/ai-code-reviewer -n test -- nslookup api.dify.ai
kubectl exec deployment/ai-code-reviewer -n test -- nslookup gitlab.com

# 检查 DNS 配置
kubectl exec deployment/ai-code-reviewer -n test -- cat /etc/resolv.conf
```

**解决方案**:
```bash
# 重启 CoreDNS
kubectl rollout restart deployment/coredns -n kube-system

# 检查 DNS 服务
kubectl get svc -n kube-system | grep dns
```

### 应用程序相关问题

#### Webhook 请求失败

**症状**: GitLab Webhook 请求返回错误

**诊断步骤**:
```bash
# 查看应用程序日志中的 Webhook 请求
kubectl logs deployment/ai-code-reviewer -n test | grep -i webhook

# 测试 Webhook 端点
curl -X POST https://ai-code-reviewer.test.example.com/webhook \
  -H "Content-Type: application/json" \
  -d '{"test": "data"}'
```

**解决方案**:

1. **检查 Benthos 配置**
   ```bash
   # 查看 Benthos 配置
   kubectl get configmap ai-code-reviewer-config -n test -o yaml
   
   # 验证端口和路径配置
   kubectl exec deployment/ai-code-reviewer -n test -- cat /config/receiver.yaml
   ```

2. **检查负载大小限制**
   ```bash
   # 调整最大负载大小
   kubectl patch configmap ai-code-reviewer-config -n test -p '{"data":{"app-config.yaml":"max_payload_size: 204800\ntimeout: 1800\nlog_level: INFO"}}'
   ```

#### Dify API 调用失败

**症状**: 无法连接到 Dify API 服务

**诊断步骤**:
```bash
# 测试 Dify API 连接
kubectl exec deployment/ai-code-reviewer -n test -- curl -I https://api.dify.ai

# 检查 API Token
kubectl get secret ai-code-reviewer-secrets -n test -o jsonpath='{.data.dify-token}' | base64 -d
```

**解决方案**:

1. **更新 API Token**
   ```bash
   # 更新 Secret
   kubectl patch secret ai-code-reviewer-secrets -n test -p '{"data":{"dify-token":"'$(echo -n "new-token" | base64)'"}}'
   
   # 重启应用程序
   kubectl rollout restart deployment/ai-code-reviewer -n test
   ```

2. **检查网络策略**
   ```bash
   # 查看网络策略
   kubectl get networkpolicy -n test
   
   # 临时禁用网络策略进行测试
   kubectl delete networkpolicy --all -n test
   ```

## 维护操作

### 配置更新

#### 更新 ConfigMap

```bash
# 备份当前配置
kubectl get configmap ai-code-reviewer-config -n test -o yaml > configmap-backup.yaml

# 更新配置
kubectl apply -f k8s/configmap.yaml

# 重启应用程序以加载新配置
kubectl rollout restart deployment/ai-code-reviewer -n test

# 验证更新
kubectl rollout status deployment/ai-code-reviewer -n test
```

#### 更新 Secret

```bash
# 备份当前 Secret
kubectl get secret ai-code-reviewer-secrets -n test -o yaml > secret-backup.yaml

# 更新 Secret
kubectl create secret generic ai-code-reviewer-secrets \
  --from-literal=gitlab-token="new-gitlab-token" \
  --from-literal=dify-token="new-dify-token" \
  --from-literal=tv-bot-id="new-tv-bot-id" \
  --namespace=test \
  --dry-run=client -o yaml | kubectl apply -f -

# 重启应用程序
kubectl rollout restart deployment/ai-code-reviewer -n test
```

### 应用程序更新

#### 滚动更新

```bash
# 更新镜像
kubectl set image deployment/ai-code-reviewer \
  ai-code-reviewer=your-registry/ai-code-reviewer:v1.1.0 \
  -n test

# 监控更新进度
kubectl rollout status deployment/ai-code-reviewer -n test

# 验证新版本
kubectl get pods -l app=ai-code-reviewer -n test
kubectl logs deployment/ai-code-reviewer -n test | head -20
```

#### 回滚操作

```bash
# 查看部署历史
kubectl rollout history deployment/ai-code-reviewer -n test

# 回滚到上一个版本
kubectl rollout undo deployment/ai-code-reviewer -n test

# 回滚到特定版本
kubectl rollout undo deployment/ai-code-reviewer -n test --to-revision=2

# 验证回滚
kubectl rollout status deployment/ai-code-reviewer -n test
```

### 扩缩容操作

#### 手动扩缩容

```bash
# 扩容到 3 个副本
kubectl scale deployment ai-code-reviewer --replicas=3 -n test

# 缩容到 1 个副本
kubectl scale deployment ai-code-reviewer --replicas=1 -n test

# 验证扩缩容结果
kubectl get pods -l app=ai-code-reviewer -n test
```

#### 自动扩缩容（HPA）

```bash
# 创建 HPA
kubectl autoscale deployment ai-code-reviewer \
  --cpu-percent=70 \
  --min=1 \
  --max=5 \
  -n test

# 查看 HPA 状态
kubectl get hpa -n test
kubectl describe hpa ai-code-reviewer -n test
```

## 监控和告警

### 关键指标监控

#### 应用程序指标

- **请求处理速率**: 每分钟处理的 Webhook 请求数
- **错误率**: 失败请求占总请求的百分比
- **响应时间**: 平均请求处理时间
- **队列长度**: 待处理请求队列长度

#### 基础设施指标

- **CPU 使用率**: Pod CPU 使用百分比
- **内存使用率**: Pod 内存使用百分比
- **网络流量**: 入站和出站网络流量
- **存储使用率**: 持久化存储使用情况

### 告警规则

#### 关键告警

1. **Pod 重启频繁**
   ```bash
   # 检查重启次数
   kubectl get pods -l app=ai-code-reviewer -n test -o custom-columns=NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount
   ```

2. **内存使用率过高**
   ```bash
   # 监控内存使用
   kubectl top pod -l app=ai-code-reviewer -n test
   ```

3. **错误率超过阈值**
   ```bash
   # 统计错误日志
   kubectl logs deployment/ai-code-reviewer -n test --since=1h | grep -c "ERROR"
   ```

4. **外部服务不可用**
   ```bash
   # 测试外部服务连接
   kubectl exec deployment/ai-code-reviewer -n test -- curl -f https://api.dify.ai/health
   ```

### 日志聚合和分析

#### 日志收集配置

```yaml
# 使用 Fluent Bit 收集日志
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluent-bit-config
data:
  fluent-bit.conf: |
    [INPUT]
        Name tail
        Path /var/log/containers/ai-code-reviewer*.log
        Parser docker
        Tag kube.*
    
    [OUTPUT]
        Name es
        Match kube.*
        Host elasticsearch.logging.svc.cluster.local
        Port 9200
        Index ai-code-reviewer
```

#### 日志查询示例

```bash
# 查询特定时间范围的错误日志
curl -X GET "elasticsearch:9200/ai-code-reviewer/_search" -H 'Content-Type: application/json' -d'
{
  "query": {
    "bool": {
      "must": [
        {"match": {"log": "ERROR"}},
        {"range": {"@timestamp": {"gte": "now-1h"}}}
      ]
    }
  }
}'
```

## 备份和恢复

### 配置备份

#### 自动备份脚本

```bash
#!/bin/bash
# backup-config.sh

NAMESPACE="test"
BACKUP_DIR="/backup/$(date +%Y%m%d)"
mkdir -p $BACKUP_DIR

# 备份所有配置
kubectl get all,configmap,secret,ingress -n $NAMESPACE -o yaml > $BACKUP_DIR/all-resources.yaml

# 备份特定资源
kubectl get configmap ai-code-reviewer-config -n $NAMESPACE -o yaml > $BACKUP_DIR/configmap.yaml
kubectl get secret ai-code-reviewer-secrets -n $NAMESPACE -o yaml > $BACKUP_DIR/secret.yaml
kubectl get deployment ai-code-reviewer -n $NAMESPACE -o yaml > $BACKUP_DIR/deployment.yaml

echo "Backup completed: $BACKUP_DIR"
```

#### 定期备份 Cron Job

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: config-backup
  namespace: test
spec:
  schedule: "0 2 * * *"  # 每天凌晨 2 点
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: bitnami/kubectl:latest
            command:
            - /bin/bash
            - -c
            - |
              kubectl get all,configmap,secret,ingress -n test -o yaml > /backup/backup-$(date +%Y%m%d).yaml
            volumeMounts:
            - name: backup-storage
              mountPath: /backup
          volumes:
          - name: backup-storage
            persistentVolumeClaim:
              claimName: backup-pvc
          restartPolicy: OnFailure
```

### 灾难恢复

#### 完整恢复流程

```bash
# 1. 恢复命名空间
kubectl create namespace test

# 2. 恢复 Secret 和 ConfigMap
kubectl apply -f backup/secret.yaml
kubectl apply -f backup/configmap.yaml

# 3. 恢复应用程序
kubectl apply -f backup/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml

# 4. 验证恢复
kubectl get pods -l app=ai-code-reviewer -n test
kubectl logs deployment/ai-code-reviewer -n test
```

## 安全维护

### 定期安全检查

#### 镜像安全扫描

```bash
# 使用 Trivy 扫描镜像漏洞
trivy image your-registry/ai-code-reviewer:latest

# 扫描 Kubernetes 配置
trivy k8s --report summary cluster
```

#### 权限审计

```bash
# 检查 ServiceAccount 权限
kubectl auth can-i --list --as=system:serviceaccount:test:ai-code-reviewer -n test

# 检查 RBAC 配置
kubectl get rolebinding,clusterrolebinding -n test
```

### 证书管理

#### TLS 证书更新

```bash
# 检查证书有效期
kubectl get secret tls-secret -n test -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates

# 更新证书
kubectl create secret tls tls-secret \
  --cert=path/to/tls.crt \
  --key=path/to/tls.key \
  --namespace=test \
  --dry-run=client -o yaml | kubectl apply -f -
```

## 性能优化

### 资源优化

#### 基于使用情况调整资源

```bash
# 监控资源使用趋势
kubectl top pod -l app=ai-code-reviewer -n test --containers

# 根据监控数据调整资源配置
kubectl patch deployment ai-code-reviewer -n test -p '{"spec":{"template":{"spec":{"containers":[{"name":"ai-code-reviewer","resources":{"requests":{"cpu":"300m","memory":"384Mi"},"limits":{"cpu":"600m","memory":"768Mi"}}}]}}}}'
```

#### JVM 调优（如果适用）

```yaml
# 在 Deployment 中添加 JVM 参数
env:
- name: JAVA_OPTS
  value: "-Xms256m -Xmx512m -XX:+UseG1GC -XX:MaxGCPauseMillis=200"
```

### 网络优化

#### 连接池配置

```yaml
# 在 ConfigMap 中配置连接池
data:
  app-config.yaml: |
    http_client:
      timeout: 30s
      max_idle_conns: 100
      max_idle_conns_per_host: 10
      idle_conn_timeout: 90s
```

## 故障排除检查清单

### 快速诊断检查清单

- [ ] Pod 状态正常 (`kubectl get pods`)
- [ ] 服务端点可达 (`kubectl get endpoints`)
- [ ] Ingress 配置正确 (`kubectl describe ingress`)
- [ ] 健康检查通过 (`curl /health`)
- [ ] 日志无错误 (`kubectl logs`)
- [ ] 资源使用正常 (`kubectl top pod`)
- [ ] 外部服务可达 (`curl external-api`)
- [ ] 配置正确加载 (`kubectl describe pod`)

### 紧急响应流程

1. **确认问题范围**
   - 影响的用户数量
   - 服务可用性状态
   - 错误率和响应时间

2. **快速缓解措施**
   - 重启 Pod (`kubectl rollout restart`)
   - 回滚到稳定版本 (`kubectl rollout undo`)
   - 扩容增加容量 (`kubectl scale`)

3. **根因分析**
   - 收集日志和指标
   - 分析错误模式
   - 确定修复方案

4. **修复和验证**
   - 实施修复措施
   - 验证问题解决
   - 更新监控和告警

5. **事后总结**
   - 记录问题和解决方案
   - 更新运维文档
   - 改进监控和预防措施

## 联系信息

### 紧急联系人

- **DevOps 团队**: devops@company.com
- **开发团队**: dev-team@company.com
- **系统管理员**: sysadmin@company.com

### 相关资源

- **监控面板**: https://monitoring.company.com/ai-code-reviewer
- **日志系统**: https://logs.company.com/ai-code-reviewer
- **文档库**: https://docs.company.com/ai-code-reviewer
- **问题跟踪**: https://issues.company.com/ai-code-reviewer
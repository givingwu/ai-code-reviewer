# Jenkins CI/CD 流水线配置指南

## 概述

本目录包含了 AI 代码审查应用的 Jenkins CI/CD 流水线配置文件和脚本。流水线实现了从代码提交到 Kubernetes 部署的完整自动化流程。

## 文件结构

```
jenkins/
├── README.md                 # 本文档
├── jenkins-config.yaml       # Jenkins 配置参数
└── scripts/
    ├── deploy.sh             # 部署脚本
    ├── test.sh               # 集成测试脚本
    └── rollback.sh           # 回滚脚本
```

## 流水线阶段

### 1. 代码检出 (Code Checkout)
- 从 GitLab 仓库检出最新代码
- 清理工作空间
- 显示提交信息

### 2. 构建镜像 (Build Image)
- 使用 Docker 构建应用镜像
- 标记镜像版本（BUILD_NUMBER-GIT_COMMIT）
- 创建 latest 标签

### 3. 推送镜像 (Push Image)
- 登录阿里云容器镜像服务 (ACR)
- 推送带版本标签的镜像
- 推送 latest 标签镜像

### 4. 部署到测试环境 (Deploy to Test)
- 应用 Kubernetes 资源清单
- 更新部署镜像
- 等待部署完成
- 验证 Pod 状态

### 5. 集成测试 (Integration Test)
- 健康检查端点测试
- 应用程序日志检查
- 服务连通性验证
- 基础性能测试

### 6. 部署验证 (Deployment Verification)
- 验证部署状态
- 检查服务端点
- 确认应用程序正常运行

## 环境变量配置

### 必需的环境变量

| 变量名 | 描述 | 示例值 |
|--------|------|--------|
| `ACR_REGISTRY_URL` | 阿里云容器镜像服务地址 | `registry.cn-hangzhou.aliyuncs.com` |
| `ACR_NAMESPACE` | ACR 命名空间 | `your-namespace` |
| `K8S_NAMESPACE` | Kubernetes 命名空间 | `test` |
| `K8S_DEPLOYMENT` | 部署名称 | `ai-code-reviewer` |

### Jenkins 凭据配置

需要在 Jenkins 中配置以下凭据：

1. **aliyun-acr-credentials** (Username/Password)
   - 用于登录阿里云容器镜像服务
   - Username: ACR 用户名
   - Password: ACR 密码

2. **k8s-kubeconfig** (Secret File)
   - Kubernetes 集群的 kubeconfig 文件
   - 用于 kubectl 命令认证

## 部署脚本说明

### deploy.sh
自动化部署脚本，包含以下功能：
- 环境变量检查
- Kubernetes 连接验证
- 命名空间管理
- 资源应用和部署更新
- 部署状态监控

### test.sh
集成测试脚本，包含以下测试：
- 服务就绪检查
- Pod 健康状态验证
- 应用程序日志分析
- 健康检查端点测试
- Webhook 端点测试
- 服务连通性检查
- 基础性能测试

### rollback.sh
回滚脚本，用于部署失败时的恢复：
- 部署历史检查
- 自动回滚到上一版本
- 回滚状态验证
- 回滚信息收集

## 使用方法

### 1. 配置 Jenkins

1. 在 Jenkins 中创建新的流水线项目
2. 配置 Git 仓库地址
3. 设置 Jenkinsfile 路径为项目根目录的 `Jenkinsfile`
4. 配置必需的凭据和环境变量

### 2. 配置触发器

建议配置以下触发器：
- **Git Hook 触发**: 代码推送到主分支时自动触发
- **定时构建**: 每日定时构建（可选）
- **手动触发**: 支持手动执行构建

### 3. 配置通知

可以配置以下通知方式：
- **钉钉通知**: 构建结果通知到钉钉群
- **邮件通知**: 发送构建报告邮件
- **Slack 通知**: 发送到 Slack 频道（可选）

## 故障排除

### 常见问题

1. **镜像构建失败**
   - 检查 Dockerfile 语法
   - 验证基础镜像可用性
   - 检查网络连接

2. **镜像推送失败**
   - 验证 ACR 凭据配置
   - 检查网络连接到 ACR
   - 确认命名空间权限

3. **部署失败**
   - 检查 kubeconfig 配置
   - 验证 Kubernetes 集群连接
   - 检查资源清单语法

4. **测试失败**
   - 检查应用程序日志
   - 验证健康检查端点
   - 确认服务配置正确

### 调试方法

1. **查看构建日志**
   ```bash
   # 在 Jenkins 控制台查看详细日志
   ```

2. **检查 Kubernetes 状态**
   ```bash
   kubectl get pods -n test
   kubectl describe pod <pod-name> -n test
   kubectl logs <pod-name> -n test
   ```

3. **手动执行脚本**
   ```bash
   # 在 Jenkins 节点上手动执行脚本进行调试
   ./jenkins/scripts/deploy.sh
   ./jenkins/scripts/test.sh
   ```

## 最佳实践

### 1. 版本管理
- 使用语义化版本标签
- 保留最近的镜像版本
- 定期清理旧版本镜像

### 2. 安全配置
- 使用最小权限原则配置 RBAC
- 定期轮换访问凭据
- 启用镜像漏洞扫描

### 3. 监控和告警
- 配置构建失败告警
- 监控部署成功率
- 设置性能基准告警

### 4. 备份和恢复
- 定期备份 Jenkins 配置
- 保留部署历史记录
- 测试回滚流程

## 扩展配置

### 多环境支持
如果需要支持多个环境，可以：
1. 创建不同的 Jenkins 流水线
2. 使用参数化构建
3. 配置环境特定的变量

### 高级测试
可以添加更多测试类型：
- 安全扫描测试
- 性能压力测试
- 端到端自动化测试
- 合规性检查

### 集成其他工具
可以集成以下工具：
- SonarQube 代码质量检查
- Trivy 镜像安全扫描
- Prometheus 监控集成
- Grafana 可视化面板
#!/bin/bash

# AI 代码审查应用自动化部署脚本
# 使用方法: ./deploy.sh [环境名称]

set -e

# 默认配置
NAMESPACE=${1:-test}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查必需的工具
check_prerequisites() {
    log_info "检查前置条件..."
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl 未安装或不在 PATH 中"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        log_error "无法连接到 Kubernetes 集群"
        exit 1
    fi
    
    log_info "前置条件检查通过"
}

# 创建命名空间
create_namespace() {
    log_info "创建命名空间: $NAMESPACE"
    
    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_warn "命名空间 $NAMESPACE 已存在"
    else
        kubectl create namespace "$NAMESPACE"
        log_info "命名空间 $NAMESPACE 创建成功"
    fi
}

# 验证配置文件
validate_configs() {
    log_info "验证配置文件..."
    
    local required_files=(
        "$SCRIPT_DIR/namespace.yaml"
        "$SCRIPT_DIR/configmap.yaml"
        "$SCRIPT_DIR/configmap-env.yaml"
        "$SCRIPT_DIR/secret.yaml"
        "$SCRIPT_DIR/deployment.yaml"
        "$SCRIPT_DIR/service.yaml"
        "$SCRIPT_DIR/ingress.yaml"
        "$SCRIPT_DIR/pvc.yaml"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "配置文件不存在: $file"
            exit 1
        fi
    done
    
    log_info "配置文件验证通过"
}

# 部署配置资源
deploy_configs() {
    log_info "部署配置资源..."
    
    # 应用命名空间
    kubectl apply -f "$SCRIPT_DIR/namespace.yaml"
    
    # 应用 ConfigMap
    kubectl apply -f "$SCRIPT_DIR/configmap.yaml" -n "$NAMESPACE"
    kubectl apply -f "$SCRIPT_DIR/configmap-env.yaml" -n "$NAMESPACE"
    
    # 检查 Secret 是否存在
    if kubectl get secret ai-code-reviewer-secrets -n "$NAMESPACE" &> /dev/null; then
        log_warn "Secret ai-code-reviewer-secrets 已存在，跳过创建"
    else
        log_warn "Secret 不存在，请手动创建或运行 create-secrets.sh"
        if [[ -f "$SCRIPT_DIR/create-secrets.sh" ]]; then
            log_info "运行 create-secrets.sh 创建 Secret..."
            bash "$SCRIPT_DIR/create-secrets.sh" "$NAMESPACE"
        fi
    fi
    
    # 应用 PVC
    kubectl apply -f "$SCRIPT_DIR/pvc.yaml" -n "$NAMESPACE"
    
    log_info "配置资源部署完成"
}

# 部署应用程序
deploy_application() {
    log_info "部署应用程序..."
    
    # 部署应用程序
    kubectl apply -f "$SCRIPT_DIR/deployment.yaml" -n "$NAMESPACE"
    
    # 创建服务
    kubectl apply -f "$SCRIPT_DIR/service.yaml" -n "$NAMESPACE"
    
    # 创建 Ingress
    kubectl apply -f "$SCRIPT_DIR/ingress.yaml" -n "$NAMESPACE"
    
    log_info "应用程序部署完成"
}

# 等待部署完成
wait_for_deployment() {
    log_info "等待部署完成..."
    
    # 等待 Deployment 就绪
    if kubectl rollout status deployment/ai-code-reviewer -n "$NAMESPACE" --timeout=300s; then
        log_info "Deployment 部署成功"
    else
        log_error "Deployment 部署超时"
        return 1
    fi
    
    # 等待 Pod 就绪
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        local ready_pods=$(kubectl get pods -l app=ai-code-reviewer -n "$NAMESPACE" -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | grep -c "True" || echo "0")
        local total_pods=$(kubectl get pods -l app=ai-code-reviewer -n "$NAMESPACE" --no-headers | wc -l)
        
        if [[ $ready_pods -eq $total_pods ]] && [[ $total_pods -gt 0 ]]; then
            log_info "所有 Pod 已就绪"
            break
        fi
        
        log_info "等待 Pod 就绪... ($ready_pods/$total_pods)"
        sleep 10
        ((attempt++))
    done
    
    if [[ $attempt -eq $max_attempts ]]; then
        log_error "Pod 就绪超时"
        return 1
    fi
}

# 验证部署
verify_deployment() {
    log_info "验证部署..."
    
    # 检查 Pod 状态
    log_info "Pod 状态:"
    kubectl get pods -l app=ai-code-reviewer -n "$NAMESPACE" -o wide
    
    # 检查服务状态
    log_info "服务状态:"
    kubectl get svc ai-code-reviewer -n "$NAMESPACE"
    
    # 检查 Ingress 状态
    log_info "Ingress 状态:"
    kubectl get ingress ai-code-reviewer -n "$NAMESPACE"
    
    # 测试健康检查
    log_info "测试健康检查..."
    local pod_name=$(kubectl get pods -l app=ai-code-reviewer -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}')
    
    if kubectl exec "$pod_name" -n "$NAMESPACE" -- curl -f http://localhost:4195/health &> /dev/null; then
        log_info "健康检查通过"
    else
        log_warn "健康检查失败，请检查应用程序日志"
    fi
    
    # 显示访问信息
    local ingress_host=$(kubectl get ingress ai-code-reviewer -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].host}')
    if [[ -n "$ingress_host" ]]; then
        log_info "应用程序访问地址: https://$ingress_host"
    fi
}

# 显示部署信息
show_deployment_info() {
    log_info "部署信息:"
    echo "命名空间: $NAMESPACE"
    echo "应用程序: ai-code-reviewer"
    echo ""
    
    log_info "有用的命令:"
    echo "查看 Pod 状态: kubectl get pods -l app=ai-code-reviewer -n $NAMESPACE"
    echo "查看应用日志: kubectl logs -f deployment/ai-code-reviewer -n $NAMESPACE"
    echo "进入 Pod 调试: kubectl exec -it deployment/ai-code-reviewer -n $NAMESPACE -- /bin/sh"
    echo "端口转发测试: kubectl port-forward svc/ai-code-reviewer 8080:80 -n $NAMESPACE"
    echo ""
    
    log_info "配置管理:"
    echo "更新配置: kubectl apply -f k8s/configmap.yaml -n $NAMESPACE"
    echo "重启应用: kubectl rollout restart deployment/ai-code-reviewer -n $NAMESPACE"
    echo "查看配置: kubectl get configmap,secret -n $NAMESPACE"
}

# 清理函数
cleanup_on_error() {
    log_error "部署过程中发生错误，正在清理..."
    
    # 可选：删除已创建的资源
    # kubectl delete namespace "$NAMESPACE" --ignore-not-found=true
    
    exit 1
}

# 主函数
main() {
    log_info "开始部署 AI 代码审查应用到环境: $NAMESPACE"
    
    # 设置错误处理
    trap cleanup_on_error ERR
    
    # 执行部署步骤
    check_prerequisites
    create_namespace
    validate_configs
    deploy_configs
    deploy_application
    wait_for_deployment
    verify_deployment
    show_deployment_info
    
    log_info "部署完成！"
}

# 帮助信息
show_help() {
    echo "AI 代码审查应用部署脚本"
    echo ""
    echo "使用方法:"
    echo "  $0 [环境名称]"
    echo ""
    echo "参数:"
    echo "  环境名称    目标 Kubernetes 命名空间 (默认: test)"
    echo ""
    echo "示例:"
    echo "  $0          # 部署到 test 环境"
    echo "  $0 prod     # 部署到 prod 环境"
    echo "  $0 staging  # 部署到 staging 环境"
    echo ""
    echo "选项:"
    echo "  -h, --help  显示此帮助信息"
}

# 解析命令行参数
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
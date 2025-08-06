#!/bin/bash

# AI 代码审查应用配置验证脚本
# 使用方法: ./validate-config.sh [环境名称]

set -e

# 默认配置
NAMESPACE=${1:-test}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# 成功/失败计数器
SUCCESS_COUNT=0
FAILURE_COUNT=0
WARNING_COUNT=0

# 记录结果
record_success() {
    ((SUCCESS_COUNT++))
    log_info "✓ $1"
}

record_failure() {
    ((FAILURE_COUNT++))
    log_error "✗ $1"
}

record_warning() {
    ((WARNING_COUNT++))
    log_warn "! $1"
}

# 检查 kubectl 连接
check_kubectl() {
    log_info "=== 检查 Kubernetes 连接 ==="
    
    if command -v kubectl &> /dev/null; then
        record_success "kubectl 命令可用"
    else
        record_failure "kubectl 命令不可用"
        return 1
    fi
    
    if kubectl cluster-info &> /dev/null; then
        record_success "Kubernetes 集群连接正常"
    else
        record_failure "无法连接到 Kubernetes 集群"
        return 1
    fi
    
    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        record_success "命名空间 $NAMESPACE 存在"
    else
        record_failure "命名空间 $NAMESPACE 不存在"
    fi
}

# 检查配置文件
check_config_files() {
    log_info "=== 检查配置文件 ==="
    
    local config_files=(
        "namespace.yaml:命名空间配置"
        "configmap.yaml:主配置文件"
        "configmap-env.yaml:环境变量配置"
        "secret.yaml:密钥配置模板"
        "deployment.yaml:部署配置"
        "service.yaml:服务配置"
        "ingress.yaml:Ingress 配置"
        "pvc.yaml:存储配置"
    )
    
    for config in "${config_files[@]}"; do
        local file="${config%%:*}"
        local desc="${config##*:}"
        
        if [[ -f "$SCRIPT_DIR/$file" ]]; then
            record_success "$desc ($file) 存在"
            
            # 验证 YAML 语法
            if kubectl apply --dry-run=client -f "$SCRIPT_DIR/$file" &> /dev/null; then
                record_success "$desc YAML 语法正确"
            else
                record_failure "$desc YAML 语法错误"
            fi
        else
            record_failure "$desc ($file) 不存在"
        fi
    done
}

# 检查 Kubernetes 资源
check_k8s_resources() {
    log_info "=== 检查 Kubernetes 资源 ==="
    
    # 检查 ConfigMap
    if kubectl get configmap ai-code-reviewer-config -n "$NAMESPACE" &> /dev/null; then
        record_success "ConfigMap ai-code-reviewer-config 存在"
        
        # 检查 ConfigMap 内容
        local config_keys=("receiver.yaml" "app-config.yaml")
        for key in "${config_keys[@]}"; do
            if kubectl get configmap ai-code-reviewer-config -n "$NAMESPACE" -o jsonpath="{.data.$key}" &> /dev/null; then
                record_success "ConfigMap 包含 $key"
            else
                record_failure "ConfigMap 缺少 $key"
            fi
        done
    else
        record_failure "ConfigMap ai-code-reviewer-config 不存在"
    fi
    
    # 检查环境变量 ConfigMap
    if kubectl get configmap ai-code-reviewer-env -n "$NAMESPACE" &> /dev/null; then
        record_success "ConfigMap ai-code-reviewer-env 存在"
    else
        record_failure "ConfigMap ai-code-reviewer-env 不存在"
    fi
    
    # 检查 Secret
    if kubectl get secret ai-code-reviewer-secrets -n "$NAMESPACE" &> /dev/null; then
        record_success "Secret ai-code-reviewer-secrets 存在"
        
        # 检查 Secret 内容
        local secret_keys=("gitlab-token" "dify-token" "tv-bot-id")
        for key in "${secret_keys[@]}"; do
            if kubectl get secret ai-code-reviewer-secrets -n "$NAMESPACE" -o jsonpath="{.data.$key}" &> /dev/null; then
                local value=$(kubectl get secret ai-code-reviewer-secrets -n "$NAMESPACE" -o jsonpath="{.data.$key}" | base64 -d)
                if [[ -n "$value" && "$value" != "YOUR_"* ]]; then
                    record_success "Secret 包含有效的 $key"
                else
                    record_warning "Secret $key 可能未正确配置"
                fi
            else
                record_failure "Secret 缺少 $key"
            fi
        done
    else
        record_failure "Secret ai-code-reviewer-secrets 不存在"
    fi
    
    # 检查 PVC
    if kubectl get pvc ai-code-reviewer-storage -n "$NAMESPACE" &> /dev/null; then
        record_success "PVC ai-code-reviewer-storage 存在"
        
        local pvc_status=$(kubectl get pvc ai-code-reviewer-storage -n "$NAMESPACE" -o jsonpath='{.status.phase}')
        if [[ "$pvc_status" == "Bound" ]]; then
            record_success "PVC 状态正常 (Bound)"
        else
            record_warning "PVC 状态异常: $pvc_status"
        fi
    else
        record_failure "PVC ai-code-reviewer-storage 不存在"
    fi
}

# 检查应用程序部署
check_application() {
    log_info "=== 检查应用程序部署 ==="
    
    # 检查 Deployment
    if kubectl get deployment ai-code-reviewer -n "$NAMESPACE" &> /dev/null; then
        record_success "Deployment ai-code-reviewer 存在"
        
        # 检查 Deployment 状态
        local ready_replicas=$(kubectl get deployment ai-code-reviewer -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
        local desired_replicas=$(kubectl get deployment ai-code-reviewer -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
        
        if [[ "$ready_replicas" == "$desired_replicas" ]]; then
            record_success "Deployment 副本数正常 ($ready_replicas/$desired_replicas)"
        else
            record_failure "Deployment 副本数异常 ($ready_replicas/$desired_replicas)"
        fi
    else
        record_failure "Deployment ai-code-reviewer 不存在"
    fi
    
    # 检查 Pod
    local pods=$(kubectl get pods -l app=ai-code-reviewer -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    if [[ $pods -gt 0 ]]; then
        record_success "找到 $pods 个 Pod"
        
        # 检查 Pod 状态
        local running_pods=$(kubectl get pods -l app=ai-code-reviewer -n "$NAMESPACE" -o jsonpath='{.items[*].status.phase}' | grep -c "Running" || echo "0")
        if [[ $running_pods -eq $pods ]]; then
            record_success "所有 Pod 状态正常 (Running)"
        else
            record_failure "部分 Pod 状态异常 ($running_pods/$pods Running)"
        fi
        
        # 检查 Pod 重启次数
        local restart_counts=$(kubectl get pods -l app=ai-code-reviewer -n "$NAMESPACE" -o jsonpath='{.items[*].status.containerStatuses[0].restartCount}')
        local total_restarts=0
        for count in $restart_counts; do
            ((total_restarts += count))
        done
        
        if [[ $total_restarts -eq 0 ]]; then
            record_success "Pod 无重启记录"
        elif [[ $total_restarts -lt 5 ]]; then
            record_warning "Pod 重启次数较少 ($total_restarts)"
        else
            record_failure "Pod 重启次数过多 ($total_restarts)"
        fi
    else
        record_failure "未找到应用程序 Pod"
    fi
    
    # 检查 Service
    if kubectl get service ai-code-reviewer -n "$NAMESPACE" &> /dev/null; then
        record_success "Service ai-code-reviewer 存在"
        
        # 检查 Service 端点
        local endpoints=$(kubectl get endpoints ai-code-reviewer -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}' | wc -w)
        if [[ $endpoints -gt 0 ]]; then
            record_success "Service 有 $endpoints 个端点"
        else
            record_failure "Service 没有可用端点"
        fi
    else
        record_failure "Service ai-code-reviewer 不存在"
    fi
    
    # 检查 Ingress
    if kubectl get ingress ai-code-reviewer -n "$NAMESPACE" &> /dev/null; then
        record_success "Ingress ai-code-reviewer 存在"
        
        local ingress_host=$(kubectl get ingress ai-code-reviewer -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].host}')
        if [[ -n "$ingress_host" ]]; then
            record_success "Ingress 配置主机: $ingress_host"
        else
            record_warning "Ingress 未配置主机"
        fi
    else
        record_failure "Ingress ai-code-reviewer 不存在"
    fi
}

# 检查应用程序健康状态
check_application_health() {
    log_info "=== 检查应用程序健康状态 ==="
    
    # 获取 Pod 名称
    local pod_name=$(kubectl get pods -l app=ai-code-reviewer -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [[ -z "$pod_name" ]]; then
        record_failure "无法获取 Pod 名称"
        return 1
    fi
    
    # 检查健康检查端点
    local health_endpoints=("/health" "/ready" "/startup")
    for endpoint in "${health_endpoints[@]}"; do
        if kubectl exec "$pod_name" -n "$NAMESPACE" -- curl -f "http://localhost:4195$endpoint" &> /dev/null; then
            record_success "健康检查端点 $endpoint 正常"
        else
            record_failure "健康检查端点 $endpoint 异常"
        fi
    done
    
    # 检查应用程序日志
    local error_count=$(kubectl logs "$pod_name" -n "$NAMESPACE" --tail=100 | grep -c "ERROR" || echo "0")
    if [[ $error_count -eq 0 ]]; then
        record_success "应用程序日志无错误"
    elif [[ $error_count -lt 5 ]]; then
        record_warning "应用程序日志有少量错误 ($error_count)"
    else
        record_failure "应用程序日志错误较多 ($error_count)"
    fi
}

# 检查外部服务连接
check_external_services() {
    log_info "=== 检查外部服务连接 ==="
    
    # 获取 Pod 名称
    local pod_name=$(kubectl get pods -l app=ai-code-reviewer -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [[ -z "$pod_name" ]]; then
        record_failure "无法获取 Pod 名称进行外部服务测试"
        return 1
    fi
    
    # 测试 GitLab 连接
    if kubectl exec "$pod_name" -n "$NAMESPACE" -- curl -s -I https://gitlab.com &> /dev/null; then
        record_success "GitLab 服务连接正常"
    else
        record_failure "GitLab 服务连接失败"
    fi
    
    # 测试 Dify API 连接
    if kubectl exec "$pod_name" -n "$NAMESPACE" -- curl -s -I https://api.dify.ai &> /dev/null; then
        record_success "Dify API 连接正常"
    else
        record_failure "Dify API 连接失败"
    fi
    
    # 测试 DNS 解析
    if kubectl exec "$pod_name" -n "$NAMESPACE" -- nslookup google.com &> /dev/null; then
        record_success "DNS 解析正常"
    else
        record_failure "DNS 解析失败"
    fi
}

# 检查资源使用情况
check_resource_usage() {
    log_info "=== 检查资源使用情况 ==="
    
    # 检查 Pod 资源使用
    if command -v kubectl &> /dev/null && kubectl top pod -l app=ai-code-reviewer -n "$NAMESPACE" &> /dev/null; then
        local pod_metrics=$(kubectl top pod -l app=ai-code-reviewer -n "$NAMESPACE" --no-headers)
        if [[ -n "$pod_metrics" ]]; then
            record_success "Pod 资源使用情况可获取"
            log_debug "资源使用: $pod_metrics"
        else
            record_warning "无法获取 Pod 资源使用情况"
        fi
    else
        record_warning "Metrics Server 不可用，无法检查资源使用"
    fi
    
    # 检查节点资源
    if kubectl top nodes &> /dev/null; then
        record_success "节点资源信息可获取"
    else
        record_warning "无法获取节点资源信息"
    fi
}

# 生成验证报告
generate_report() {
    log_info "=== 验证报告 ==="
    
    echo ""
    echo "验证结果统计:"
    echo "  成功: $SUCCESS_COUNT"
    echo "  警告: $WARNING_COUNT"
    echo "  失败: $FAILURE_COUNT"
    echo "  总计: $((SUCCESS_COUNT + WARNING_COUNT + FAILURE_COUNT))"
    echo ""
    
    if [[ $FAILURE_COUNT -eq 0 ]]; then
        if [[ $WARNING_COUNT -eq 0 ]]; then
            log_info "✓ 所有检查通过，应用程序配置正确"
            return 0
        else
            log_warn "! 检查通过但有警告，建议检查警告项"
            return 0
        fi
    else
        log_error "✗ 检查失败，请修复失败项后重新验证"
        return 1
    fi
}

# 显示修复建议
show_fix_suggestions() {
    if [[ $FAILURE_COUNT -gt 0 ]]; then
        log_info "=== 修复建议 ==="
        echo ""
        echo "常见问题修复方法:"
        echo ""
        echo "1. 如果 Secret 不存在或配置错误:"
        echo "   ./create-secrets.sh $NAMESPACE"
        echo ""
        echo "2. 如果 ConfigMap 不存在:"
        echo "   kubectl apply -f configmap.yaml -n $NAMESPACE"
        echo "   kubectl apply -f configmap-env.yaml -n $NAMESPACE"
        echo ""
        echo "3. 如果应用程序未部署:"
        echo "   ./deploy.sh $NAMESPACE"
        echo ""
        echo "4. 如果 Pod 状态异常:"
        echo "   kubectl describe pod -l app=ai-code-reviewer -n $NAMESPACE"
        echo "   kubectl logs -f deployment/ai-code-reviewer -n $NAMESPACE"
        echo ""
        echo "5. 如果健康检查失败:"
        echo "   kubectl exec deployment/ai-code-reviewer -n $NAMESPACE -- curl -v http://localhost:4195/health"
        echo ""
    fi
}

# 主函数
main() {
    log_info "开始验证 AI 代码审查应用配置 (环境: $NAMESPACE)"
    echo ""
    
    # 执行所有检查
    check_kubectl
    check_config_files
    check_k8s_resources
    check_application
    check_application_health
    check_external_services
    check_resource_usage
    
    echo ""
    
    # 生成报告
    if generate_report; then
        exit 0
    else
        show_fix_suggestions
        exit 1
    fi
}

# 显示帮助信息
show_help() {
    echo "AI 代码审查应用配置验证脚本"
    echo ""
    echo "使用方法:"
    echo "  $0 [环境名称]"
    echo ""
    echo "参数:"
    echo "  环境名称    目标 Kubernetes 命名空间 (默认: test)"
    echo ""
    echo "示例:"
    echo "  $0          # 验证 test 环境"
    echo "  $0 prod     # 验证 prod 环境"
    echo "  $0 staging  # 验证 staging 环境"
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
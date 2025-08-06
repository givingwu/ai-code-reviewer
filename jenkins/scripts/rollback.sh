#!/bin/bash

# Jenkins 回滚脚本
# 用于在部署失败时回滚到上一个稳定版本

set -e

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

# 检查必需的环境变量
check_env_vars() {
    local required_vars=("K8S_NAMESPACE" "K8S_DEPLOYMENT")
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            log_error "环境变量 $var 未设置"
            exit 1
        fi
    done
}

# 检查部署历史
check_rollout_history() {
    log_info "检查部署历史..."
    
    # 获取部署历史
    kubectl rollout history deployment/"${K8S_DEPLOYMENT}" -n "${K8S_NAMESPACE}"
    
    # 检查是否有历史版本可以回滚
    local history_count
    history_count=$(kubectl rollout history deployment/"${K8S_DEPLOYMENT}" -n "${K8S_NAMESPACE}" | grep -c "^[0-9]" || echo "0")
    
    if [ "${history_count}" -le 1 ]; then
        log_warn "没有可用的历史版本进行回滚"
        return 1
    fi
    
    log_info "发现 ${history_count} 个历史版本"
}

# 获取当前部署状态
get_current_status() {
    log_info "获取当前部署状态..."
    
    # 显示当前部署状态
    kubectl get deployment "${K8S_DEPLOYMENT}" -n "${K8S_NAMESPACE}"
    
    # 显示当前 Pod 状态
    kubectl get pods -n "${K8S_NAMESPACE}" -l app="${K8S_DEPLOYMENT}"
    
    # 检查部署是否健康
    local ready_replicas
    ready_replicas=$(kubectl get deployment "${K8S_DEPLOYMENT}" -n "${K8S_NAMESPACE}" \
        -o jsonpath='{.status.readyReplicas}' || echo "0")
    
    local desired_replicas
    desired_replicas=$(kubectl get deployment "${K8S_DEPLOYMENT}" -n "${K8S_NAMESPACE}" \
        -o jsonpath='{.spec.replicas}')
    
    log_info "就绪副本: ${ready_replicas}/${desired_replicas}"
    
    if [ "${ready_replicas}" != "${desired_replicas}" ]; then
        log_warn "部署状态不健康，需要回滚"
        return 1
    fi
    
    return 0
}

# 执行回滚
perform_rollback() {
    local revision=${1:-""}
    
    if [ -n "$revision" ]; then
        log_info "回滚到指定版本: $revision"
        kubectl rollout undo deployment/"${K8S_DEPLOYMENT}" \
            --to-revision="$revision" -n "${K8S_NAMESPACE}"
    else
        log_info "回滚到上一个版本..."
        kubectl rollout undo deployment/"${K8S_DEPLOYMENT}" -n "${K8S_NAMESPACE}"
    fi
}

# 等待回滚完成
wait_for_rollback() {
    log_info "等待回滚完成..."
    
    # 等待回滚状态
    if kubectl rollout status deployment/"${K8S_DEPLOYMENT}" \
        -n "${K8S_NAMESPACE}" --timeout=300s; then
        log_info "回滚成功完成"
    else
        log_error "回滚超时或失败"
        return 1
    fi
}

# 验证回滚结果
verify_rollback() {
    log_info "验证回滚结果..."
    
    # 检查部署状态
    kubectl get deployment "${K8S_DEPLOYMENT}" -n "${K8S_NAMESPACE}"
    
    # 检查 Pod 状态
    kubectl get pods -n "${K8S_NAMESPACE}" -l app="${K8S_DEPLOYMENT}"
    
    # 检查是否有运行中的 Pod
    local running_pods
    running_pods=$(kubectl get pods -n "${K8S_NAMESPACE}" \
        -l app="${K8S_DEPLOYMENT}" \
        --field-selector=status.phase=Running \
        -o jsonpath='{.items[*].metadata.name}' | wc -w)
    
    if [ "${running_pods}" -eq 0 ]; then
        log_error "回滚后没有运行中的 Pod"
        return 1
    fi
    
    log_info "回滚验证成功，发现 ${running_pods} 个运行中的 Pod"
    
    # 检查应用程序健康状态
    local pod_name
    pod_name=$(kubectl get pods -n "${K8S_NAMESPACE}" \
        -l app="${K8S_DEPLOYMENT}" \
        --field-selector=status.phase=Running \
        -o jsonpath='{.items[0].metadata.name}')
    
    if [ -n "$pod_name" ]; then
        log_info "测试回滚后的应用程序健康状态..."
        
        # 等待一段时间让应用程序启动
        sleep 30
        
        # 测试健康检查端点
        if kubectl exec -n "${K8S_NAMESPACE}" "$pod_name" -- \
            curl -f -s "http://localhost:4195/health" > /dev/null 2>&1; then
            log_info "应用程序健康检查通过"
        else
            log_warn "应用程序健康检查失败"
        fi
    fi
}

# 收集回滚信息
collect_rollback_info() {
    log_info "收集回滚信息..."
    
    # 显示当前版本信息
    log_info "当前部署版本信息:"
    kubectl describe deployment "${K8S_DEPLOYMENT}" -n "${K8S_NAMESPACE}" | grep -A 5 "Image:"
    
    # 显示回滚历史
    log_info "部署历史:"
    kubectl rollout history deployment/"${K8S_DEPLOYMENT}" -n "${K8S_NAMESPACE}"
    
    # 显示最近的事件
    log_info "最近的事件:"
    kubectl get events -n "${K8S_NAMESPACE}" \
        --sort-by='.lastTimestamp' \
        --field-selector involvedObject.name="${K8S_DEPLOYMENT}" \
        | tail -10
}

# 主函数
main() {
    local revision=${1:-""}
    
    log_info "开始回滚流程..."
    
    # 检查环境
    check_env_vars
    
    # 检查是否需要回滚
    if get_current_status; then
        log_info "当前部署状态正常，无需回滚"
        return 0
    fi
    
    # 检查回滚历史
    if ! check_rollout_history; then
        log_error "无法执行回滚，没有可用的历史版本"
        exit 1
    fi
    
    # 执行回滚
    perform_rollback "$revision"
    wait_for_rollback
    verify_rollback
    collect_rollback_info
    
    log_info "回滚流程完成！"
}

# 显示使用说明
usage() {
    echo "用法: $0 [revision]"
    echo ""
    echo "参数:"
    echo "  revision  可选，指定要回滚到的版本号"
    echo ""
    echo "示例:"
    echo "  $0        # 回滚到上一个版本"
    echo "  $0 3      # 回滚到版本 3"
    echo ""
    echo "环境变量:"
    echo "  K8S_NAMESPACE   Kubernetes 命名空间"
    echo "  K8S_DEPLOYMENT  部署名称"
}

# 处理命令行参数
case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    *)
        # 错误处理
        trap 'log_error "回滚脚本执行失败，退出码: $?"' ERR
        
        # 执行主函数
        main "$@"
        ;;
esac
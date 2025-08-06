#!/bin/bash

# Jenkins 集成测试脚本
# 用于测试部署后的应用程序

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

# 等待服务就绪
wait_for_service() {
    log_info "等待服务就绪..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log_info "等待服务就绪... (尝试 $attempt/$max_attempts)"
        
        # 检查 Pod 是否就绪
        local ready_pods
        ready_pods=$(kubectl get pods -n "${K8S_NAMESPACE}" \
            -l app="${K8S_DEPLOYMENT}" \
            -o jsonpath='{.items[?(@.status.conditions[?(@.type=="Ready")].status=="True")].metadata.name}' | wc -w)
        
        if [ "${ready_pods}" -gt 0 ]; then
            log_info "服务已就绪"
            return 0
        fi
        
        sleep 10
        ((attempt++))
    done
    
    log_error "服务在 ${max_attempts} 次尝试后仍未就绪"
    return 1
}

# 检查 Pod 健康状态
check_pod_health() {
    log_info "检查 Pod 健康状态..."
    
    # 获取 Pod 列表
    local pods
    pods=$(kubectl get pods -n "${K8S_NAMESPACE}" \
        -l app="${K8S_DEPLOYMENT}" \
        -o jsonpath='{.items[*].metadata.name}')
    
    if [ -z "$pods" ]; then
        log_error "未找到任何 Pod"
        return 1
    fi
    
    # 检查每个 Pod 的状态
    for pod in $pods; do
        log_info "检查 Pod: $pod"
        
        # 获取 Pod 状态
        local pod_status
        pod_status=$(kubectl get pod "$pod" -n "${K8S_NAMESPACE}" \
            -o jsonpath='{.status.phase}')
        
        log_info "Pod $pod 状态: $pod_status"
        
        if [ "$pod_status" != "Running" ]; then
            log_warn "Pod $pod 状态异常: $pod_status"
            
            # 显示 Pod 详细信息
            kubectl describe pod "$pod" -n "${K8S_NAMESPACE}"
        fi
    done
}

# 检查应用程序日志
check_application_logs() {
    log_info "检查应用程序日志..."
    
    # 获取最近的日志
    kubectl logs -n "${K8S_NAMESPACE}" \
        -l app="${K8S_DEPLOYMENT}" \
        --tail=50 \
        --timestamps=true
    
    # 检查是否有错误日志
    local error_count
    error_count=$(kubectl logs -n "${K8S_NAMESPACE}" \
        -l app="${K8S_DEPLOYMENT}" \
        --tail=100 | grep -i "error\|exception\|failed" | wc -l)
    
    if [ "${error_count}" -gt 0 ]; then
        log_warn "发现 ${error_count} 条错误日志"
        
        # 显示错误日志
        kubectl logs -n "${K8S_NAMESPACE}" \
            -l app="${K8S_DEPLOYMENT}" \
            --tail=100 | grep -i "error\|exception\|failed"
    else
        log_info "未发现错误日志"
    fi
}

# 测试健康检查端点
test_health_endpoint() {
    log_info "测试健康检查端点..."
    
    # 获取第一个运行中的 Pod
    local pod_name
    pod_name=$(kubectl get pods -n "${K8S_NAMESPACE}" \
        -l app="${K8S_DEPLOYMENT}" \
        --field-selector=status.phase=Running \
        -o jsonpath='{.items[0].metadata.name}')
    
    if [ -z "$pod_name" ]; then
        log_error "未找到运行中的 Pod"
        return 1
    fi
    
    log_info "测试 Pod: $pod_name"
    
    # 测试健康检查端点
    local endpoints=("/health" "/ready")
    
    for endpoint in "${endpoints[@]}"; do
        log_info "测试端点: $endpoint"
        
        if kubectl exec -n "${K8S_NAMESPACE}" "$pod_name" -- \
            curl -f -s "http://localhost:4195$endpoint" > /dev/null 2>&1; then
            log_info "端点 $endpoint 测试成功"
        else
            log_warn "端点 $endpoint 测试失败"
        fi
    done
}

# 测试 Webhook 端点
test_webhook_endpoint() {
    log_info "测试 Webhook 端点..."
    
    # 获取第一个运行中的 Pod
    local pod_name
    pod_name=$(kubectl get pods -n "${K8S_NAMESPACE}" \
        -l app="${K8S_DEPLOYMENT}" \
        --field-selector=status.phase=Running \
        -o jsonpath='{.items[0].metadata.name}')
    
    if [ -z "$pod_name" ]; then
        log_error "未找到运行中的 Pod"
        return 1
    fi
    
    # 创建测试负载
    local test_payload='{"test": "webhook", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'
    
    log_info "发送测试 Webhook 请求..."
    
    # 测试 Webhook 端点
    if kubectl exec -n "${K8S_NAMESPACE}" "$pod_name" -- \
        curl -f -s -X POST \
        -H "Content-Type: application/json" \
        -d "$test_payload" \
        "http://localhost:4195/" > /dev/null 2>&1; then
        log_info "Webhook 端点测试成功"
    else
        log_warn "Webhook 端点测试失败"
    fi
}

# 检查服务连通性
check_service_connectivity() {
    log_info "检查服务连通性..."
    
    # 检查服务是否存在
    if ! kubectl get service "${K8S_DEPLOYMENT}" -n "${K8S_NAMESPACE}" > /dev/null 2>&1; then
        log_error "服务 ${K8S_DEPLOYMENT} 不存在"
        return 1
    fi
    
    # 获取服务信息
    kubectl get service "${K8S_DEPLOYMENT}" -n "${K8S_NAMESPACE}"
    
    # 检查端点
    local endpoints
    endpoints=$(kubectl get endpoints "${K8S_DEPLOYMENT}" -n "${K8S_NAMESPACE}" \
        -o jsonpath='{.subsets[*].addresses[*].ip}')
    
    if [ -z "$endpoints" ]; then
        log_error "服务没有可用的端点"
        return 1
    fi
    
    log_info "服务端点: $endpoints"
}

# 性能基准测试
performance_test() {
    log_info "执行性能基准测试..."
    
    # 获取第一个运行中的 Pod
    local pod_name
    pod_name=$(kubectl get pods -n "${K8S_NAMESPACE}" \
        -l app="${K8S_DEPLOYMENT}" \
        --field-selector=status.phase=Running \
        -o jsonpath='{.items[0].metadata.name}')
    
    if [ -z "$pod_name" ]; then
        log_error "未找到运行中的 Pod"
        return 1
    fi
    
    # 检查资源使用情况
    log_info "检查资源使用情况..."
    kubectl top pod "$pod_name" -n "${K8S_NAMESPACE}" || log_warn "无法获取资源使用情况"
    
    # 简单的并发测试
    log_info "执行简单的并发测试..."
    
    local test_payload='{"test": "performance", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'
    local concurrent_requests=5
    
    for i in $(seq 1 $concurrent_requests); do
        kubectl exec -n "${K8S_NAMESPACE}" "$pod_name" -- \
            curl -f -s -X POST \
            -H "Content-Type: application/json" \
            -d "$test_payload" \
            "http://localhost:4195/" > /dev/null 2>&1 &
    done
    
    # 等待所有请求完成
    wait
    
    log_info "并发测试完成"
}

# 主函数
main() {
    log_info "开始集成测试..."
    
    # 检查环境
    check_env_vars
    
    # 执行测试
    wait_for_service
    check_pod_health
    check_application_logs
    test_health_endpoint
    test_webhook_endpoint
    check_service_connectivity
    performance_test
    
    log_info "集成测试完成！"
}

# 错误处理
trap 'log_error "测试脚本执行失败，退出码: $?"' ERR

# 执行主函数
main "$@"
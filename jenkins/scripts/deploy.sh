#!/bin/bash

# Jenkins 部署脚本
# 用于部署应用到 Kubernetes 集群

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
    local required_vars=("K8S_NAMESPACE" "K8S_DEPLOYMENT" "FULL_IMAGE_NAME")
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            log_error "环境变量 $var 未设置"
            exit 1
        fi
    done
}

# 检查 kubectl 连接
check_kubectl() {
    log_info "检查 kubectl 连接..."
    
    if ! kubectl cluster-info > /dev/null 2>&1; then
        log_error "无法连接到 Kubernetes 集群"
        exit 1
    fi
    
    log_info "Kubernetes 集群连接正常"
}

# 确保命名空间存在
ensure_namespace() {
    log_info "检查命名空间 ${K8S_NAMESPACE}..."
    
    if ! kubectl get namespace "${K8S_NAMESPACE}" > /dev/null 2>&1; then
        log_info "创建命名空间 ${K8S_NAMESPACE}..."
        kubectl create namespace "${K8S_NAMESPACE}"
    else
        log_info "命名空间 ${K8S_NAMESPACE} 已存在"
    fi
}

# 应用 Kubernetes 资源
apply_k8s_resources() {
    log_info "应用 Kubernetes 资源..."
    
    if [ ! -d "k8s" ]; then
        log_error "k8s 目录不存在"
        exit 1
    fi
    
    # 应用所有 YAML 文件
    kubectl apply -f k8s/ -n "${K8S_NAMESPACE}"
    
    log_info "Kubernetes 资源应用完成"
}

# 更新部署镜像
update_deployment() {
    log_info "更新部署镜像为 ${FULL_IMAGE_NAME}..."
    
    # 更新镜像
    kubectl set image deployment/"${K8S_DEPLOYMENT}" \
        "${K8S_DEPLOYMENT}"="${FULL_IMAGE_NAME}" \
        -n "${K8S_NAMESPACE}"
    
    log_info "部署镜像更新完成"
}

# 等待部署完成
wait_for_deployment() {
    log_info "等待部署完成..."
    
    # 等待部署状态
    if kubectl rollout status deployment/"${K8S_DEPLOYMENT}" \
        -n "${K8S_NAMESPACE}" --timeout=300s; then
        log_info "部署成功完成"
    else
        log_error "部署超时或失败"
        return 1
    fi
}

# 检查 Pod 状态
check_pod_status() {
    log_info "检查 Pod 状态..."
    
    # 获取 Pod 信息
    kubectl get pods -n "${K8S_NAMESPACE}" -l app="${K8S_DEPLOYMENT}"
    
    # 检查是否有运行中的 Pod
    local running_pods
    running_pods=$(kubectl get pods -n "${K8S_NAMESPACE}" \
        -l app="${K8S_DEPLOYMENT}" \
        --field-selector=status.phase=Running \
        -o jsonpath='{.items[*].metadata.name}' | wc -w)
    
    if [ "${running_pods}" -eq 0 ]; then
        log_error "没有运行中的 Pod"
        return 1
    fi
    
    log_info "发现 ${running_pods} 个运行中的 Pod"
}

# 验证服务
verify_service() {
    log_info "验证服务状态..."
    
    # 检查服务
    kubectl get service "${K8S_DEPLOYMENT}" -n "${K8S_NAMESPACE}"
    
    # 检查端点
    kubectl get endpoints "${K8S_DEPLOYMENT}" -n "${K8S_NAMESPACE}"
    
    log_info "服务验证完成"
}

# 主函数
main() {
    log_info "开始部署流程..."
    
    # 检查环境
    check_env_vars
    check_kubectl
    
    # 部署流程
    ensure_namespace
    apply_k8s_resources
    update_deployment
    wait_for_deployment
    check_pod_status
    verify_service
    
    log_info "部署流程完成！"
}

# 错误处理
trap 'log_error "部署脚本执行失败，退出码: $?"' ERR

# 执行主函数
main "$@"
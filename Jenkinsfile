pipeline {
    agent any
    
    environment {
        // 阿里云容器镜像服务配置
        ACR_REGISTRY = "${ACR_REGISTRY_URL}"
        ACR_NAMESPACE = "${ACR_NAMESPACE}"
        IMAGE_NAME = "ai-code-reviewer"
        
        // Kubernetes 配置
        K8S_NAMESPACE = "test"
        K8S_DEPLOYMENT = "ai-code-reviewer"
        
        // 构建配置
        BUILD_TAG = "${BUILD_NUMBER}-${GIT_COMMIT.take(7)}"
        FULL_IMAGE_NAME = "${ACR_REGISTRY}/${ACR_NAMESPACE}/${IMAGE_NAME}:${BUILD_TAG}"
        
        // 超时配置
        BUILD_TIMEOUT = "10"
        DEPLOY_TIMEOUT = "5"
        TEST_TIMEOUT = "3"
    }
    
    options {
        // 构建保留策略
        buildDiscarder(logRotator(numToKeepStr: '10'))
        // 全局超时
        timeout(time: 30, unit: 'MINUTES')
        // 时间戳
        timestamps()
    }
    
    stages {
        stage('代码检出') {
            steps {
                script {
                    echo "开始代码检出阶段..."
                    echo "Git Commit: ${GIT_COMMIT}"
                    echo "Git Branch: ${GIT_BRANCH}"
                    
                    // 清理工作空间
                    cleanWs()
                    
                    // 检出代码
                    checkout scm
                    
                    // 显示当前目录内容
                    sh 'ls -la'
                    
                    echo "代码检出完成"
                }
            }
        }
        
        stage('构建镜像') {
            steps {
                script {
                    echo "开始构建 Docker 镜像..."
                    echo "镜像名称: ${FULL_IMAGE_NAME}"
                    
                    timeout(time: "${BUILD_TIMEOUT}".toInteger(), unit: 'MINUTES') {
                        // 构建 Docker 镜像
                        sh """
                            cd docker
                            docker build -t ${FULL_IMAGE_NAME} .
                            docker tag ${FULL_IMAGE_NAME} ${ACR_REGISTRY}/${ACR_NAMESPACE}/${IMAGE_NAME}:latest
                        """
                        
                        // 显示镜像信息
                        sh "docker images | grep ${IMAGE_NAME}"
                    }
                    
                    echo "Docker 镜像构建完成"
                }
            }
        }
        
        stage('推送镜像') {
            steps {
                script {
                    echo "开始推送镜像到阿里云容器镜像服务..."
                    
                    // 使用凭据登录 ACR
                    withCredentials([usernamePassword(
                        credentialsId: 'aliyun-acr-credentials',
                        usernameVariable: 'ACR_USERNAME',
                        passwordVariable: 'ACR_PASSWORD'
                    )]) {
                        sh """
                            echo "登录到阿里云容器镜像服务..."
                            docker login -u \${ACR_USERNAME} -p \${ACR_PASSWORD} ${ACR_REGISTRY}
                            
                            echo "推送镜像..."
                            docker push ${FULL_IMAGE_NAME}
                            docker push ${ACR_REGISTRY}/${ACR_NAMESPACE}/${IMAGE_NAME}:latest
                            
                            echo "镜像推送完成"
                        """
                    }
                }
            }
        }
        
        stage('部署到测试环境') {
            steps {
                script {
                    echo "开始部署到 Kubernetes 测试环境..."
                    
                    timeout(time: "${DEPLOY_TIMEOUT}".toInteger(), unit: 'MINUTES') {
                        // 使用 kubectl 凭据
                        withCredentials([kubeconfigFile(
                            credentialsId: 'k8s-kubeconfig',
                            variable: 'KUBECONFIG'
                        )]) {
                            sh """
                                echo "检查 Kubernetes 连接..."
                                kubectl cluster-info
                                
                                echo "检查命名空间..."
                                kubectl get namespace ${K8S_NAMESPACE} || kubectl create namespace ${K8S_NAMESPACE}
                                
                                echo "应用 Kubernetes 资源..."
                                kubectl apply -f k8s/ -n ${K8S_NAMESPACE}
                                
                                echo "更新部署镜像..."
                                kubectl set image deployment/${K8S_DEPLOYMENT} ${K8S_DEPLOYMENT}=${FULL_IMAGE_NAME} -n ${K8S_NAMESPACE}
                                
                                echo "等待部署完成..."
                                kubectl rollout status deployment/${K8S_DEPLOYMENT} -n ${K8S_NAMESPACE} --timeout=300s
                                
                                echo "检查 Pod 状态..."
                                kubectl get pods -n ${K8S_NAMESPACE} -l app=${K8S_DEPLOYMENT}
                            """
                        }
                    }
                    
                    echo "部署到测试环境完成"
                }
            }
        }
        
        stage('集成测试') {
            steps {
                script {
                    echo "开始集成测试..."
                    
                    timeout(time: "${TEST_TIMEOUT}".toInteger(), unit: 'MINUTES') {
                        withCredentials([kubeconfigFile(
                            credentialsId: 'k8s-kubeconfig',
                            variable: 'KUBECONFIG'
                        )]) {
                            sh """
                                echo "等待服务就绪..."
                                sleep 30
                                
                                echo "检查服务状态..."
                                kubectl get service ${K8S_DEPLOYMENT} -n ${K8S_NAMESPACE}
                                
                                echo "检查 Pod 健康状态..."
                                kubectl get pods -n ${K8S_NAMESPACE} -l app=${K8S_DEPLOYMENT}
                                
                                echo "检查应用程序日志..."
                                kubectl logs -n ${K8S_NAMESPACE} -l app=${K8S_DEPLOYMENT} --tail=50
                                
                                echo "测试健康检查端点..."
                                POD_NAME=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=${K8S_DEPLOYMENT} -o jsonpath='{.items[0].metadata.name}')
                                if [ ! -z "\$POD_NAME" ]; then
                                    echo "测试 Pod: \$POD_NAME"
                                    kubectl exec -n ${K8S_NAMESPACE} \$POD_NAME -- curl -f http://localhost:4195/health || echo "健康检查端点测试失败"
                                fi
                            """
                        }
                    }
                    
                    echo "集成测试完成"
                }
            }
        }
        
        stage('部署验证') {
            steps {
                script {
                    echo "开始部署验证..."
                    
                    withCredentials([kubeconfigFile(
                        credentialsId: 'k8s-kubeconfig',
                        variable: 'KUBECONFIG'
                    )]) {
                        sh """
                            echo "验证部署状态..."
                            kubectl get deployment ${K8S_DEPLOYMENT} -n ${K8S_NAMESPACE}
                            
                            echo "验证 Pod 运行状态..."
                            READY_PODS=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=${K8S_DEPLOYMENT} --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}' | wc -w)
                            echo "运行中的 Pod 数量: \$READY_PODS"
                            
                            if [ "\$READY_PODS" -eq "0" ]; then
                                echo "错误: 没有运行中的 Pod"
                                exit 1
                            fi
                            
                            echo "验证服务端点..."
                            kubectl get endpoints ${K8S_DEPLOYMENT} -n ${K8S_NAMESPACE}
                            
                            echo "部署验证成功"
                        """
                    }
                }
            }
        }
    }
    
    post {
        always {
            script {
                echo "流水线执行完成，开始清理..."
                
                // 清理本地 Docker 镜像
                sh """
                    echo "清理本地镜像..."
                    docker rmi ${FULL_IMAGE_NAME} || true
                    docker rmi ${ACR_REGISTRY}/${ACR_NAMESPACE}/${IMAGE_NAME}:latest || true
                    
                    echo "清理悬空镜像..."
                    docker image prune -f || true
                """
                
                // 归档构建日志
                archiveArtifacts artifacts: 'k8s/*.yaml', allowEmptyArchive: true
            }
        }
        
        success {
            script {
                echo "🎉 流水线执行成功！"
                echo "镜像: ${FULL_IMAGE_NAME}"
                echo "部署环境: ${K8S_NAMESPACE}"
                
                // 发送成功通知（可选）
                // 这里可以添加钉钉、邮件等通知
            }
        }
        
        failure {
            script {
                echo "❌ 流水线执行失败！"
                
                // 收集失败信息
                withCredentials([kubeconfigFile(
                    credentialsId: 'k8s-kubeconfig',
                    variable: 'KUBECONFIG'
                )]) {
                    sh """
                        echo "收集故障信息..."
                        
                        echo "=== Pod 状态 ==="
                        kubectl get pods -n ${K8S_NAMESPACE} -l app=${K8S_DEPLOYMENT} || true
                        
                        echo "=== Pod 日志 ==="
                        kubectl logs -n ${K8S_NAMESPACE} -l app=${K8S_DEPLOYMENT} --tail=100 || true
                        
                        echo "=== 事件信息 ==="
                        kubectl get events -n ${K8S_NAMESPACE} --sort-by='.lastTimestamp' || true
                    """ 
                }
                
                // 尝试回滚到上一个版本
                try {
                    withCredentials([kubeconfigFile(
                        credentialsId: 'k8s-kubeconfig',
                        variable: 'KUBECONFIG'
                    )]) {
                        sh """
                            echo "尝试回滚到上一个版本..."
                            kubectl rollout undo deployment/${K8S_DEPLOYMENT} -n ${K8S_NAMESPACE}
                            kubectl rollout status deployment/${K8S_DEPLOYMENT} -n ${K8S_NAMESPACE} --timeout=300s
                            echo "回滚完成"
                        """
                    }
                } catch (Exception e) {
                    echo "回滚失败: ${e.getMessage()}"
                }
                
                // 发送失败通知（可选）
                // 这里可以添加钉钉、邮件等通知
            }
        }
        
        unstable {
            script {
                echo "⚠️ 流水线执行不稳定"
                // 发送警告通知
            }
        }
        
        aborted {
            script {
                echo "🛑 流水线执行被中止"
                // 清理资源
            }
        }
    }
}
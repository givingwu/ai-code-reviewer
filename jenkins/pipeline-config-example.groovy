// Jenkins 流水线配置示例
// 用于快速配置 Jenkins 流水线项目

// 流水线配置
pipelineJob('ai-code-reviewer-pipeline') {
    description('AI 代码审查应用的 CI/CD 流水线')
    
    // Git 配置
    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url('https://git.kuainiujinke.com/your-group/ai-code-reviewer.git')
                        credentials('gitlab-credentials')
                    }
                    branch('*/main')
                }
            }
            scriptPath('Jenkinsfile')
        }
    }
    
    // 构建触发器
    triggers {
        // Git Hook 触发
        gitlabPush {
            buildOnMergeRequestEvents(true)
            buildOnPushEvents(true)
            enableCiSkip(false)
            setBuildDescription(false)
            rebuildOpenMergeRequest('never')
        }
        
        // 定时构建（每天凌晨2点）
        cron('H 2 * * *')
    }
    
    // 构建参数
    parameters {
        stringParam('IMAGE_TAG', '', '可选：指定镜像标签，留空则使用默认标签')
        booleanParam('SKIP_TESTS', false, '跳过集成测试')
        choiceParam('DEPLOY_ACTION', ['deploy', 'rollback'], '部署操作类型')
    }
    
    // 构建保留策略
    logRotator {
        numToKeep(20)
        daysToKeep(30)
    }
    
    // 并发构建限制
    concurrentBuild(false)
    
    // 构建环境
    environmentVariables {
        env('ACR_REGISTRY_URL', 'registry.cn-hangzhou.aliyuncs.com')
        env('ACR_NAMESPACE', 'your-namespace')
        env('K8S_NAMESPACE', 'test')
        env('K8S_DEPLOYMENT', 'ai-code-reviewer')
    }
}

// 多分支流水线配置（可选）
multibranchPipelineJob('ai-code-reviewer-multibranch') {
    description('AI 代码审查应用的多分支流水线')
    
    branchSources {
        git {
            id('ai-code-reviewer-git')
            remote('https://git.kuainiujinke.com/your-group/ai-code-reviewer.git')
            credentialsId('gitlab-credentials')
            
            // 分支发现策略
            traits {
                gitBranchDiscovery()
                gitTagDiscovery()
                
                // 只构建特定分支
                headRegexFilter {
                    regex('(main|develop|feature/.*|hotfix/.*)')
                }
            }
        }
    }
    
    // 扫描触发器
    triggers {
        periodic(5) // 每5分钟扫描一次
    }
    
    // Jenkinsfile 路径
    factory {
        workflowBranchProjectFactory {
            scriptPath('Jenkinsfile')
        }
    }
}

// 凭据配置示例
folder('credentials') {
    description('存储 CI/CD 相关凭据')
}

// GitLab 凭据
usernamePassword('gitlab-credentials') {
    scope('GLOBAL')
    description('GitLab 访问凭据')
    username('your-gitlab-username')
    password('your-gitlab-token')
}

// 阿里云 ACR 凭据
usernamePassword('aliyun-acr-credentials') {
    scope('GLOBAL')
    description('阿里云容器镜像服务凭据')
    username('your-acr-username')
    password('your-acr-password')
}

// Kubernetes kubeconfig 文件
secretFile('k8s-kubeconfig') {
    scope('GLOBAL')
    description('Kubernetes 集群配置文件')
    fileName('kubeconfig')
    secretBytes('your-kubeconfig-content-base64')
}

// 全局工具配置
configure { project ->
    project / 'properties' / 'jenkins.model.BuildDiscarderProperty' {
        strategy {
            'daysToKeep'('30')
            'numToKeep'('20')
            'artifactDaysToKeep'('7')
            'artifactNumToKeep'('5')
        }
    }
}

// 系统配置
configure { root ->
    // Git 配置
    root / 'scm' / 'git' {
        'globalConfigName'('Jenkins CI')
        'globalConfigEmail'('jenkins@company.com')
    }
    
    // Docker 配置
    root / 'clouds' / 'com.nirima.jenkins.plugins.docker.DockerCloud' {
        'name'('docker')
        'dockerApi' {
            'dockerHost' {
                'uri'('unix:///var/run/docker.sock')
            }
        }
    }
}

// 视图配置
listView('AI Code Reviewer') {
    description('AI 代码审查相关的构建任务')
    jobs {
        regex('ai-code-reviewer.*')
    }
    columns {
        status()
        weather()
        name()
        lastSuccess()
        lastFailure()
        lastDuration()
        buildButton()
    }
}

// 通知配置示例
configure { project ->
    project / 'publishers' / 'hudson.plugins.emailext.ExtendedEmailPublisher' {
        'recipientList'('team@company.com')
        'configuredTriggers' {
            'hudson.plugins.emailext.plugins.trigger.FailureTrigger' {
                'email' {
                    'recipientList'('$DEFAULT_RECIPIENTS')
                    'subject'('$DEFAULT_SUBJECT')
                    'body'('$DEFAULT_CONTENT')
                }
            }
            'hudson.plugins.emailext.plugins.trigger.SuccessTrigger' {
                'email' {
                    'recipientList'('$DEFAULT_RECIPIENTS')
                    'subject'('构建成功: $PROJECT_NAME - $BUILD_NUMBER')
                    'body'('构建成功完成，部署已更新。')
                }
            }
        }
    }
}
```groovy
pipeline {
    agent any

    triggers {
        githubPush()
    }

    options {
        disableConcurrentBuilds()
        timestamps()
    }

    parameters {
        choice(
            name: 'ACTION',
            choices: ['deploy', 'destroy'],
            description: 'Choose whether to deploy or destroy the infrastructure.'
        )
    }

    environment {
        TF_IN_AUTOMATION = 'true'
        TF_VAR_aws_region = 'ap-south-1'

        TF_VAR_key_name = credentials('chat-ec2-key-name')
        TF_VAR_admin_cidr = credentials('chat-admin-cidr')
        TF_VAR_ssh_public_key = credentials('chat-ssh-public-key')
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Check Tools') {
            steps {
                sh '''
                    set -e

                    echo "=============================="
                    echo "Terraform"
                    echo "=============================="
                    terraform version

                    echo "=============================="
                    echo "Ansible"
                    echo "=============================="
                    ansible-playbook --version

                    echo "=============================="
                    echo "SSH"
                    echo "=============================="
                    ssh -V

                    echo "=============================="
                    echo "AWS CLI"
                    echo "=============================="
                    aws --version

                    echo "=============================="
                    echo "Docker"
                    echo "=============================="
                    docker --version
                '''
            }
        }

        stage('Terraform Init') {
            steps {
                sh '''
                    set -e
                    terraform -chdir=infra init -input=false
                '''
            }
        }

        stage('Terraform Validate') {
            when {
                expression {
                    params.ACTION == 'deploy'
                }
            }

            steps {
                sh '''
                    set -e

                    terraform -chdir=infra fmt -check
                    terraform -chdir=infra validate
                '''
            }
        }

        stage('Terraform Deploy') {
            when {
                expression {
                    params.ACTION == 'deploy'
                }
            }

            steps {
                withCredentials([
                    [
                        $class: 'AmazonWebServicesCredentialsBinding',
                        credentialsId: 'chat-aws',
                        accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                        secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
                    ]
                ]) {
                    sh '''
                        set -e

                        terraform -chdir=infra apply \
                            -auto-approve \
                            -input=false
                    '''
                }
            }
        }

        stage('Get EC2 Public IP') {
            when {
                expression {
                    params.ACTION == 'deploy'
                }
            }

            steps {
                script {

                    def publicIp = sh(
                        script: 'terraform -chdir=infra output -raw public_ip',
                        returnStdout: true
                    ).trim()

                    if (!publicIp) {
                        error("Terraform did not return a public IP.")
                    }

                    env.PUBLIC_IP = publicIp
                    env.APPLICATION_URL = "http://${publicIp}"

                    echo "=========================================="
                    echo "EC2 PUBLIC IP: ${env.PUBLIC_IP}"
                    echo "APPLICATION URL: ${env.APPLICATION_URL}"
                    echo "=========================================="
                }
            }
        }

        stage('Deploy Application With Ansible') {
            when {
                expression {
                    params.ACTION == 'deploy'
                }
            }

            steps {

                withCredentials([

                    string(
                        credentialsId: 'chat-mongodb-uri',
                        variable: 'MONGODB_URI'
                    ),

                    string(
                        credentialsId: 'chat-jwt-secret',
                        variable: 'JWT_SECRET'
                    ),

                    sshUserPrivateKey(
                        credentialsId: 'chat-ec2-private-key',
                        keyFileVariable: 'SSH_PRIVATE_KEY',
                        usernameVariable: 'SSH_USERNAME'
                    )

                ]) {

                    script {

                        writeFile(
                            file: 'ansible/jenkins-inventory.ini',
                            text: """
[chat]
${env.PUBLIC_IP} ansible_user=${env.SSH_USERNAME} ansible_ssh_private_key_file=${env.SSH_PRIVATE_KEY} ansible_ssh_common_args='-o StrictHostKeyChecking=no'
"""
                        )

                        writeFile(
                            file: 'ansible/jenkins-vars.yml',
                            text: """
required_frontend_origin: "${env.APPLICATION_URL}"
required_mongodb_uri: "${MONGODB_URI}"
required_jwt_secret: "${JWT_SECRET}"
"""
                        )

                        echo "=========================================="
                        echo "Starting Ansible deployment"
                        echo "=========================================="

                        sh '''
                            set -e

                            ansible-playbook \
                                -i ansible/jenkins-inventory.ini \
                                ansible/site.yml \
                                -e "@ansible/jenkins-vars.yml"
                        '''
                    }
                }
            }
        }

        stage('Verify Public Application') {
            when {
                expression {
                    params.ACTION == 'deploy'
                }
            }

            steps {

                script {

                    def maxAttempts = 30
                    def attempt = 0
                    def success = false

                    while (attempt < maxAttempts) {

                        echo "Checking ${env.APPLICATION_URL}/health"

                        def result = sh(
                            script: """
                                curl -fsS "${env.APPLICATION_URL}/health" \
                                > /dev/null 2>&1
                            """,
                            returnStatus: true
                        )

                        if (result == 0) {

                            success = true

                            echo "=========================================="
                            echo "APPLICATION IS LIVE"
                            echo "=========================================="
                            echo "URL: ${env.APPLICATION_URL}"
                            echo "=========================================="

                            break
                        }

                        attempt++

                        echo "Application not ready."
                        echo "Attempt ${attempt}/${maxAttempts}"

                        sleep 10
                    }

                    if (!success) {
                        error("Application did not become reachable.")
                    }
                }
            }
        }

        stage('Destroy Infrastructure') {
            when {
                expression {
                    params.ACTION == 'destroy'
                }
            }

            steps {

                withCredentials([
                    [
                        $class: 'AmazonWebServicesCredentialsBinding',
                        credentialsId: 'chat-aws',
                        accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                        secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
                    ]
                ]) {

                    sh '''
                        set -e

                        terraform -chdir=infra destroy \
                            -auto-approve \
                            -input=false
                    '''
                }
            }
        }
    }

    post {

        success {
            script {

                if (params.ACTION == 'deploy') {

                    echo """
==================================================
          CHAT APPLICATION DEPLOYED
==================================================

Live URL:
${env.APPLICATION_URL}

Public IP:
${env.PUBLIC_IP}

==================================================
Share this URL with users.
==================================================
"""

                } else {

                    echo """
==================================================
       ALL TERRAFORM RESOURCES DESTROYED
==================================================
"""
                }
            }
        }

        failure {

            echo """
==================================================
              PIPELINE FAILED
==================================================
"""
        }

        always {

            sh '''
                rm -f ansible/jenkins-inventory.ini || true
                rm -f ansible/jenkins-vars.yml || true
            '''
        }
    }
}
```

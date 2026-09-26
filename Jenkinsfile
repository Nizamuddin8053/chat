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

        stage('Terraform Init') {
            steps {
                sh '''
                    set -eu

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
                    set -eu

                    terraform -chdir=infra fmt -check
                    terraform -chdir=infra validate
                '''
            }
        }

        stage('Build Docker Images') {
            when {
                expression {
                    params.ACTION == 'deploy'
                }
            }

            steps {
                sh '''
                    set -eu

                    docker compose config -q
                    docker compose build
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
                        set -eu

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
                    env.PUBLIC_IP = sh(
                        script: '''
                            terraform -chdir=infra output -raw public_ip
                        ''',
                        returnStdout: true
                    ).trim()

                    env.APPLICATION_URL = "http://${env.PUBLIC_IP}"

                    echo "EC2 Public IP: ${env.PUBLIC_IP}"
                    echo "Application URL: ${env.APPLICATION_URL}"
                }
            }
        }

        stage('Create Ansible Inventory') {
            when {
                expression {
                    params.ACTION == 'deploy'
                }
            }

            steps {
                sh '''
                    set -eu

                    cat > inventory.ini <<EOF
[chat]
${PUBLIC_IP} ansible_user=ubuntu
EOF

                    cat inventory.ini
                '''
            }
        }

        stage('Deploy Application with Ansible') {
            when {
                expression {
                    params.ACTION == 'deploy'
                }
            }

            steps {
                withCredentials([
                    string(
                        credentialsId: 'chat-mongodb-uri',
                        variable: 'CHAT_MONGODB_URI'
                    ),

                    string(
                        credentialsId: 'chat-jwt-secret',
                        variable: 'CHAT_JWT_SECRET'
                    ),

                    sshUserPrivateKey(
                        credentialsId: 'chat-ec2-private-key',
                        keyFileVariable: 'SSH_PRIVATE_KEY',
                        usernameVariable: 'SSH_USERNAME'
                    )
                ]) {

                    sh '''
                        set -eu

                        ansible-playbook \
                            ansible/site.yml \
                            -i inventory.ini \
                            --private-key "$SSH_PRIVATE_KEY" \
                            --extra-vars "required_frontend_origin=http://$PUBLIC_IP required_mongodb_uri=$CHAT_MONGODB_URI required_jwt_secret=$CHAT_JWT_SECRET" \
                            --ssh-extra-args "-o StrictHostKeyChecking=no"
                    '''
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
                sh '''
                    set -eu

                    echo "Checking public application..."

                    for i in $(seq 1 30); do
                        if curl -fsS "$APPLICATION_URL/health" > /dev/null; then
                            echo "Application is publicly reachable."
                            exit 0
                        fi

                        echo "Waiting for application..."
                        sleep 10
                    done

                    echo "Application did not become reachable."
                    exit 1
                '''
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
                        set -eu

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
            echo "Pipeline failed."
        }

        always {
            sh '''
                rm -f inventory.ini || true
            '''
        }
    }
}             

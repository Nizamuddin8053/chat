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

        /*
         * ==========================================
         * CHECKOUT
         * ==========================================
         */

        stage('Checkout') {
            steps {
                checkout scm
            }
        }


        /*
         * ==========================================
         * TERRAFORM INIT
         * ==========================================
         */

        stage('Terraform Init') {
            steps {
                bat '''
                    terraform -chdir=infra init -input=false
                '''
            }
        }


        /*
         * ==========================================
         * TERRAFORM VALIDATE
         * ==========================================
         */

        stage('Terraform Validate') {
            when {
                expression {
                    params.ACTION == 'deploy'
                }
            }

            steps {
                bat '''
                    terraform -chdir=infra fmt -check
                    if errorlevel 1 exit /b 1

                    terraform -chdir=infra validate
                    if errorlevel 1 exit /b 1
                '''
            }
        }


        /*
         * ==========================================
         * BUILD DOCKER IMAGES
         * ==========================================
         */

        stage('Build Docker Images') {
            when {
                expression {
                    params.ACTION == 'deploy'
                }
            }

            steps {
                bat '''
                    docker compose config -q
                    if errorlevel 1 exit /b 1

                    docker compose build
                    if errorlevel 1 exit /b 1
                '''
            }
        }


        /*
         * ==========================================
         * TERRAFORM DEPLOY
         * ==========================================
         */

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
                    bat '''
                        terraform -chdir=infra apply -auto-approve -input=false
                    '''
                }
            }
        }


        /*
         * ==========================================
         * GET EC2 PUBLIC IP
         * ==========================================
         */

        stage('Get EC2 Public IP') {
            when {
                expression {
                    params.ACTION == 'deploy'
                }
            }

            steps {
                script {

                    def publicIp = bat(
                        script: 'terraform -chdir=infra output -raw public_ip',
                        returnStdout: true
                    ).trim()

                    // Remove possible command echo / whitespace
                    publicIp = publicIp
                        .readLines()
                        .findAll { line ->
                            line?.trim() &&
                            !line.contains('terraform -chdir')
                        }
                        .last()
                        .trim()

                    env.PUBLIC_IP = publicIp
                    env.APPLICATION_URL = "http://${env.PUBLIC_IP}"

                    echo "EC2 Public IP: ${env.PUBLIC_IP}"
                    echo "Application URL: ${env.APPLICATION_URL}"
                }
            }
        }


        /*
         * ==========================================
         * CREATE ANSIBLE INVENTORY
         * ==========================================
         */

        stage('Create Ansible Inventory') {
            when {
                expression {
                    params.ACTION == 'deploy'
                }
            }

            steps {
                bat '''
                    (
                        echo [chat]
                        echo %PUBLIC_IP% ansible_user=ubuntu
                    ) > inventory.ini

                    type inventory.ini
                '''
            }
        }


        /*
         * ==========================================
         * DEPLOY APPLICATION WITH ANSIBLE
         * ==========================================
         */

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

                    bat '''
                        ansible-playbook ansible/site.yml ^
                            -i inventory.ini ^
                            --private-key "%SSH_PRIVATE_KEY%" ^
                            --extra-vars "required_frontend_origin=http://%PUBLIC_IP% required_mongodb_uri=%CHAT_MONGODB_URI% required_jwt_secret=%CHAT_JWT_SECRET%" ^
                            --ssh-extra-args "-o StrictHostKeyChecking=no"
                    '''
                }
            }
        }


        /*
         * ==========================================
         * VERIFY PUBLIC APPLICATION
         * ==========================================
         */

        stage('Verify Public Application') {
            when {
                expression {
                    params.ACTION == 'deploy'
                }
            }

            steps {
                bat '''
                    echo Checking public application...

                    set "RETRY_COUNT=0"

                    :CHECK_APPLICATION

                    curl -fsS "%APPLICATION_URL%/health" > nul 2>&1

                    if not errorlevel 1 (
                        echo Application is publicly reachable.
                        exit /b 0
                    )

                    set /a RETRY_COUNT+=1

                    if %RETRY_COUNT% GEQ 30 (
                        echo Application did not become reachable.
                        exit /b 1
                    )

                    echo Waiting for application...
                    timeout /t 10 /nobreak > nul

                    goto CHECK_APPLICATION
                '''
            }
        }


        /*
         * ==========================================
         * DESTROY INFRASTRUCTURE
         * ==========================================
         */

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

                    bat '''
                        terraform -chdir=infra destroy -auto-approve -input=false
                    '''
                }
            }
        }
    }


    /*
     * ==========================================
     * POST ACTIONS
     * ==========================================
     */

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
            bat '''
                if exist inventory.ini del /f /q inventory.ini
            '''
        }
    }
}

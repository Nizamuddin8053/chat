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
        PATH = "C:\\Users\\acer\\AppData\\Local\\Microsoft\\WinGet\\Packages\\Hashicorp.Terraform_Microsoft.Winget.Source_8wekyb3d8bbwe;${env.PATH}"

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
                bat '''
                    echo ==============================
                    echo Terraform
                    echo ==============================
                    terraform version

                    echo ==============================
                    echo Ansible
                    echo ==============================
                    ansible-playbook --version

                    echo ==============================
                    echo SSH
                    echo ==============================
                    ssh -V
                '''
            }
        }

        stage('Terraform Init') {
            steps {
                bat '''
                    terraform -chdir=infra init -input=false
                    if errorlevel 1 exit /b 1
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
                bat '''
                    terraform -chdir=infra fmt -check
                    if errorlevel 1 exit /b 1

                    terraform -chdir=infra validate
                    if errorlevel 1 exit /b 1
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
                    bat '''
                        terraform -chdir=infra apply -auto-approve -input=false
                        if errorlevel 1 exit /b 1
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

                    def publicIp = bat(
                        script: 'terraform -chdir=infra output -raw public_ip',
                        returnStdout: true
                    ).trim()

                    publicIp = publicIp
                        .readLines()
                        .findAll { line ->
                            line?.trim() &&
                            !line.contains('terraform -chdir')
                        }
                        .last()
                        .trim()

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

                        /*
                         * Temporary Ansible inventory
                         */
                        writeFile(
                            file: 'ansible\\jenkins-inventory.ini',
                            text: """
[chat]
${env.PUBLIC_IP} ansible_user=${env.SSH_USERNAME} ansible_ssh_private_key_file=${env.SSH_PRIVATE_KEY}
"""
                        )

                        /*
                         * Temporary Ansible variables
                         */
                        writeFile(
                            file: 'ansible\\jenkins-vars.yml',
                            text: """
required_frontend_origin: "${env.APPLICATION_URL}"
required_mongodb_uri: "${MONGODB_URI}"
required_jwt_secret: "${JWT_SECRET}"
"""
                        )

                        echo "=========================================="
                        echo "Starting Ansible deployment"
                        echo "=========================================="

                        bat '''
                            ansible-playbook ^
                                -i ansible\\jenkins-inventory.ini ^
                                ansible\\site.yml ^
                                -e "@ansible\\jenkins-vars.yml"

                            if errorlevel 1 exit /b 1
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

                        def result = bat(
                            script: """
                                curl -fsS "${env.APPLICATION_URL}/health" > nul 2>&1
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

                        bat '''
                            timeout /t 10 /nobreak > nul
                        '''
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

                    bat '''
                        terraform -chdir=infra destroy -auto-approve -input=false

                        if errorlevel 1 exit /b 1
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

            bat '''
                if exist ansible\\jenkins-inventory.ini del /f /q ansible\\jenkins-inventory.ini
                if exist ansible\\jenkins-vars.yml del /f /q ansible\\jenkins-vars.yml
            '''
        }
    }
}
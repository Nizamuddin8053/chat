pipeline {
    agent any

    triggers {
        githubPush()
    }

    options {
        disableConcurrentBuilds(abortPrevious: true)
        timestamps()
        timeout(time: 40, unit: 'MINUTES')
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

        // ============================================================
        // CHECKOUT
        // ============================================================

        stage('Checkout') {
            steps {
                checkout scm
            }
        }


        // ============================================================
        // CHECK TOOLS
        // ============================================================

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

                    echo "=============================="
                    echo "Curl"
                    echo "=============================="
                    curl --version | head -n 1
                '''
            }
        }


        // ============================================================
        // TERRAFORM INIT
        // ============================================================

        stage('Terraform Init') {
            steps {
                sh '''
                    set -e

                    terraform -chdir=infra init \
                        -input=false \
                        -no-color
                '''
            }
        }


        // ============================================================
        // CLEAN OLD AWS RESOURCES
        // ============================================================

        stage('Clean Previous AWS Resources') {
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

                        echo "=========================================="
                        echo "CLEANING PREVIOUS CHAT RESOURCES"
                        echo "=========================================="


                        # -------------------------------
                        # Find old EC2
                        # -------------------------------

                        INSTANCE_IDS=$(aws ec2 describe-instances \
                            --filters \
                            Name=tag:Name,Values=chat-app \
                            Name=instance-state-name,Values=pending,running,stopping,stopped \
                            --query 'Reservations[].Instances[].InstanceId' \
                            --output text)

                        if [ -n "$INSTANCE_IDS" ] && [ "$INSTANCE_IDS" != "None" ]; then

                            echo "Old EC2 found: $INSTANCE_IDS"

                            aws ec2 terminate-instances \
                                --instance-ids $INSTANCE_IDS

                            echo "Waiting for EC2 termination..."

                            aws ec2 wait instance-terminated \
                                --instance-ids $INSTANCE_IDS

                            echo "EC2 termination completed."

                        else
                            echo "No old chat-app EC2 found."
                        fi


                        # -------------------------------
                        # Delete Security Group
                        # -------------------------------

                        DEFAULT_VPC=$(aws ec2 describe-vpcs \
                            --filters Name=is-default,Values=true \
                            --query 'Vpcs[0].VpcId' \
                            --output text)

                        echo "Default VPC: $DEFAULT_VPC"


                        SG_ID=$(aws ec2 describe-security-groups \
                            --filters \
                            Name=group-name,Values=chat-app-sg \
                            Name=vpc-id,Values=$DEFAULT_VPC \
                            --query 'SecurityGroups[0].GroupId' \
                            --output text 2>/dev/null || true)


                        if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then

                            echo "Old Security Group found: $SG_ID"

                            for i in $(seq 1 12); do

                                if aws ec2 delete-security-group \
                                    --group-id "$SG_ID" 2>/dev/null; then

                                    echo "Security Group deleted."
                                    break

                                fi

                                if [ "$i" -eq 12 ]; then
                                    echo "Could not delete Security Group."
                                    exit 1
                                fi

                                echo "Security Group still in use. Retry $i/12"
                                sleep 5
                            done

                        else
                            echo "No old Security Group found."
                        fi


                        # -------------------------------
                        # Delete Key Pair
                        # -------------------------------

                        KEY_EXISTS=$(aws ec2 describe-key-pairs \
                            --key-names chat-app-deploy \
                            --query 'KeyPairs[0].KeyName' \
                            --output text 2>/dev/null || true)


                        if [ "$KEY_EXISTS" = "chat-app-deploy" ]; then

                            echo "Deleting old Key Pair..."

                            aws ec2 delete-key-pair \
                                --key-name chat-app-deploy

                            echo "Key Pair deleted."

                        else
                            echo "No old Key Pair found."
                        fi


                        echo "=========================================="
                        echo "CLEANUP COMPLETED"
                        echo "=========================================="
                    '''
                }
            }
        }


        // ============================================================
        // TERRAFORM VALIDATE
        // ============================================================

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


        // ============================================================
        // TERRAFORM DEPLOY
        // ============================================================

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

                        echo "=========================================="
                        echo "STARTING TERRAFORM DEPLOYMENT"
                        echo "=========================================="

                        terraform -chdir=infra apply \
                            -auto-approve \
                            -input=false \
                            -no-color

                        echo "=========================================="
                        echo "TERRAFORM DEPLOYMENT COMPLETED"
                        echo "=========================================="
                    '''
                }
            }
        }


        // ============================================================
        // GET EC2 PUBLIC IP
        // ============================================================

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


        // ============================================================
        // WAIT FOR SSH
        // ============================================================

        stage('Wait For SSH') {
            when {
                expression {
                    params.ACTION == 'deploy'
                }
            }

            steps {
                withCredentials([
                    sshUserPrivateKey(
                        credentialsId: 'chat-ec2-private-key',
                        keyFileVariable: 'SSH_PRIVATE_KEY',
                        usernameVariable: 'SSH_USERNAME'
                    )
                ]) {

                    sh '''
                        set -e

                        echo "=========================================="
                        echo "WAITING FOR EC2 SSH"
                        echo "=========================================="

                        for i in $(seq 1 30); do

                            if ssh \
                                -i "$SSH_PRIVATE_KEY" \
                                -o StrictHostKeyChecking=no \
                                -o UserKnownHostsFile=/dev/null \
                                -o ConnectTimeout=5 \
                                -o ConnectionAttempts=1 \
                                "$SSH_USERNAME@$PUBLIC_IP" \
                                "echo SSH_READY" 2>/dev/null
                            then

                                echo "=========================================="
                                echo "SSH CONNECTION READY"
                                echo "=========================================="

                                exit 0
                            fi

                            echo "SSH not ready. Attempt $i/30"

                            sleep 10
                        done

                        echo "EC2 SSH did not become ready."

                        exit 1
                    '''
                }
            }
        }


        // ============================================================
        // DEPLOY APPLICATION WITH ANSIBLE
        // ============================================================

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
${env.PUBLIC_IP} ansible_user=${env.SSH_USERNAME} ansible_ssh_private_key_file=${env.SSH_PRIVATE_KEY} ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10'
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
                        echo "STARTING ANSIBLE DEPLOYMENT"
                        echo "=========================================="


                        sh '''
                            set -e

                            ansible-playbook \
                                -i ansible/jenkins-inventory.ini \
                                ansible/site.yml \
                                -e "@ansible/jenkins-vars.yml" \
                                -T 30 \
                                -vv

                            echo "=========================================="
                            echo "ANSIBLE DEPLOYMENT COMPLETED"
                            echo "=========================================="
                        '''
                    }
                }
            }
        }


        // ============================================================
        // VERIFY APPLICATION
        // ============================================================

        stage('Verify Public Application') {
            when {
                expression {
                    params.ACTION == 'deploy'
                }
            }

            steps {

                script {

                    def maxAttempts = 18
                    def attempt = 0
                    def success = false


                    while (attempt < maxAttempts) {

                        attempt++


                        echo "=========================================="
                        echo "Checking ${env.APPLICATION_URL}/health"
                        echo "Attempt ${attempt}/${maxAttempts}"
                        echo "=========================================="


                        def result = sh(
                            script: """
                                curl \
                                    --connect-timeout 5 \
                                    --max-time 10 \
                                    -fsS \
                                    "${env.APPLICATION_URL}/health" \
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


                        if (attempt < maxAttempts) {

                            echo "Application not ready."

                            sleep 10
                        }
                    }


                    if (!success) {

                        error(
                            "Application did not become reachable at ${env.APPLICATION_URL}/health"
                        )
                    }
                }
            }
        }


        // ============================================================
        // DESTROY
        // ============================================================

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

                        echo "=========================================="
                        echo "DESTROYING TERRAFORM INFRASTRUCTURE"
                        echo "=========================================="


                        terraform -chdir=infra destroy \
                            -auto-approve \
                            -input=false \
                            -no-color


                        echo "=========================================="
                        echo "TERRAFORM INFRASTRUCTURE DESTROYED"
                        echo "=========================================="
                    '''
                }
            }
        }
    }


    // ================================================================
    // POST ACTIONS
    // ================================================================

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
       TERRAFORM INFRASTRUCTURE DESTROYED
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

Check the failed stage above for the exact error.

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
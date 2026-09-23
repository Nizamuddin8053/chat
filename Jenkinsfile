pipeline {
    agent any

    parameters {
        choice(
            name: 'ACTION',
            choices: ['deploy', 'destroy'],
            description: 'Deploy the EC2 Compose stack or destroy all Terraform-managed resources.'
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

        stage('Validate') {
            when {
                expression { params.ACTION == 'deploy' }
            }
            steps {
                sh 'terraform -chdir=infra init -backend=false -input=false'
                sh 'terraform -chdir=infra fmt -check'
                sh 'terraform -chdir=infra validate'
            }
        }

        stage('Build and test') {
            when {
                expression { params.ACTION == 'deploy' }
            }
            steps {
                sh 'docker compose config -q'
                sh 'docker compose build'
            }
        }

        stage('AWS deployment') {
            steps {
                withCredentials([
                    [
                        $class: 'AmazonWebServicesCredentialsBinding',
                        credentialsId: 'chat-aws',
                        accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                        secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
                    ],
                    string(credentialsId: 'chat-mongodb-uri', variable: 'CHAT_MONGODB_URI'),
                    string(credentialsId: 'chat-jwt-secret', variable: 'CHAT_JWT_SECRET'),
                    sshUserPrivateKey(
                        credentialsId: 'chat-ec2-private-key',
                        keyFileVariable: 'SSH_PRIVATE_KEY'
                    )
                ]) {
                    sh '''
                        set -eu
                        if [ "$ACTION" = "deploy" ]; then
                            terraform -chdir=infra init -input=false
                            terraform -chdir=infra apply -auto-approve -input=false
                            PUBLIC_IP=$(terraform -chdir=infra output -raw public_ip)
                            printf '[chat]\\n%s ansible_user=ubuntu\\n' "$PUBLIC_IP" > inventory.ini
                            ansible-playbook ansible/site.yml -i inventory.ini \
                              --private-key "$SSH_PRIVATE_KEY" \
                              --extra-vars "required_frontend_origin=http://$PUBLIC_IP required_mongodb_uri=$CHAT_MONGODB_URI required_jwt_secret=$CHAT_JWT_SECRET" \
                              --ssh-extra-args '-o StrictHostKeyChecking=no'
                            rm -f inventory.ini
                        else
                            terraform -chdir=infra destroy -auto-approve
                        fi
                    '''
                }
            }
        }
    }

    post {
        success {
            echo 'Chat application pipeline completed successfully.'
        }
        failure {
            echo 'Chat application pipeline failed.'
        }
    }
}

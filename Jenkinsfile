pipeline {
    agent { label 'oracle-3' }

    environment {
        IMAGE_NAME = "sudarshanuprety/esewa"
        IMAGE_TAG  = "latest"
    }

    stages {
        stage('Checkout Code') {
            steps {
                checkout scm
            }
        }

        stage('Azure Login') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'AZURE_SP', usernameVariable: 'AZURE_CLIENT_ID', passwordVariable: 'AZURE_CLIENT_SECRET')]) {
                    sh """
                        az login --service-principal -u '$AZURE_CLIENT_ID' -p '$AZURE_CLIENT_SECRET' --tenant '$AZURE_TENANT_ID'
                        az account set --subscription '<SUBSCRIPTION_ID>'
                    """
                }
            }
        }

        stage('Terraform Init & Apply') {
            steps {
                sh """
                    cd terraform
                    terraform init
                    terraform plan -out=tfplan -var "docker_image=${IMAGE_NAME}:${IMAGE_TAG}"
                    terraform apply -auto-approve tfplan
                """
            }
        }

        stage('Verify Deployment') {
            steps {
                sh """
                    az aks get-credentials --resource-group esewa-resources --name esewa-cluster --overwrite-existing
                    kubectl get pods -n esewans
                    kubectl get svc -n esewans
                """
            }
        }
    }

    post {
        success { echo "Infrastructure & App deployed successfully ✅" }
        failure { echo "Deployment failed ❌" }
    }
}

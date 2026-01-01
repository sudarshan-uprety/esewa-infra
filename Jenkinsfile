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
                        az account set --subscription '$AZURE_SUBSCRIPTION_ID'
                    """
                }
            }
        }

        stage('Terraform Init & Apply') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'DOCKER',
                        usernameVariable: 'DOCKER_USERNAME',
                        passwordVariable: 'DOCKER_PASSWORD'
                    )
                ]) {
                    sh """
                        cd terraform
                        
                        # Export Terraform variables
                        export TF_VAR_docker_image="${IMAGE_NAME}:${IMAGE_TAG}"
                        export TF_VAR_dockerhub_username="${DOCKER_USERNAME}"
                        export TF_VAR_dockerhub_password="${DOCKER_PASSWORD}"
                        
                        terraform init

                        # --- Handle existing AKS cluster & node pool ---
                        terraform import azurerm_kubernetes_cluster.esewa /subscriptions/\$AZURE_SUBSCRIPTION_ID/resourceGroups/esewa-resources/providers/Microsoft.ContainerService/managedClusters/esewa-cluster || true
                        terraform import azurerm_kubernetes_cluster_node_pool.workernode /subscriptions/\$AZURE_SUBSCRIPTION_ID/resourceGroups/esewa-resources/providers/Microsoft.ContainerService/managedClusters/esewa-cluster/agentPools/workernode || true

                        # --- Fix Unexpected Identity Change for Kubernetes resources ---
                        # Remove resources from state if they already exist
                        terraform state rm 'kubernetes_deployment.esewa_app' || true
                        terraform state rm 'kubernetes_service.esewa_svc' || true
                        terraform state rm 'kubernetes_ingress_v1.esewa_ingress' || true

                        # Import them back with the correct identity
                        terraform import 'kubernetes_deployment.esewa_app' esewans/esewa-app || true
                        terraform import 'kubernetes_service.esewa_svc' esewans/esewa-service || true
                        terraform import 'kubernetes_ingress_v1.esewa_ingress' esewans/esewa-ingress || true

                        # Plan & apply with all variables
                        terraform plan -out=tfplan \\
                            -var "docker_image=\${IMAGE_NAME}:\${IMAGE_TAG}" \\
                            -var "dockerhub_username=\${DOCKER_USERNAME}" \\
                            -var "dockerhub_password=\${DOCKER_PASSWORD}"
                        
                        terraform apply -auto-approve tfplan
                    """
                }
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

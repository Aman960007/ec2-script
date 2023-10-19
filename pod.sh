#!/bin/bash

# Constants variables
CLUSTER_NAME='prod'
AWS_DEFAULT_REGION='us-east-1'
EKS_VERSION='1.26'
NODEGROUP_NAME='standard-workers'
NODE_TYPE='t3a.medium'
MIN_NODES='3'
MAX_NODES='3'
NODE_VOLUME_SIZE='30'
ZONES='us-east-1a,us-east-1b,us-east-1c'
APP_NAMESPACE='ecomm'
STORAGE_CLASS_NAME="io2"
VOLUME_SIZE="10Gi"
VOLUME_TYPE="io2"
IOPS="100"

# Your AWS access key ID and secret access key will be provided as command-line arguments
# ACCESS_KEY_ID="$1"
# SECRET_ACCESS_KEY="$2"

# Function to display an error message and exit the script with a non-zero status
function display_error_and_exit() {
    echo "Error: $1"
    exit 1
}

# Validate the number of arguments
# if [ $# -ne 2 ]; then
#     display_error_and_exit "Usage: $0 <aws_access_key_id> <aws_secret_access_key>"
# fi

# Function to check if a command is installed, and install it if not
function check_and_install_command() {
    local command_name="$1"
    local install_command="$2"

    if ! command -v "$command_name" &>/dev/null; then
        echo "$command_name not found. Installing $command_name..."
        eval "$install_command"
        if [ $? -ne 0 ]; then
            display_error_and_exit "Error: Unable to install $command_name. Please install it manually."
        fi
    else
        echo "$command_name is already installed."
    fi
}

# Check and install required packages
check_and_install_command "aws" "sudo apt update -y && sudo apt install -y awscli"
check_and_install_command "pip3" "sudo apt install -y python3-pip"
check_and_install_command "eksctl" 'curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | sudo tar xz -C /usr/local/bin'
check_and_install_command "kubectl" 'curl -o kubectl https://amazon-eks.s3.us-west-2.amazonaws.com/1.17.7/2020-07-08/bin/linux/amd64/kubectl && chmod +x kubectl && sudo mv kubectl /usr/local/bin'

# Update AWS credentials
echo "
[default]
aws_access_key_id = $ACCESS_KEY_ID
aws_secret_access_key = $SECRET_ACCESS_KEY
" > ~/.aws/credentials

echo "Credentials updated successfully."

# Function to create the EKS cluster
function create_eks_cluster() {
    # Check if the EKS cluster already exists
    if ! aws eks describe-cluster --region "$AWS_DEFAULT_REGION" --name "$CLUSTER_NAME" &>/dev/null; then
        # Create EKS cluster with the provided configurations
        eksctl create cluster \
            --region "$AWS_DEFAULT_REGION" \
            --name "$CLUSTER_NAME" \
            --version "$EKS_VERSION" \
            --nodegroup-name "$NODEGROUP_NAME" \
            --node-type "$NODE_TYPE" \
            --zones "$ZONES" \
            --nodes "$MAX_NODES" \
            --nodes-min "$MIN_NODES" \
            --nodes-max "$MAX_NODES" \
            --node-volume-size="$NODE_VOLUME_SIZE" \
            --managed
    else
        echo "EKS cluster $CLUSTER_NAME already exists. Skipping cluster creation."
    fi
}

# Function to create IAM service account and addons
function create_iam_service_account_and_addons() {
    # Get AWS account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

    # Get OIDC ID for the cluster
    OIDC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5)

    # Associate OIDC ID if not already associated
    if ! aws iam list-open-id-connect-providers | grep $OIDC_ID &>/dev/null; then
        eksctl utils associate-iam-oidc-provider --region "$AWS_DEFAULT_REGION" --cluster "$CLUSTER_NAME" --approve
    else
        echo "OIDC ID is already associated with the cluster."
    fi

    # Check if the IAM service account for EBS CSI controller exists
    # if ! eksctl get iamserviceaccount --name ebs-csi-controller-sa --namespace kube-system --cluster $CLUSTER_NAME &>/dev/null; then
        # Create IAM service account for EBS CSI controller
    eksctl create iamserviceaccount \
        --name ebs-csi-controller-sa \
        --namespace kube-system \
        --cluster $CLUSTER_NAME \
        --role-name AmazonEKS_EBS_CSI_DriverRole \
        --role-only \
        --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
        --approve
    # else
    #     echo "IAM service account 'ebs-csi-controller-sa' already exists. Skipping IAM service account creation."
    # fi

    # Check if the EBS addons exist
    if ! eksctl get addon --name aws-ebs-csi-driver --cluster $CLUSTER_NAME &>/dev/null; then
        # Create addons
        eksctl create addon --name aws-ebs-csi-driver --cluster $CLUSTER_NAME --service-account-role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/AmazonEKS_EBS_CSI_DriverRole --force
    else
        echo "Addons 'aws-ebs-csi-driver'  already exist. Skipping addon creation."
    fi

    # Check if the IAM service account for vpc cni controller exists
    # if ! eksctl get iamserviceaccount --name vpc-cni-sa --namespace kube-system --cluster $CLUSTER_NAME &>/dev/null; then
        # Create IAM service account for VPC CNI controller
    eksctl create iamserviceaccount \
        --name vpc-cni-sa \
        --namespace kube-system \
        --cluster $CLUSTER_NAME \
        --role-name AmazonEKSVPCCNIRole \
        --attach-policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy \
        --override-existing-serviceaccounts \
        --approve
    # else
    #     echo "IAM service account 'vpc-cni-sa' already exists. Skipping IAM service account creation."
    # fi

    # Check if the VPC CNI addons exist
    if ! eksctl get addon --name vpc-cni --cluster $CLUSTER_NAME &>/dev/null; then
        # Create addons
        # eksctl create addon --name vpc-cni --cluster $CLUSTER_NAME --addon-version v1.13.2-eksbuild.1 --service-account-role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/AmazonEKSVPCCNIRole --force
        eksctl create addon --name vpc-cni --cluster $CLUSTER_NAME --version latest --force
    else
        echo "Addons 'vpc-cni' already exist. Skipping addon creation."
    fi
}

# Check if EKS cluster exists and create if necessary
create_eks_cluster

# Update kubeconfig
echo "Updating kubeconfig..."
aws eks update-kubeconfig --region "$AWS_DEFAULT_REGION" --name "$CLUSTER_NAME"

# Create IAM service account and addons
create_iam_service_account_and_addons

# Check if the namespace exists
if ! kubectl get namespace $APP_NAMESPACE &>/dev/null; then
    kubectl create namespace $APP_NAMESPACE
else
    echo "Namespace $APP_NAMESPACE already exists. Skipping namespace creation."
fi

# Setup monitoring
# bash <(curl -s https://raw.githubusercontent.com/mohanraz81/hpdc/master/kubernetes/deploymonitoring.sh)
##############################
# Create StorageClass
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: $STORAGE_CLASS_NAME
provisioner: ebs.csi.aws.com
parameters:
  type: $VOLUME_TYPE
  iopsPerGB: "$IOPS"
  fsType: ext4
EOF
curl -sSL https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
helm repo add stable https://charts.helm.sh/stable
helm repo update
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
kubectl create namespace prometheus
helm install prometheus prometheus-community/prometheus \
    --namespace prometheus \
    --set alertmanager.enabled=false \
    --set server.persistentVolume.storageClass="io2" \
    --set server.persistentVolume.size="10Gi"
sleep 120

helm repo add grafana https://grafana.github.io/helm-charts
mkdir ${HOME}/environment/grafana

cat << EoF > ${HOME}/environment/grafana/grafana.yaml
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus-server.prometheus.svc.cluster.local
      access: proxy
      isDefault: true
EoF
kubectl create namespace grafana

helm install grafana grafana/grafana \
    --namespace grafana \
    --set persistence.storageClassName="io2" \
    --set persistence.enabled=true \
    --set adminPassword='EKS!sAWSome' \
    --values ${HOME}/environment/grafana/grafana.yaml \
    --set service.type=LoadBalancer
sleep 120
kubectl get all -n grafana
export ELB=$(kubectl get svc -n grafana grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "To Access Grafanna hit the below URL"
echo "http://$ELB"
grafanapassword=`kubectl get secret --namespace grafana grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo`
echo "To Login Username: admin   Password: $grafanapassword"
###########################

# Apply Kubernetes manifests
kubectl apply -f https://raw.githubusercontent.com/mohanraz81/hpdc/master/kubernetes/deployment.yaml -n $APP_NAMESPACE
kubectl apply -f https://raw.githubusercontent.com/mohanraz81/hpdc/master/kubernetes/services.yaml -n $APP_NAMESPACE

echo "Script execution completed successfully."

aws dynamodb create-table     --table-name producttable     --attribute-definitions AttributeName=id,AttributeType=S     --key-schema AttributeName=id,KeyType=HASH     --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5




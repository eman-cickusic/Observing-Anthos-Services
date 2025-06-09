#!/bin/bash

# Cloud Service Mesh Setup Script
# This script automates the setup of Cloud Service Mesh on GKE with the Online Boutique application

set -e

echo "🚀 Starting Cloud Service Mesh Setup..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required tools are installed
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed. Please install kubectl."
        exit 1
    fi
    
    print_status "Prerequisites check passed ✅"
}

# Set environment variables
setup_environment() {
    print_status "Setting up environment variables..."
    
    # Prompt for required variables if not set
    if [ -z "$PROJECT_ID" ]; then
        read -p "Enter your Google Cloud Project ID: " PROJECT_ID
    fi
    
    if [ -z "$CLUSTER_ZONE" ]; then
        read -p "Enter your cluster zone (e.g., us-central1-a): " CLUSTER_ZONE
    fi
    
    # Extract region from zone
    CLUSTER_REGION=$(echo $CLUSTER_ZONE | cut -d'-' -f1-2)
    
    # Set other variables
    export CLUSTER_NAME=gke
    export PROJECT_NUMBER=$(gcloud projects describe ${PROJECT_ID} --format="value(projectNumber)")
    export FLEET_PROJECT_ID="${PROJECT_ID}"
    export IDNS="${PROJECT_ID}.svc.id.goog"
    export DIR_PATH=.
    
    print_status "Environment variables configured:"
    printf "CLUSTER_NAME: $CLUSTER_NAME\n"
    printf "CLUSTER_ZONE: $CLUSTER_ZONE\n"
    printf "CLUSTER_REGION: $CLUSTER_REGION\n"
    printf "PROJECT_ID: $PROJECT_ID\n"
    printf "PROJECT_NUMBER: $PROJECT_NUMBER\n"
    printf "FLEET_PROJECT_ID: $FLEET_PROJECT_ID\n"
    printf "IDNS: $IDNS\n"
}

# Configure cluster access
configure_cluster_access() {
    print_status "Configuring cluster access..."
    
    gcloud container clusters get-credentials $CLUSTER_NAME \
        --zone $CLUSTER_ZONE --project $PROJECT_ID
    
    print_status "Cluster access configured ✅"
}

# Enable required APIs and services
enable_services() {
    print_status "Enabling required Google Cloud APIs..."
    
    gcloud services enable --project="${PROJECT_ID}" \
        anthos.googleapis.com \
        container.googleapis.com \
        compute.googleapis.com \
        monitoring.googleapis.com \
        logging.googleapis.com \
        cloudtrace.googleapis.com
    
    print_status "APIs enabled ✅"
}

# Register cluster to fleet
register_cluster() {
    print_status "Registering cluster to fleet..."
    
    gcloud container clusters update gke --enable-fleet --region "${CLUSTER_ZONE}"
    
    # Verify registration
    print_status "Verifying fleet registration..."
    gcloud container fleet memberships list --project "${PROJECT_ID}"
    
    print_status "Cluster registered to fleet ✅"
}

# Install Cloud Service Mesh
install_service_mesh() {
    print_status "Installing Cloud Service Mesh..."
    
    # Enable Cloud Service Mesh on fleet
    gcloud container fleet mesh enable --project "${PROJECT_ID}"
    
    # Enable automatic management
    gcloud container fleet mesh update \
        --management automatic \
        --memberships gke \
        --project "${PROJECT_ID}" \
        --location "$CLUSTER_REGION"
    
    print_status "Waiting for control plane to be ready..."
    print_warning "This may take several minutes..."
    
    # Wait for control plane to be ready
    while true; do
        STATUS=$(gcloud container fleet mesh describe --project "${PROJECT_ID}" --format="value(membershipStates.*.servicemesh.controlPlaneManagement.state)" 2>/dev/null || echo "")
        if [[ "$STATUS" == "ACTIVE" ]]; then
            print_status "Control plane is ready ✅"
            break
        fi
        echo "Waiting for control plane... Current status: $STATUS"
        sleep 30
    done
}

# Enable Cloud Trace integration
enable_tracing() {
    print_status "Enabling Cloud Trace integration..."
    
    cat <<EOF | kubectl apply -n istio-system -f -
apiVersion: telemetry.istio.io/v1alpha1
kind: Telemetry
metadata:
   name: enable-cloud-trace
   namespace: istio-system
spec:
   tracing:
   - providers:
     - name: stackdriver
EOF
    
    print_status "Cloud Trace integration enabled ✅"
}

# Configure mesh data plane
configure_data_plane() {
    print_status "Configuring mesh data plane..."
    
    # Enable Istio sidecar injection
    kubectl label namespace default istio.io/rev- istio-injection=enabled --overwrite
    
    # Enable managed data plane
    kubectl annotate --overwrite namespace default \
        mesh.cloud.google.com/proxy='{"managed":"true"}'
    
    print_status "Data plane configured ✅"
}

# Deploy Online Boutique application
deploy_application() {
    print_status "Deploying Online Boutique application..."
    
    # Deploy the application
    kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/master/release/kubernetes-manifests.yaml
    
    # Patch product catalog service for versioning
    kubectl patch deployments/productcatalogservice -p '{"spec":{"template":{"metadata":{"labels":{"version":"v1"}}}}}'
    
    print_status "Application deployed ✅"
}

# Configure ingress gateway
configure_ingress() {
    print_status "Configuring ingress gateway..."
    
    # Clone required packages
    if [ ! -d "anthos-service-mesh-packages" ]; then
        git clone https://github.com/GoogleCloudPlatform/anthos-service-mesh-packages
    fi
    
    # Install ingress gateway
    kubectl apply -f anthos-service-mesh-packages/samples/gateways/istio-ingressgateway
    
    # Install required CRDs
    kubectl apply -k "github.com/kubernetes-sigs/gateway-api/config/crd/experimental?ref=v0.6.0"
    kubectl kustomize "https://github.com/GoogleCloudPlatform/gke-networking-recipes.git/gateway-api/config/mesh/crd" | kubectl apply -f -
    
    # Configure gateway
    kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/master/release/istio-manifests.yaml
    
    print_status "Ingress gateway configured ✅"
}

# Wait for deployments to be ready
wait_for_deployments() {
    print_status "Waiting for deployments to be ready..."
    
    kubectl wait --for=condition=available --timeout=600s deployment --all
    
    print_status "All deployments are ready ✅"
}

# Get application URL
get_application_url() {
    print_status "Getting application URL..."
    
    # Wait for external IP
    print_warning "Waiting for external IP to be assigned..."
    while true; do
        EXTERNAL_IP=$(kubectl get svc frontend-external -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        if [[ -n "$EXTERNAL_IP" && "$EXTERNAL_IP" != "null" ]]; then
            print_status "Application is available at: http://$EXTERNAL_IP"
            break
        fi
        echo "Waiting for external IP..."
        sleep 10
    done
}

# Main execution
main() {
    print_status "Starting Cloud Service Mesh setup process..."
    
    check_prerequisites
    setup_environment
    configure_cluster_access
    enable_services
    register_cluster
    install_service_mesh
    enable_tracing
    configure_data_plane
    deploy_application
    configure_ingress
    wait_for_deployments
    get_application_url
    
    print_status "🎉 Setup completed successfully!"
    print_status "You can now:"
    print_status "1. Access the application using the URL above"
    print_status "2. View traces in Cloud Console > Trace"
    print_status "3. Monitor services in Cloud Console > Kubernetes Engine > Service Mesh"
    print_status "4. Create SLOs for your services"
}

# Run main function
main "$@"

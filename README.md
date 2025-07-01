# Observing Anthos Services

This repository contains the complete guide and configuration files for setting up Cloud Service Mesh on Google Kubernetes Engine (GKE) and observing microservices using Google Cloud's operations suite.

## Video

https://youtu.be/zJgNEpMGiNY

## Overview      
 
This project demonstrates how to:
- Install Cloud Service Mesh on GKE with tracing enabled
- Deploy a multi-service microservices application (Online Boutique)
- Configure service mesh observability features
- Create and monitor Service Level Objectives (SLOs)
- Diagnose and resolve service performance issues using Cloud Trace
- Visualize service mesh topology

## Architecture

The lab uses Google Cloud's Online Boutique application, a cloud-native microservices demo consisting of 10 interconnected services that simulate an e-commerce platform.

## Prerequisites

- Google Cloud Platform account with billing enabled
- Access to Google Cloud Console
- Basic familiarity with Kubernetes and Istio concepts

## Setup Instructions

### 1. Environment Setup

Set up your environment variables in Cloud Shell:

```bash
# Set cluster configuration
CLUSTER_NAME=gke
CLUSTER_ZONE="your-zone"
CLUSTER_REGION="your-region"
PROJECT_ID="your-project-id"
PROJECT_NUMBER=$(gcloud projects describe ${PROJECT_ID} --format="value(projectNumber)")
FLEET_PROJECT_ID="${PROJECT_ID}"
IDNS="${PROJECT_ID}.svc.id.goog"
DIR_PATH=.
```

Verify your configuration:
```bash
printf '\nCLUSTER_NAME:'$CLUSTER_NAME'\nCLUSTER_ZONE:'$CLUSTER_ZONE'\nPROJECT_ID:'$PROJECT_ID'\nPROJECT_NUMBER:'$PROJECT_NUMBER'\nFLEET PROJECT_ID:'$FLEET_PROJECT_ID'\nIDNS:'$IDNS'\nDIR_PATH:'$DIR_PATH'\n'
```

### 2. Configure Cluster Access

```bash
# Configure kubectl
gcloud container clusters get-credentials $CLUSTER_NAME \
    --zone $CLUSTER_ZONE --project $PROJECT_ID

# Verify cluster is running
gcloud container clusters list
```

### 3. Enable GKE Enterprise and Fleet

```bash
# Enable Anthos API
gcloud services enable --project="${PROJECT_ID}" anthos.googleapis.com

# Register cluster to Fleet
gcloud container clusters update gke --enable-fleet --region "${CLUSTER_ZONE}"

# Verify registration
gcloud container fleet memberships list --project "${PROJECT_ID}"
```

### 4. Install Cloud Service Mesh

```bash
# Enable Cloud Service Mesh on fleet
gcloud container fleet mesh enable --project "${PROJECT_ID}"

# Enable automatic management
gcloud container fleet mesh update \
  --management automatic \
  --memberships gke \
  --project "${PROJECT_ID}" \
  --location "$CLUSTER_REGION"

# Verify installation (wait for REVISION_READY state)
gcloud container fleet mesh describe --project "${PROJECT_ID}"
```

### 5. Enable Cloud Trace Integration

Apply the telemetry configuration:

```bash
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
```

### 6. Deploy the Online Boutique Application

```bash
# Enable Istio sidecar injection
kubectl label namespace default istio.io/rev- istio-injection=enabled --overwrite

# Enable managed data plane
kubectl annotate --overwrite namespace default \
  mesh.cloud.google.com/proxy='{"managed":"true"}'

# Deploy the application
kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/master/release/kubernetes-manifests.yaml
kubectl patch deployments/productcatalogservice -p '{"spec":{"template":{"metadata":{"labels":{"version":"v1"}}}}}'
```

### 7. Configure Ingress Gateway

```bash
# Clone required packages
git clone https://github.com/GoogleCloudPlatform/anthos-service-mesh-packages

# Install ingress gateway
kubectl apply -f anthos-service-mesh-packages/samples/gateways/istio-ingressgateway

# Install CRDs
kubectl apply -k "github.com/kubernetes-sigs/gateway-api/config/crd/experimental?ref=v0.6.0"
kubectl kustomize "https://github.com/GoogleCloudPlatform/gke-networking-recipes.git/gateway-api/config/mesh/crd" | kubectl apply -f -

# Configure gateway
kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/master/release/istio-manifests.yaml
```

### 8. Access the Application

Find the external IP address:
```bash
kubectl get services
```

Look for the `frontend-external` service's EXTERNAL-IP and access the application in your browser.

## Observability Features

### Cloud Trace
- Navigate to **Cloud Console > Trace** to view request traces
- Analyze request latency and service dependencies
- Identify performance bottlenecks across services

### Service Level Objectives (SLOs)
1. Go to **Kubernetes Engine > Service Mesh**
2. Select a service (e.g., productcatalogservice)
3. Click **Health > +CreateSLO**
4. Configure latency-based SLO with 99.5% goal

### Service Mesh Dashboard
- Visualize service topology
- Monitor service performance metrics
- Track SLO compliance and error budgets

## Testing Canary Deployments

To demonstrate troubleshooting capabilities, deploy a high-latency canary version:

```bash
# Clone samples repository
git clone https://github.com/GoogleCloudPlatform/istio-samples.git ~/istio-samples

# Deploy canary with high latency
kubectl apply -f ~/istio-samples/istio-canary-gke/canary/destinationrule.yaml
kubectl apply -f ~/istio-samples/istio-canary-gke/canary/productcatalog-v2.yaml
kubectl apply -f ~/istio-samples/istio-canary-gke/canary/vs-split-traffic.yaml
```

This splits traffic 75% to v1 and 25% to v2 (high latency version).

### Rollback Procedure

```bash
# Remove canary deployment
kubectl delete -f ~/istio-samples/istio-canary-gke/canary/destinationrule.yaml
kubectl delete -f ~/istio-samples/istio-canary-gke/canary/productcatalog-v2.yaml
kubectl delete -f ~/istio-samples/istio-canary-gke/canary/vs-split-traffic.yaml
```

## Key Learning Outcomes

- **Service Mesh Installation**: Successfully installed and configured Cloud Service Mesh on GKE
- **Microservices Deployment**: Deployed a complex microservices application with service mesh integration
- **Observability**: Implemented comprehensive monitoring using Cloud Trace, Service Mesh Dashboard, and SLOs
- **Troubleshooting**: Diagnosed performance issues using distributed tracing and metrics
- **Traffic Management**: Implemented canary deployments and traffic splitting for safe releases

## Monitoring and Alerting

The project demonstrates several observability features:

- **Automatic Telemetry**: Service-to-service communication is automatically instrumented
- **Distributed Tracing**: Request flows across services are tracked in Cloud Trace
- **Service Metrics**: Latency, error rates, and throughput metrics are collected
- **SLO Monitoring**: Service-level objectives track service health and error budgets
- **Visual Topology**: Service dependencies and relationships are visualized

## Best Practices Implemented

1. **Managed Control Plane**: Using Google-managed Istio control plane for automatic updates
2. **Automatic Sidecar Injection**: Configured namespace-level sidecar injection
3. **Managed Data Plane**: Enabled automatic sidecar proxy updates
4. **Distributed Tracing**: Integrated with Cloud Trace for request tracking
5. **SLO Definition**: Established measurable service quality objectives

## Troubleshooting Common Issues

- **Control Plane Status**: Verify control plane is in REVISION_READY state
- **Sidecar Injection**: Ensure namespaces are properly labeled and annotated
- **Service Discovery**: Check that services are properly registered in the mesh
- **Trace Data**: Allow 5-10 minutes for trace data to appear in Cloud Trace
- **Topology View**: Service topology may take 10+ minutes to fully populate

## Cleanup

To clean up resources after the lab:

```bash
# Delete the GKE cluster
gcloud container clusters delete gke --zone $CLUSTER_ZONE

# Disable APIs if no longer needed
gcloud services disable anthos.googleapis.com
```

## Additional Resources

- [Cloud Service Mesh Documentation](https://cloud.google.com/service-mesh/docs)
- [Istio Documentation](https://istio.io/docs/)
- [Online Boutique GitHub Repository](https://github.com/GoogleCloudPlatform/microservices-demo)
- [Cloud Trace Documentation](https://cloud.google.com/trace/docs)

## Contributing

Feel free to submit issues or pull requests to improve this guide.

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

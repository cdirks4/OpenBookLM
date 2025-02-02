#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get the directory of the script and move to project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
cd "$PROJECT_ROOT"

# Parse command line arguments
BUILD_DOCKER=false
HELP=false

print_usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -b, --build     Build and push Docker image before deployment"
    echo "  -h, --help      Show this help message"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--build)
            BUILD_DOCKER=true
            shift
            ;;
        -h|--help)
            HELP=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

if [ "$HELP" = true ]; then
    print_usage
    exit 0
fi

echo -e "${GREEN}Deploying to Kubernetes...${NC}\n"

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${YELLOW}Error: kubectl is not installed. Please install it first:${NC}"
    echo "brew install kubectl"
    exit 1
fi

# Check if we have access to the cluster
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to Kubernetes cluster. Please check your kubeconfig.${NC}"
    exit 1
fi

# Build and push Docker image if flag is set
if [ "$BUILD_DOCKER" = true ]; then
    echo -e "${GREEN}Building and pushing Docker image...${NC}"
    
    # Build the Docker image
    docker build -t ghcr.io/open-biz/openbooklm:latest .
    
    # Push to GitHub Container Registry
    echo -e "${GREEN}Pushing to GitHub Container Registry...${NC}"
    docker push ghcr.io/open-biz/openbooklm:latest
else
    echo -e "${YELLOW}Skipping Docker build step. Using existing image.${NC}"
fi

# Call the validation function before deployment
validate_environment

# Deploy to Kubernetes
echo -e "${GREEN}Deploying to Kubernetes...${NC}"

# Create namespace if it doesn't exist
kubectl create namespace openbooklm --dry-run=client -o yaml | kubectl apply -f -

# Apply Kubernetes configurations
kubectl apply -f k8s/ -n openbooklm

# Wait for deployment with increased timeout
echo -e "${GREEN}Waiting for deployment to be ready...${NC}"
if ! kubectl wait --for=condition=available --timeout=600s deployment/openbooklm -n openbooklm; then
  echo -e "${RED}Deployment failed to become ready. Checking logs...${NC}"
  
  # Get the pod name
  POD_NAME=$(kubectl get pods -n openbooklm -l app=openbooklm -o jsonpath='{.items[0].metadata.name}')
  
  if [ ! -z "$POD_NAME" ]; then
    echo -e "${YELLOW}Pod logs:${NC}"
    kubectl logs -n openbooklm $POD_NAME
    
    echo -e "${YELLOW}Pod description:${NC}"
    kubectl describe pod -n openbooklm $POD_NAME
  fi
  
  exit 1
fi

# Get the deployment status
echo -e "${GREEN}Deployment Status:${NC}"
kubectl get deployments -n openbooklm
kubectl get pods -n openbooklm

echo "Setting up other secrets..."
if [ -f "$PROJECT_ROOT/.env" ]; then
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ $key =~ ^#.*$ ]] || [ -z "$key" ] && continue
        
        # Clean up key and value
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs | sed -e 's/^["\x27]//' -e 's/["\x27]$//')
        
        echo "Setting $key..."
        kubectl create secret generic openbooklm --from-literal="$key=$value" -n openbooklm
    done < "$PROJECT_ROOT/.env"
fi

# Verify database connection and run migrations
echo "Running database migrations..."
if ! npx prisma migrate deploy; then
    echo -e "${RED}Error: Database migration failed${NC}"
    exit 1
fi

echo -e "${GREEN}Deployment complete!${NC}"
echo -e "To view your deployment:"
echo -e "${YELLOW}kubectl get pods -n openbooklm${NC}"
echo -e "To view logs:"
echo -e "${YELLOW}kubectl logs -f deployment/openbooklm -n openbooklm${NC}"

# Add this near the start of the script
validate_environment() {
  local required_vars=(
    "NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY"
    "CLERK_SECRET_KEY"
    "DATABASE_URL"
    "REDIS_URL"
  )

  local missing_vars=()
  for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
      missing_vars+=("$var")
    fi
  done

  if [ ${#missing_vars[@]} -ne 0 ]; then
    echo -e "${RED}Error: Missing required environment variables:${NC}"
    printf '%s\n' "${missing_vars[@]}"
    exit 1
  fi
}

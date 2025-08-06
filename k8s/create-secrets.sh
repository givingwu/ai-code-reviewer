#!/bin/bash

# AI Code Reviewer - Secret Creation Helper Script
# This script helps create and manage Kubernetes secrets for the AI Code Reviewer application

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="test"
SECRET_NAME="ai-code-reviewer-secrets"

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to encode string to base64
encode_base64() {
    echo -n "$1" | base64 | tr -d '\n'
}

# Function to create secret interactively
create_secret_interactive() {
    log_info "Creating secrets interactively..."
    
    # GitLab Configuration
    echo -n "Enter GitLab Private Token: "
    read -s GITLAB_TOKEN
    echo
    
    echo -n "Enter GitLab Webhook Secret (optional): "
    read -s GITLAB_WEBHOOK_SECRET
    echo
    
    # Dify Configuration
    echo -n "Enter Dify API Token: "
    read -s DIFY_TOKEN
    echo
    
    echo -n "Enter Dify API URL: "
    read DIFY_API_URL
    
    # TV Bot Configuration
    echo -n "Enter TV Bot ID: "
    read TV_BOT_ID
    
    echo -n "Enter TV Bot Token: "
    read -s TV_BOT_TOKEN
    echo
    
    echo -n "Enter TV Bot Webhook URL: "
    read TV_BOT_WEBHOOK_URL
    
    # Generate JWT Secret if not provided
    JWT_SECRET=$(openssl rand -base64 32)
    ENCRYPTION_KEY=$(openssl rand -base64 32)
    
    log_info "Generated JWT Secret and Encryption Key"
    
    # Create the secret
    kubectl create secret generic $SECRET_NAME \
        --namespace=$NAMESPACE \
        --from-literal=gitlab-token="$GITLAB_TOKEN" \
        --from-literal=gitlab-webhook-secret="$GITLAB_WEBHOOK_SECRET" \
        --from-literal=dify-token="$DIFY_TOKEN" \
        --from-literal=dify-api-url="$DIFY_API_URL" \
        --from-literal=tv-bot-id="$TV_BOT_ID" \
        --from-literal=tv-bot-token="$TV_BOT_TOKEN" \
        --from-literal=tv-bot-webhook-url="$TV_BOT_WEBHOOK_URL" \
        --from-literal=jwt-secret="$JWT_SECRET" \
        --from-literal=encryption-key="$ENCRYPTION_KEY" \
        --dry-run=client -o yaml > secret-generated.yaml
    
    log_success "Secret YAML generated in secret-generated.yaml"
    log_info "Review the file and apply with: kubectl apply -f secret-generated.yaml"
}

# Function to create secret from environment variables
create_secret_from_env() {
    log_info "Creating secrets from environment variables..."
    
    # Check required environment variables
    required_vars=("GITLAB_TOKEN" "DIFY_TOKEN" "TV_BOT_ID" "TV_BOT_TOKEN")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            log_error "Required environment variable $var is not set"
            exit 1
        fi
    done
    
    # Set defaults for optional variables
    GITLAB_WEBHOOK_SECRET=${GITLAB_WEBHOOK_SECRET:-""}
    DIFY_API_URL=${DIFY_API_URL:-"https://api.dify.ai/v1"}
    TV_BOT_WEBHOOK_URL=${TV_BOT_WEBHOOK_URL:-""}
    JWT_SECRET=${JWT_SECRET:-$(openssl rand -base64 32)}
    ENCRYPTION_KEY=${ENCRYPTION_KEY:-$(openssl rand -base64 32)}
    
    # Create the secret
    kubectl create secret generic $SECRET_NAME \
        --namespace=$NAMESPACE \
        --from-literal=gitlab-token="$GITLAB_TOKEN" \
        --from-literal=gitlab-webhook-secret="$GITLAB_WEBHOOK_SECRET" \
        --from-literal=dify-token="$DIFY_TOKEN" \
        --from-literal=dify-api-url="$DIFY_API_URL" \
        --from-literal=tv-bot-id="$TV_BOT_ID" \
        --from-literal=tv-bot-token="$TV_BOT_TOKEN" \
        --from-literal=tv-bot-webhook-url="$TV_BOT_WEBHOOK_URL" \
        --from-literal=jwt-secret="$JWT_SECRET" \
        --from-literal=encryption-key="$ENCRYPTION_KEY" \
        --dry-run=client -o yaml
    
    log_success "Secret created successfully"
}

# Function to update existing secret
update_secret() {
    log_info "Updating existing secret..."
    
    if ! kubectl get secret $SECRET_NAME -n $NAMESPACE >/dev/null 2>&1; then
        log_error "Secret $SECRET_NAME does not exist in namespace $NAMESPACE"
        exit 1
    fi
    
    echo -n "Enter key to update: "
    read KEY
    
    echo -n "Enter new value: "
    read -s VALUE
    echo
    
    kubectl patch secret $SECRET_NAME -n $NAMESPACE \
        --type='json' \
        -p="[{\"op\": \"replace\", \"path\": \"/data/$KEY\", \"value\":\"$(encode_base64 "$VALUE")\"}]"
    
    log_success "Secret key $KEY updated successfully"
}

# Function to view secret (base64 decoded)
view_secret() {
    log_info "Viewing secret contents..."
    
    if ! kubectl get secret $SECRET_NAME -n $NAMESPACE >/dev/null 2>&1; then
        log_error "Secret $SECRET_NAME does not exist in namespace $NAMESPACE"
        exit 1
    fi
    
    echo "Secret keys:"
    kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data}' | jq -r 'keys[]'
    
    echo -n "Enter key to view (or 'all' for all keys): "
    read KEY
    
    if [[ "$KEY" == "all" ]]; then
        kubectl get secret $SECRET_NAME -n $NAMESPACE -o json | jq -r '.data | to_entries[] | "\(.key): \(.value | @base64d)"'
    else
        VALUE=$(kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath="{.data.$KEY}" | base64 -d)
        echo "$KEY: $VALUE"
    fi
}

# Function to delete secret
delete_secret() {
    log_warning "This will delete the secret $SECRET_NAME in namespace $NAMESPACE"
    echo -n "Are you sure? (y/N): "
    read CONFIRM
    
    if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then
        kubectl delete secret $SECRET_NAME -n $NAMESPACE
        log_success "Secret deleted successfully"
    else
        log_info "Operation cancelled"
    fi
}

# Main menu
show_menu() {
    echo
    echo "AI Code Reviewer - Secret Management"
    echo "===================================="
    echo "1. Create secret interactively"
    echo "2. Create secret from environment variables"
    echo "3. Update existing secret"
    echo "4. View secret contents"
    echo "5. Delete secret"
    echo "6. Exit"
    echo
}

# Main script
main() {
    if [[ $# -eq 0 ]]; then
        while true; do
            show_menu
            echo -n "Choose an option (1-6): "
            read OPTION
            
            case $OPTION in
                1) create_secret_interactive ;;
                2) create_secret_from_env ;;
                3) update_secret ;;
                4) view_secret ;;
                5) delete_secret ;;
                6) log_info "Goodbye!"; exit 0 ;;
                *) log_error "Invalid option. Please choose 1-6." ;;
            esac
            
            echo
            echo -n "Press Enter to continue..."
            read
        done
    else
        case $1 in
            "create") create_secret_interactive ;;
            "create-env") create_secret_from_env ;;
            "update") update_secret ;;
            "view") view_secret ;;
            "delete") delete_secret ;;
            *) 
                echo "Usage: $0 [create|create-env|update|view|delete]"
                echo "Run without arguments for interactive menu"
                exit 1
                ;;
        esac
    fi
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
    log_error "jq is not installed or not in PATH"
    exit 1
fi

# Run main function
main "$@"
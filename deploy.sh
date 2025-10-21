#!/bin/bash

# Color codes for pretty output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color


# Log file with timestamp
LOG_FILE="deploy_$(date +%Y%m%d_%H%M%S).log"


# FUNCTION: Log messages to both console and file

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}



# FUNCTION: Error handling - exit on failure
error_exit() {
    log_error "$1"
    exit 1
}

# Trap errors and cleanup
trap 'error_exit "Script failed at line $LINENO"' ERR

# FUNCTION: Cleanup all deployed resources

cleanup_deployment() {
    log_info "=== CLEANUP MODE ACTIVATED ==="
    
    if [[ -z "$SERVER_IP" ]] || [[ -z "$SSH_USER" ]] || [[ -z "$SSH_KEY" ]]; then
        log_error "Missing server connection details for cleanup"
        read -p "Enter remote server IP: " SERVER_IP
        read -p "Enter remote server username: " SSH_USER
        read -p "Enter SSH key path: " SSH_KEY
        SSH_KEY="${SSH_KEY/#\~/$HOME}"
    fi
    
    if [[ -z "$REPO_NAME" ]]; then
        read -p "Enter repository/application name to cleanup: " REPO_NAME
    fi
    
    log_info "Cleaning up deployment: $REPO_NAME on $SERVER_IP"
    
    ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" bash <<CLEANUP_SCRIPT
        set -e
        
        echo "Stopping and removing containers..."
        docker stop $REPO_NAME 2>/dev/null || true
        docker rm $REPO_NAME 2>/dev/null || true
        
        # Stop docker-compose services if they exist
        if [[ -d ~/deployments/$REPO_NAME ]] && [[ -f ~/deployments/$REPO_NAME/docker-compose.yml ]]; then
            cd ~/deployments/$REPO_NAME
            docker-compose down -v 2>/dev/null || true
        fi
        
        echo "Removing Docker images..."
        docker rmi $REPO_NAME:latest 2>/dev/null || true
        docker image prune -f
        
        echo "Removing deployment files..."
        rm -rf ~/deployments/$REPO_NAME
        
        echo "Removing Nginx configuration..."
        sudo rm -f /etc/nginx/sites-available/$REPO_NAME
        sudo rm -f /etc/nginx/sites-enabled/$REPO_NAME
        
        # Restore default Nginx config if needed
        if [[ ! -f /etc/nginx/sites-enabled/default ]]; then
            sudo ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default 2>/dev/null || true
        fi
        
        echo "Reloading Nginx..."
        sudo nginx -t && sudo systemctl reload nginx
        
        echo "Cleaning up unused Docker resources..."
        docker system prune -f
        
        echo "Cleanup completed!"
CLEANUP_SCRIPT
    
    log_info "Cleanup completed successfully ✅"
    
    # Clean local clone
    if [[ -d "$REPO_NAME" ]]; then
        log_info "Removing local repository clone..."
        cd ..
        rm -rf "$REPO_NAME"
    fi
    
    exit 0
}

# CLEANUP FLAG

if [[ "$1" == "--cleanup" ]]; then
    cleanup_deployment
fi


# STEP 1: COLLECT USER INPUTS

log " Starting Deployment Script"
log "Step 1: Collecting deployment parameters..."

# Git Repository URL
read -p "Enter Git Repository URL: " GIT_REPO
[[ -z "$GIT_REPO" ]] && error_exit "Git repository URL cannot be empty"

# Personal Access Token
read -sp "Enter Personal Access Token (PAT): " GIT_TOKEN
echo ""
[[ -z "$GIT_TOKEN" ]] && error_exit "Personal Access Token cannot be empty"

# Branch Name
read -p "Enter branch name (default: main): " BRANCH
BRANCH=${BRANCH:-main}

# SSH Details
read -p "Enter remote server username: " SSH_USER
[[ -z "$SSH_USER" ]] && error_exit "SSH username cannot be empty"

read -p "Enter remote server IP address: " SERVER_IP
[[ -z "$SERVER_IP" ]] && error_exit "Server IP cannot be empty"

read -p "Enter SSH key path (default: ~/.ssh/id_rsa): " SSH_KEY
SSH_KEY=${SSH_KEY:-~/.ssh/id_rsa}
[[ ! -f "$SSH_KEY" ]] && error_exit "SSH key not found at $SSH_KEY"

# Application port
read -p "Enter application port (e.g., 3000): " APP_PORT
[[ -z "$APP_PORT" ]] && error_exit "Application port cannot be empty"

# Extract repo name from URL
REPO_NAME=$(basename "$GIT_REPO" .git)
log "Repository name: $REPO_NAME"


# STEP 2: CLONE/UPDATE REPOSITORY

log "Step 2: Cloning repository..."

# Create authenticated URL
AUTH_URL=$(echo "$GIT_REPO" | sed "s|https://|https://$GIT_TOKEN@|")

if [[ -d "$REPO_NAME" ]]; then
    log_warning "Removing existing repository directory..."
    rm -rf "$REPO_NAME"
fi

# Clone the repository
log "Cloning repository from $GIT_REPO (branch: $BRANCH)..."
git clone -b "$BRANCH" "$AUTH_URL" >> "$LOG_FILE" 2>&1 || error_exit "Failed to clone repository. Check the URL and your access token."

cd "$REPO_NAME" || error_exit "Failed to navigate to $REPO_NAME"

log "Repository cloned successfully 👍"


# Check if docker exists

log "Step 3: Verifying Docker configuration files..."

if [[ -f "Dockerfile" ]]; then
    log "Found Dockerfile ✅"
    DEPLOY_TYPE="dockerfile"
elif [[ -f "docker-compose.yml" ]] || [[ -f "docker-compose.yaml" ]]; then
    log "Found docker-compose.yml ✅"
    DEPLOY_TYPE="compose"
else
    error_exit "No Dockerfile or docker-compose.yml found!"
fi

#  absolute path of project
PROJECT_PATH=$(pwd)
log "Project path: $PROJECT_PATH"


# STEP 4: TEST SSH CONNECTION

log "Step 4: Testing SSH connection to remote server..."

ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
    "$SSH_USER@$SERVER_IP" "echo 'SSH connection successful '" >> "$LOG_FILE" 2>&1 \
    || error_exit "Failed to connect to remote server"

log "SSH connection successful 👍 "


# STEP 5:  REMOTE ENVIRONMENT

log "Step 5: Preparing remote server environment..."

ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" bash <<'REMOTE_SETUP'
    set -e

    echo "Updating system packages..."
    sudo apt-get update -y
    echo "Installing Docker..."
    if ! command -v docker &> /dev/null; then
        sudo apt-get install -y docker.io
        sudo systemctl start docker
        sudo systemctl enable docker
    fi

    echo "Installing Docker Compose..."
    if ! command -v docker-compose &> /dev/null; then
        sudo apt-get install -y docker-compose
    fi

    echo "Installing Nginx..."
    if ! command -v nginx &> /dev/null; then
        sudo apt-get install -y nginx
        sudo systemctl start nginx
        sudo systemctl enable nginx
    fi

    echo "Adding user to docker group..."
    sudo usermod -aG docker $USER || true

    echo "Verifying installations..."
    docker --version
    docker-compose --version
    nginx -v

    echo "Remote environment ready!"
REMOTE_SETUP

log "Remote environment prepared successfully 👍"


# STEP 6: TRANSFER PROJECT FILES

log "Step 6: Transferring project files to remote server..."

# Create remote directory
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" "mkdir -p ~/deployments/$REPO_NAME"

# Transfer files using rsync
rsync -avz -e "ssh -i $SSH_KEY" \
    --exclude '.git' \
    "$PROJECT_PATH/" \
    "$SSH_USER@$SERVER_IP:~/deployments/$REPO_NAME/" \
    >> "$LOG_FILE" 2>&1 || error_exit "Failed to transfer files"

log "Files transferred successfully ✅"

# DEPLOY APPLICATION

log "Deploying Dockerized application..."

if [[ "$DEPLOY_TYPE" == "compose" ]]; then
    # Deploy with docker-compose
    ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" bash <<REMOTE_DEPLOY
        set -e
        cd ~/deployments/$REPO_NAME

        echo "Stopping existing containers..."
        docker-compose down || true

        echo "Removing old images..."
        docker-compose down --rmi local 2>/dev/null || true

        echo "Building and starting containers..."
        docker-compose up -d --build

        echo "Waiting for containers to be healthy..."
        sleep 10

        echo "Container status:"
        docker-compose ps

        echo "Cleaning up unused resources..."
        docker image prune -f
REMOTE_DEPLOY
else
    # Deploy with Dockerfile
    ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" bash <<REMOTE_DEPLOY
        set -e
        cd ~/deployments/$REPO_NAME

        echo "Stopping existing container..."
        docker stop $REPO_NAME 2>/dev/null || true
        docker rm $REPO_NAME 2>/dev/null || true

        echo "Removing old image..."
        docker rmi $REPO_NAME:latest 2>/dev/null || true

        echo "Building Docker image..."
        docker build -t $REPO_NAME:latest .

        echo "Running container..."
        docker run -d --name $REPO_NAME -p $APP_PORT:$APP_PORT $REPO_NAME:latest

        echo "Waiting for container to start..."
        sleep 10

        echo "Container status:"
        docker ps -f name=$REPO_NAME

        echo "Cleaning up unused resources..."
        docker image prune -f
REMOTE_DEPLOY
fi

log "Application deployed successfully ✅"


# STEP 8: CONFIGURE NGINX REVERSE PROXY

log "Step 8: Configuring Nginx reverse proxy..."

ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" bash <<NGINX_CONFIG
    set -e

    echo "Creating Nginx configuration..."
    sudo tee /etc/nginx/sites-available/$REPO_NAME > /dev/null <<'EOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    echo "Enabling site..."
    sudo ln -sf /etc/nginx/sites-available/$REPO_NAME /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default

    echo "Testing Nginx configuration..."
    sudo nginx -t

    echo "Reloading Nginx..."
    sudo systemctl reload nginx

    echo "Nginx configured successfully!"
NGINX_CONFIG

log "Nginx reverse proxy configured successfully ✅"


# STEP 9: VALIDATE DEPLOYMENT

log "Step 9: Validating deployment..."

# Check Docker service
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" "systemctl is-active docker" >> "$LOG_FILE" 2>&1 \
    || error_exit "Docker service is not running"

# Check container health
if [[ "$DEPLOY_TYPE" == "compose" ]]; then
    ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" \
        "cd ~/deployments/$REPO_NAME && docker-compose ps | grep -i 'up'" \
        >> "$LOG_FILE" 2>&1 || log_warning "Some containers may not be running"
else
    ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" \
        "docker ps | grep $REPO_NAME" >> "$LOG_FILE" 2>&1 \
        || error_exit "Container is not running"
fi

# Check Nginx
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" "systemctl is-active nginx" >> "$LOG_FILE" 2>&1 \
    || error_exit "Nginx is not running"

# Test endpoint from remote server
log "Testing application endpoint..."
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" \
    "curl -f http://localhost:$APP_PORT || curl -f http://localhost" \
    >> "$LOG_FILE" 2>&1 || log_warning "Could not verify application response"

log "Deployment validation complete 👍"


# STEP 10: SUMMARY

log "DEPLOYMENT SUCCESSFUL ✅"
log "Application: $REPO_NAME"
log "Server: $SERVER_IP"
log "Access your application at: http://$SERVER_IP"
log "Check logs at: $LOG_FILE"
log ""
log "To check application status:"
log "  ssh -i $SSH_KEY $SSH_USER@$SERVER_IP 'docker ps'"
log ""
log "To view application logs:"
if [[ "$DEPLOY_TYPE" == "compose" ]]; then
    log "  ssh -i $SSH_KEY $SSH_USER@$SERVER_IP 'cd ~/deployments/$REPO_NAME && docker-compose logs'"
else
    log "  ssh -i $SSH_KEY $SSH_USER@$SERVER_IP 'docker logs $REPO_NAME'"
fi
log ""
log "To cleanup this deployment, run:"
log "  ./deploy.sh --cleanup"
exit 0

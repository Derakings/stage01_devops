# DevOps Stage 1 - Automated Deployment Script

## 🎯 Project Overview

This project automates the deployment of a Dockerized Node.js application to a remote Linux server using a Bash script.

##  Repositories

1. **Deployment Script (This Repo):** https://github.com/Derakings/stage01_devops.git
2. **Dockerized Application:** https://github.com/Derakings/my_docker_app.git

##  Live Deployment

- **Application URL:** http://YOUR_SERVER_IP (after deployment)


##  Features Implemented

- [x] Interactive parameter collection with validation
- [x] Git repository cloning with PAT authentication
- [x] SSH connection to remote server
- [x] Automated environment setup (Docker, Docker Compose, Nginx)
- [x] Dockerized application deployment
- [x] Nginx reverse proxy configuration
- [x] Comprehensive logging (timestamped log files)
- [x] Error handling with trap functions
- [x] Deployment validation
- [x] Idempotent execution (safe to re-run)

##  Technologies Used

- **Scripting:** Bash
- **Containerization:** Docker, Docker Compose
- **Web Server:** Nginx (reverse proxy)
- **Application:** Node.js + Express
- **Version Control:** Git + GitHub
- **Remote Access:** SSH

##  Usage

### Prerequisites

- Linux/Mac terminal (or Windows WSL)
- Git installed
- SSH client
- Remote Linux server with SSH access
- GitHub Personal Access Token

### Deployment Steps

1. **Clone this repository:**
```bash
git clone https://github.com/Derakings/stage01_devops.git

```

2. **Make script executable:**
```bash
chmod +x deploy.sh
```

3. **Run deployment:**
```bash
./deploy.sh
```

4. **Provide required information when prompted:**
   - Git Repository URL: `https://github.com/Derakings/my_docker_app.git
   - Personal Access Token: `ghp_xxxxxxxxxxxxx`
   - Branch:
   - Server username: e.g. `ubuntu`
   - Server IP: `YOUR_SERVER_IP`
   - SSH key path: e.g. `~/.ssh/your-key.pem`
   - Application port: `3000`

##  What the Script Does

```
Step 1: Collect deployment parameters from user
Step 2: Clone/update Git repository locally
Step 3: Verify Dockerfile or docker-compose.yml exists
Step 4: Test SSH connection to remote server
Step 5: Prepare remote environment
        - Update system packages
        - Install Docker & Docker Compose
        - Install Nginx
        - Configure services
Step 6: Transfer application files to server
Step 7: Build and deploy Docker containers
Step 8: Configure Nginx as reverse proxy
Step 9: Validate deployment
        - Check Docker service
        - Verify container health
        - Test application endpoints
Step 10: Display deployment summary
```

##  Logging

All deployment actions are logged to: `deploy_YYYYMMDD_HHMMSS.log`

Example:
```
deploy_20250121_203526.log
```

##  Testing

After deployment, test your application:

```bash
# Test main page
curl http://YOUR_SERVER_IP

# Test health endpoint
curl http://YOUR_SERVER_IP/api/health

# Test info endpoint
curl http://YOUR_SERVER_IP/api/info

# Check from browser
open http://YOUR_SERVER_IP
```



##  Task Requirements Met

-  Single executable Bash script
-  User input collection and validation
-  Git repository cloning with authentication
-  SSH remote execution
-  Environment preparation (Docker, Nginx)
-  Dockerized application deployment
-  Nginx reverse proxy configuration
-  Comprehensive logging
-  Error handling with trap functions
-  Deployment validation
-  Idempotent execution

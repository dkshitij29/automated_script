# Installation and Deployment Script for RIC and SS-xApp

## Overview
This script automates the setup, installation, and deployment of a Kubernetes-based environment to run the RIC platform and deploy xApps. It includes steps to configure dependencies, build software components, and deploy an SS-xApp for cellular networks.

---

## Prerequisites
- **Operating System**: Ubuntu (or similar Linux distribution)
- **Access**: Root/sudo privileges
- **Software Dependencies**: Docker, Kubernetes, and other utilities installed via the script.

---

## Features
1. **Container Management**:
   - Stops and removes any existing Docker container named `ric`.
2. **System Setup**:
   - Disables swap for Kubernetes compatibility.
   - Installs essential tools and dependencies such as `git`, `vim`, `tmux`, and `docker.io`.
3. **OAIC Cloning**:
   - Clones the OpenAirInterface Cellular (OAIC) repository and submodules.
4. **Kubernetes Setup**:
   - Installs and configures Kubernetes with a single-node setup.
   - Verifies pod deployments.
5. **InfluxDB Setup**:
   - Installs and configures an NFS server and storage class.
6. **RIC Platform Deployment**:
   - Pulls and deploys the E2 RIC platform.
7. **ASN1C Compiler**:
   - Builds and installs the ASN1C compiler for specific use cases.
8. **SS-xApp Deployment**:
   - Builds and deploys the SS-xApp with a preconfigured database.
9. **Nginx Configuration**:
   - Configures Nginx to serve xApp configuration files.
10. **Logging**:
    - Includes commands to monitor SS-xApp logs.

---

## Usage Instructions

### Step 1: Run the Script
Execute the script with root privileges:
```bash
sudo bash installation_script.sh
```

### Step 2: Verify Installations
- **Check Kubernetes Pods**:
  ```bash
  sudo kubectl get pods -A
  ```
- **Validate Nginx Configuration**:
  ```bash
  sudo nginx -t
  ```

### Step 3: Deploy xApp
- The SS-xApp will be automatically deployed. Verify the deployment via Kubernetes:
  ```bash
  sudo kubectl get pods -A
  ```

### Step 4: Monitor Logs
To view logs of the SS-xApp:
```bash
sudo kubectl logs -f -n ricxapp -l app=ricxapp-ss
```

---

## Notes
- Replace the `CONTAINER_NAME` in the script if using a custom container name.
- Ensure Docker, Kubernetes, and Helm are installed if not included in the base OS.
- Customize the script as needed, especially the repository URLs and xApp configurations.

---

## Troubleshooting
- **Issue**: Kubernetes pods are not starting.
  - **Solution**: Verify the Kubernetes installation and ensure all dependencies are installed.
- **Issue**: Nginx configuration fails.
  - **Solution**: Check the `/etc/nginx/conf.d/xApp_config.local.conf` file for syntax errors and correct paths.

---

## References
- [OAIC GitHub Repository](https://github.com/dkshitij29/oaic)
- [SS-xApp GitHub Repository](https://github.com/openaicellular/ss-xapp)


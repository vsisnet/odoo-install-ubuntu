# Odoo Installation Script for Ubuntu

This script automates the installation of the latest version of Odoo (e.g., 18.0) on Ubuntu. It configures PostgreSQL, Python, and other dependencies, making it easy to set up an Odoo server.

## Requirements
- Ubuntu 20.04 or 22.04
- Root or sudo privileges
- Internet connection

## Installation Steps
1. Download the script:
   ```bash
   if ! command -v wget >/dev/null 2>&1; then sudo apt update && sudo apt install -y wget; fi && wget https://raw.githubusercontent.com/vsisnet/odoo-install-ubuntu/master/install_odoo.sh && chmod +x install_odoo.sh && sudo ./install_odoo.sh

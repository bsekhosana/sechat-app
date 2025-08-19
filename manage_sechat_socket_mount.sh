#!/bin/bash

# SechatSocket Server SSHFS Mount Management Script
# This script helps manage the SSHFS mount to the SechatSocket server

SERVER_IP="41.76.111.100"
SERVER_USER="root"
SERVER_PORT="1337"
REMOTE_DIR="/opt/sechat-socket"
LOCAL_MOUNT_DIR="/Users/brunosekhosana/Projects/SeChat/sechat_socket"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to check if mount is active
check_mount() {
    if mount | grep -q "root@${SERVER_IP}:${REMOTE_DIR}"; then
        echo -e "${GREEN}✓ SechatSocket mount is ACTIVE${NC}"
        echo -e "  Remote: ${SERVER_USER}@${SERVER_IP}:${REMOTE_DIR}"
        echo -e "  Local:  ${LOCAL_MOUNT_DIR}"
        echo -e "  Status: $(mount | grep "root@${SERVER_IP}:${REMOTE_DIR}" | awk '{print $1, $2, $3}')"
        return 0
    elif mount | grep -q "sechat-socket"; then
        echo -e "${GREEN}✓ SechatSocket mount is ACTIVE${NC}"
        echo -e "  Remote: ${SERVER_USER}@${SERVER_IP}:${REMOTE_DIR}"
        echo -e "  Local:  ${LOCAL_MOUNT_DIR}"
        echo -e "  Status: $(mount | grep "sechat-socket" | awk '{print $1, $2, $3}')"
        return 0
    else
        echo -e "${RED}✗ SechatSocket mount is NOT ACTIVE${NC}"
        return 1
    fi
}

# Function to mount the remote directory
mount_sechat_socket() {
    echo -e "${BLUE}Mounting SechatSocket server...${NC}"
    
    if [ ! -d "$LOCAL_MOUNT_DIR" ]; then
        echo -e "${YELLOW}Creating local mount directory...${NC}"
        mkdir -p "$LOCAL_MOUNT_DIR"
    fi
    
    sshfs -o reconnect,ServerAliveInterval=15,ServerAliveCountMax=3,port=$SERVER_PORT \
          ${SERVER_USER}@${SERVER_IP}:${REMOTE_DIR} "$LOCAL_MOUNT_DIR"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Successfully mounted SechatSocket server${NC}"
        check_mount
    else
        echo -e "${RED}✗ Failed to mount SechatSocket server${NC}"
        return 1
    fi
}

# Function to unmount the remote directory
unmount_sechat_socket() {
    echo -e "${BLUE}Unmounting SechatSocket server...${NC}"
    
    if mount | grep -q "root@${SERVER_IP}:${REMOTE_DIR}" || mount | grep -q "sechat-socket"; then
        umount "$LOCAL_MOUNT_DIR"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Successfully unmounted SechatSocket server${NC}"
        else
            echo -e "${RED}✗ Failed to unmount SechatSocket server${NC}"
            echo -e "${YELLOW}You may need to use: sudo umount $LOCAL_MOUNT_DIR${NC}"
        fi
    else
        echo -e "${YELLOW}SechatSocket is not currently mounted${NC}"
    fi
}

# Function to reconnect the mount
reconnect_sechat_socket() {
    echo -e "${BLUE}Reconnecting SechatSocket server...${NC}"
    
    if mount | grep -q "root@${SERVER_IP}:${REMOTE_DIR}" || mount | grep -q "sechat-socket"; then
        echo -e "${YELLOW}Unmounting existing connection...${NC}"
        umount "$LOCAL_MOUNT_DIR"
        sleep 2
    fi
    
    mount_sechat_socket
}

# Function to show connection info
show_info() {
    echo -e "${BLUE}=== SechatSocket SSHFS Connection Info ===${NC}"
    echo -e "Server:     ${SERVER_USER}@${SERVER_IP}:${SERVER_PORT}"
    echo -e "Remote Dir: ${REMOTE_DIR}"
    echo -e "Local Mount: ${LOCAL_MOUNT_DIR}"
    echo -e ""
    check_mount
}

# Function to test connection
test_connection() {
    echo -e "${BLUE}Testing SSH connection to SechatSocket server...${NC}"
    
    if ssh -p $SERVER_PORT -o ConnectTimeout=10 -o BatchMode=yes ${SERVER_USER}@${SERVER_IP} "echo 'Connection successful'" 2>/dev/null; then
        echo -e "${GREEN}✓ SSH connection successful${NC}"
    else
        echo -e "${RED}✗ SSH connection failed${NC}"
        echo -e "${YELLOW}Please check your credentials and network connection${NC}"
        return 1
    fi
}

# Function to show help
show_help() {
    echo -e "${BLUE}SechatSocket SSHFS Mount Management Script${NC}"
    echo -e ""
    echo -e "Usage: $0 [COMMAND]"
    echo -e ""
    echo -e "Commands:"
    echo -e "  mount     - Mount the SechatSocket server"
    echo -e "  unmount   - Unmount the SechatSocket server"
    echo -e "  reconnect - Reconnect the mount (unmount + mount)"
    echo -e "  status    - Check mount status"
    echo -e "  info      - Show connection information"
    echo -e "  test      - Test SSH connection"
    echo -e "  help      - Show this help message"
    echo -e ""
    echo -e "Examples:"
    echo -e "  $0 mount"
    echo -e "  $0 status"
    echo -e "  $0 reconnect"
}

# Main script logic
case "${1:-help}" in
    "mount")
        mount_sechat_socket
        ;;
    "unmount")
        unmount_sechat_socket
        ;;
    "reconnect")
        reconnect_sechat_socket
        ;;
    "status")
        check_mount
        ;;
    "info")
        show_info
        ;;
    "test")
        test_connection
        ;;
    "help"|*)
        show_help
        ;;
esac

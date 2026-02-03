#!/bin/bash
# capsule-checkpoint.sh - Portal-Wide Checkpoint System for Capsule Cloud
# Version: 1.0.0
# Usage: capsule-checkpoint {save|restore|list|show|clean} [options]

set -euo pipefail

# Configuration
CHECKPOINT_DIR="/home/ubuntu/.capsule-checkpoints"
KEEP_COUNT=20  # Keep last 20 checkpoints by default
VERSION="1.0.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Emojis
CHECK="✅"
CROSS="✗"
CAMERA="📸"
CLOCK="🕐"

# Helper functions
log_info() {
    echo -e "${GREEN}${CHECK}${NC} $1"
}

log_error() {
    echo -e "${RED}${CROSS}${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_camera() {
    echo -e "${CAMERA} $1"
}

generate_label() {
    # Generate unique label: cp-{random}-{timestamp}
    local random=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 6 | head -n 1)
    local timestamp=$(date +%Y%m%d-%H%M%S)
    echo "cp-${random}-${timestamp}"
}

# Function: save_checkpoint
# Creates a portal-wide checkpoint
save_checkpoint() {
    local description="${1:-No description}"
    local custom_label="${2:-}"
    
    # Generate or use custom label
    if [ -n "$custom_label" ]; then
        local label="$custom_label"
    else
        local label=$(generate_label)
    fi
    
    local checkpoint_path="$CHECKPOINT_DIR/$label"
    
    log_camera "Creating checkpoint: $label"
    echo ""
    
    # Create checkpoint directory
    mkdir -p "$checkpoint_path"
    
    # 1. Backup all app deployments
    if [ -d "/home/ubuntu/deployments" ]; then
        log_info "Backing up deployments..."
        mkdir -p "$checkpoint_path/deployments"
        
        # Copy all app directories except .backups
        for app_dir in /home/ubuntu/deployments/*/; do
            if [ -d "$app_dir" ] && [[ ! "$app_dir" =~ .backups ]]; then
                app_name=$(basename "$app_dir")
                cp -r "$app_dir" "$checkpoint_path/deployments/$app_name"
            fi
        done
        
        # Copy registry.json if it exists
        if [ -f "/home/ubuntu/deployments/.registry.json" ]; then
            cp /home/ubuntu/deployments/.registry.json "$checkpoint_path/registry.json"
        fi
    fi
    
    # 2. Backup nginx route configurations
    if [ -d "/etc/nginx/conf.d/routes" ]; then
        log_info "Backing up nginx routes..."
        mkdir -p "$checkpoint_path/nginx-routes"
        sudo cp -r /etc/nginx/conf.d/routes/* "$checkpoint_path/nginx-routes/" 2>/dev/null || true
        sudo chown -R ubuntu:ubuntu "$checkpoint_path/nginx-routes"
    fi
    
    # 3. Backup main nginx server config
    if [ -f "/etc/nginx/conf.d/deploy-portal-server.conf" ]; then
        log_info "Backing up nginx server config..."
        sudo cp /etc/nginx/conf.d/deploy-portal-server.conf "$checkpoint_path/nginx-server.conf"
        sudo chown ubuntu:ubuntu "$checkpoint_path/nginx-server.conf"
    fi
    
    # 4. Create metadata
    cat > "$checkpoint_path/checkpoint-info.json" << METADATA
{
  "label": "$label",
  "description": "$description",
  "timestamp": "$(date -u +"%Y-%m-%d %H:%M:%S UTC")",
  "timestamp_unix": $(date +%s),
  "hostname": "$(hostname)",
  "user": "$USER",
  "version": "$VERSION"
}
METADATA
    
    # Create symlink to latest
    rm -f "$CHECKPOINT_DIR/latest"
    ln -sf "$checkpoint_path" "$CHECKPOINT_DIR/latest"
    
    # Calculate checkpoint size
    local size=$(du -sh "$checkpoint_path" | cut -f1)
    
    echo ""
    log_info "Checkpoint saved: $label"
    echo "  Description: $description"
    echo "  Location: $checkpoint_path"
    echo "  Size: $size"
    echo ""
    log_info "To rollback: capsule-checkpoint restore $label"
    
    # Return label for use in scripts
    echo "$label"
}

# Function: restore_checkpoint
# Restores portal to a previous checkpoint
restore_checkpoint() {
    local label="$1"
    local checkpoint_path="$CHECKPOINT_DIR/$label"
    
    if [ ! -d "$checkpoint_path" ]; then
        log_error "Checkpoint not found: $label"
        log_warning "Use 'capsule-checkpoint list' to see available checkpoints"
        return 1
    fi
    
    log_camera "Restoring checkpoint: $label"
    echo ""
    
    # Show checkpoint info
    if [ -f "$checkpoint_path/checkpoint-info.json" ]; then
        local desc=$(jq -r '.description' "$checkpoint_path/checkpoint-info.json" 2>/dev/null || echo "N/A")
        local timestamp=$(jq -r '.timestamp' "$checkpoint_path/checkpoint-info.json" 2>/dev/null || echo "N/A")
        echo "  Description: $desc"
        echo "  Created: $timestamp"
        echo ""
    fi
    
    # Safety backup before restore
    log_info "Creating safety backup of current state..."
    local safety_label="safety-$(date +%Y%m%d-%H%M%S)"
    save_checkpoint "Safety backup before restoring $label" "$safety_label" > /dev/null
    echo ""
    
    # Stop all containers
    log_info "Stopping all containers..."
    for app_dir in /home/ubuntu/deployments/*/; do
        if [ -d "$app_dir" ] && [ -f "$app_dir/docker-compose.yml" ]; then
            app_name=$(basename "$app_dir")
            echo "  Stopping $app_name..."
            (cd "$app_dir" && docker-compose down 2>/dev/null) || true
        fi
    done
    echo ""
    
    # Restore deployments
    if [ -d "$checkpoint_path/deployments" ]; then
        log_info "Restoring deployments..."
        for app_checkpoint in "$checkpoint_path/deployments"/*; do
            if [ -d "$app_checkpoint" ]; then
                app_name=$(basename "$app_checkpoint")
                echo "  Restoring $app_name..."
                
                # Remove current deployment
                rm -rf "/home/ubuntu/deployments/$app_name"
                
                # Copy from checkpoint
                cp -r "$app_checkpoint" "/home/ubuntu/deployments/$app_name"
            fi
        done
    fi
    
    # Restore registry
    if [ -f "$checkpoint_path/registry.json" ]; then
        log_info "Restoring port registry..."
        cp "$checkpoint_path/registry.json" "/home/ubuntu/deployments/.registry.json"
    fi
    
    # Restore nginx routes
    if [ -d "$checkpoint_path/nginx-routes" ]; then
        log_info "Restoring nginx routes..."
        sudo rm -rf /etc/nginx/conf.d/routes/*
        sudo cp -r "$checkpoint_path/nginx-routes"/* /etc/nginx/conf.d/routes/
    fi
    
    # Restore nginx server config
    if [ -f "$checkpoint_path/nginx-server.conf" ]; then
        log_info "Restoring nginx server config..."
        sudo cp "$checkpoint_path/nginx-server.conf" /etc/nginx/conf.d/deploy-portal-server.conf
    fi
    
    # Test nginx config
    log_info "Testing nginx configuration..."
    if sudo nginx -t 2>&1 | grep -q "successful"; then
        log_info "Nginx config valid - reloading..."
        sudo systemctl reload nginx
    else
        log_error "Nginx config test failed!"
        log_warning "Manual intervention required"
        return 1
    fi
    
    # Restart containers
    log_info "Restarting containers..."
    for app_dir in /home/ubuntu/deployments/*/; do
        if [ -d "$app_dir" ] && [ -f "$app_dir/docker-compose.yml" ]; then
            app_name=$(basename "$app_dir")
            echo "  Starting $app_name..."
            (cd "$app_dir" && docker-compose up -d 2>/dev/null) || true
        fi
    done
    
    echo ""
    log_info "Restore complete!"
    echo ""
    log_warning "Safety backup created: $safety_label"
    echo "  If restore caused issues, restore safety backup:"
    echo "  capsule-checkpoint restore $safety_label"
}

# Function: list_checkpoints
# Lists all available checkpoints
list_checkpoints() {
    if [ ! -d "$CHECKPOINT_DIR" ] || [ -z "$(ls -A $CHECKPOINT_DIR 2>/dev/null)" ]; then
        log_warning "No checkpoints found"
        echo "  Create your first checkpoint with:"
        echo "  capsule-checkpoint save \"Description\""
        return 0
    fi
    
    echo "Available Checkpoints:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "%-30s %-20s %-12s %s\n" "LABEL" "TIMESTAMP" "SIZE" "DESCRIPTION"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Sort by timestamp (newest first)
    for checkpoint in $(ls -1dt "$CHECKPOINT_DIR"/*/); do
        local label=$(basename "$checkpoint")
        
        # Skip symlinks
        [ -L "$CHECKPOINT_DIR/$label" ] && continue
        
        local info_file="$checkpoint/checkpoint-info.json"
        if [ -f "$info_file" ]; then
            local timestamp=$(jq -r '.timestamp // "N/A"' "$info_file" 2>/dev/null)
            local description=$(jq -r '.description // "No description"' "$info_file" 2>/dev/null)
        else
            local timestamp="N/A"
            local description="No metadata"
        fi
        
        local size=$(du -sh "$checkpoint" 2>/dev/null | cut -f1)
        
        # Highlight latest
        if [ -L "$CHECKPOINT_DIR/latest" ] && [ "$(readlink $CHECKPOINT_DIR/latest)" = "$checkpoint" ]; then
            printf "${GREEN}%-30s${NC} %-20s %-12s %s\n" "$label" "$timestamp" "$size" "$description [LATEST]"
        else
            printf "%-30s %-20s %-12s %s\n" "$label" "$timestamp" "$size" "$description"
        fi
    done
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    local count=$(ls -1d "$CHECKPOINT_DIR"/*/ 2>/dev/null | wc -l | tr -d ' ')
    echo "Total checkpoints: $count"
}

# Function: show_checkpoint
# Shows detailed information about a checkpoint
show_checkpoint() {
    local label="$1"
    local checkpoint_path="$CHECKPOINT_DIR/$label"
    
    if [ ! -d "$checkpoint_path" ]; then
        log_error "Checkpoint not found: $label"
        return 1
    fi
    
    echo "Checkpoint Details: $label"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Show metadata
    if [ -f "$checkpoint_path/checkpoint-info.json" ]; then
        echo ""
        echo "Metadata:"
        cat "$checkpoint_path/checkpoint-info.json" | jq '.'
    fi
    
    echo ""
    echo "Contents:"
    tree -L 2 "$checkpoint_path" 2>/dev/null || ls -lh "$checkpoint_path"
    
    echo ""
    echo "Size:"
    du -sh "$checkpoint_path"
    
    # Show deployed apps
    if [ -d "$checkpoint_path/deployments" ]; then
        echo ""
        echo "Deployed Apps:"
        ls -1 "$checkpoint_path/deployments" | sed 's/^/  - /'
    fi
}

# Function: clean_checkpoints
# Removes old checkpoints
clean_checkpoints() {
    local keep="${1:-$KEEP_COUNT}"
    
    log_camera "Cleaning old checkpoints (keeping last $keep)..."
    echo ""
    
    # Count checkpoints
    local count=$(ls -1dt "$CHECKPOINT_DIR"/*/ 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$count" -le "$keep" ]; then
        log_info "Only $count checkpoints exist (keeping $keep)"
        echo "  No cleanup needed"
        return 0
    fi
    
    # Remove old checkpoints
    local to_remove=$((count - keep))
    log_info "Removing $to_remove old checkpoints..."
    
    ls -1dt "$CHECKPOINT_DIR"/*/ | tail -n "$to_remove" | while read checkpoint; do
        local label=$(basename "$checkpoint")
        echo "  Removing: $label"
        rm -rf "$checkpoint"
    done
    
    echo ""
    log_info "Cleanup complete"
}

# Main command dispatcher
main() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        save)
            local description="${1:-No description provided}"
            local label_flag="${2:-}"
            local custom_label=""
            
            if [ "$label_flag" = "--label" ] && [ -n "${3:-}" ]; then
                custom_label="$3"
            fi
            
            save_checkpoint "$description" "$custom_label"
            ;;
            
        restore)
            if [ -z "${1:-}" ]; then
                log_error "Usage: capsule-checkpoint restore <label>"
                exit 1
            fi
            restore_checkpoint "$1"
            ;;
            
        list)
            list_checkpoints
            ;;
            
        show)
            if [ -z "${1:-}" ]; then
                log_error "Usage: capsule-checkpoint show <label>"
                exit 1
            fi
            show_checkpoint "$1"
            ;;
            
        clean)
            local keep="$KEEP_COUNT"
            if [ "${1:-}" = "--keep" ] && [ -n "${2:-}" ]; then
                keep="$2"
            fi
            clean_checkpoints "$keep"
            ;;
            
        help|--help|-h)
            cat << HELP
Capsule Cloud Portal Checkpoint System v$VERSION

Usage: capsule-checkpoint <command> [options]

Commands:
  save <description> [--label <name>]  Create a new checkpoint
  restore <label>                       Restore from a checkpoint
  list                                  List all checkpoints
  show <label>                          Show checkpoint details
  clean [--keep N]                      Remove old checkpoints (keep last N)
  help                                  Show this help message

Examples:
  # Create checkpoint
  capsule-checkpoint save "Before deploying new-app"
  
  # Create checkpoint with custom label
  capsule-checkpoint save "Stable baseline" --label baseline-v1
  
  # List all checkpoints
  capsule-checkpoint list
  
  # Show checkpoint details
  capsule-checkpoint show cp-abc123-20260203-060000
  
  # Restore from checkpoint
  capsule-checkpoint restore cp-abc123-20260203-060000
  
  # Clean old checkpoints (keep last 10)
  capsule-checkpoint clean --keep 10

HELP
            ;;
            
        *)
            log_error "Unknown command: $command"
            echo "Use 'capsule-checkpoint help' for usage information"
            exit 1
            ;;
    esac
}

# Create checkpoint directory if it doesn't exist
mkdir -p "$CHECKPOINT_DIR"

# Run main function
main "$@"

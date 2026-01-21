#!/bin/bash
#
# SSM Connection Wrapper
# Provides seamless AWS Systems Manager Session Manager access
# Replaces traditional SSH with secure, audited remote access
#

set -euo pipefail

# Configuration
INSTANCE_ID="${SSM_INSTANCE_ID:-i-0d1e3b59f57974076}"
REGION="${AWS_REGION:-us-east-1}"
PROFILE="${AWS_PROFILE:-default}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS] [COMMAND]

Connect to EC2 instance via AWS Systems Manager Session Manager

OPTIONS:
    -i, --instance ID       Instance ID (default: ${INSTANCE_ID})
    -r, --region REGION     AWS Region (default: ${REGION})
    -p, --profile PROFILE   AWS Profile (default: ${PROFILE})
    -f, --forward PORT      Forward local port to remote (format: local:remote)
    -h, --help              Show this help message

COMMANDS:
    connect                 Start interactive session (default)
    port-forward            Forward ports for remote debugging
    status                  Check SSM agent status
    logs                    View recent session logs

EXAMPLES:
    # Interactive session
    $0

    # Port forwarding for debugging
    $0 --forward 5000:5000

    # Check SSM agent status
    $0 status

    # Use different instance
    $0 -i i-1234567890abcdef0

EOF
    exit 0
}

# Check prerequisites
check_prerequisites() {
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}Error: AWS CLI not installed${NC}"
        echo "Install with: pip install awscli"
        exit 1
    fi

    if ! command -v session-manager-plugin &> /dev/null; then
        echo -e "${YELLOW}Warning: Session Manager plugin not installed${NC}"
        echo "Install with: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
        exit 1
    fi
}

# Check SSM agent status
check_agent_status() {
    echo -e "${YELLOW}Checking SSM agent status...${NC}"

    local status=$(aws ssm describe-instance-information \
        --region "${REGION}" \
        --profile "${PROFILE}" \
        --filters "Key=InstanceIds,Values=${INSTANCE_ID}" \
        --query 'InstanceInformationList[0].PingStatus' \
        --output text 2>/dev/null || echo "ERROR")

    if [ "${status}" = "Online" ]; then
        echo -e "${GREEN}✓ SSM Agent is online${NC}"
        return 0
    elif [ "${status}" = "ERROR" ]; then
        echo -e "${RED}✗ Unable to check SSM agent status${NC}"
        echo "  Check AWS credentials and permissions"
        return 1
    else
        echo -e "${RED}✗ SSM Agent is ${status}${NC}"
        echo "  Run on instance: sudo systemctl status snap.amazon-ssm-agent.amazon-ssm-agent"
        return 1
    fi
}

# Start interactive session
start_session() {
    echo -e "${GREEN}Starting SSM session to ${INSTANCE_ID}...${NC}"

    aws ssm start-session \
        --target "${INSTANCE_ID}" \
        --region "${REGION}" \
        --profile "${PROFILE}"
}

# Port forwarding
port_forward() {
    local port_spec="$1"
    local local_port="${port_spec%%:*}"
    local remote_port="${port_spec##*:}"

    echo -e "${GREEN}Forwarding local port ${local_port} to remote port ${remote_port}...${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop forwarding${NC}"

    aws ssm start-session \
        --target "${INSTANCE_ID}" \
        --region "${REGION}" \
        --profile "${PROFILE}" \
        --document-name AWS-StartPortForwardingSession \
        --parameters "{\"portNumber\":[\"${remote_port}\"],\"localPortNumber\":[\"${local_port}\"]}"
}

# View session logs
view_logs() {
    echo -e "${YELLOW}Recent SSM session logs:${NC}"

    aws ssm describe-sessions \
        --region "${REGION}" \
        --profile "${PROFILE}" \
        --state History \
        --filters "key=Target,value=${INSTANCE_ID}" \
        --max-results 10 \
        --query 'Sessions[*].[SessionId,StartDate,EndDate,Status]' \
        --output table
}

# Main
main() {
    local command="connect"
    local port_spec=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--instance)
                INSTANCE_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -p|--profile)
                PROFILE="$2"
                shift 2
                ;;
            -f|--forward)
                command="port-forward"
                port_spec="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            status)
                command="status"
                shift
                ;;
            logs)
                command="logs"
                shift
                ;;
            connect)
                command="connect"
                shift
                ;;
            port-forward)
                command="port-forward"
                shift
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                usage
                ;;
        esac
    done

    check_prerequisites

    case "${command}" in
        connect)
            check_agent_status && start_session
            ;;
        port-forward)
            if [ -z "${port_spec}" ]; then
                echo -e "${RED}Error: Port specification required${NC}"
                echo "Example: $0 --forward 5000:5000"
                exit 1
            fi
            check_agent_status && port_forward "${port_spec}"
            ;;
        status)
            check_agent_status
            ;;
        logs)
            view_logs
            ;;
    esac
}

main "$@"

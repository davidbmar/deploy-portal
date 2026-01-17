import os

class Config:
    SECRET_KEY = os.environ.get('SECRET_KEY', os.urandom(24).hex())
    SECURITY_GROUP_ID = 'sg-0d6bbadbbd290b320'
    SSH_KEY_PATH = '/home/ubuntu/src/deploy-portal/keys/deploy-key.pem'
    SSH_KEY_NAME = 'deploy-key'
    ACTIVITY_LOG_DIR = '/var/log/deploy-sessions'
    EC2_USER = 'ubuntu'

    # Deployment configuration
    DEPLOYMENT_ROOT = '/home/ubuntu/deployments'
    PORT_RANGE_START = 5001
    PORT_RANGE_END = 5999
    REGISTRY_FILE = '/home/ubuntu/deployments/.registry.json'

    # Version management
    DEPLOYMENT_VERSION_FORMAT = "%Y%m%d.%H%M%S"
    SESSION_TIMEOUT_MINUTES = 30
    SKILL_FILE_PATH = "deploy-skill.yaml"

    # Get AWS region from metadata
    @staticmethod
    def get_region():
        import urllib.request
        try:
            # IMDSv2
            token_request = urllib.request.Request(
                'http://169.254.169.254/latest/api/token',
                headers={'X-aws-ec2-metadata-token-ttl-seconds': '21600'},
                method='PUT'
            )
            token = urllib.request.urlopen(token_request, timeout=2).read().decode()
            region_request = urllib.request.Request(
                'http://169.254.169.254/latest/meta-data/placement/region',
                headers={'X-aws-ec2-metadata-token': token}
            )
            return urllib.request.urlopen(region_request, timeout=2).read().decode()
        except:
            return 'us-west-2'  # Default fallback

    # Get instance public IP from metadata
    @staticmethod
    def get_instance_ip():
        import urllib.request
        try:
            # IMDSv2
            token_request = urllib.request.Request(
                'http://169.254.169.254/latest/api/token',
                headers={'X-aws-ec2-metadata-token-ttl-seconds': '21600'},
                method='PUT'
            )
            token = urllib.request.urlopen(token_request, timeout=2).read().decode()
            ip_request = urllib.request.Request(
                'http://169.254.169.254/latest/meta-data/public-ipv4',
                headers={'X-aws-ec2-metadata-token': token}
            )
            return urllib.request.urlopen(ip_request, timeout=2).read().decode()
        except:
            return 'UNKNOWN'

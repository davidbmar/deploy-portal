import os
import urllib.request
import logging
import time

logger = logging.getLogger(__name__)

class ConfigLoader:
    """Load configuration from multiple sources with priority order:
    1. Environment variables
    2. Config file (~/.ec2-config.env)
    3. AWS metadata service
    4. Hardcoded defaults
    """

    def __init__(self):
        self.config_file_path = os.path.expanduser('~/.ec2-config.env')
        self.env_file_data = self._load_env_file(self.config_file_path)

    def _load_env_file(self, path):
        """Parse shell-style environment file"""
        env_data = {}
        try:
            if os.path.exists(path):
                with open(path, 'r') as f:
                    for line in f:
                        line = line.strip()
                        # Skip comments and empty lines
                        if not line or line.startswith('#'):
                            continue
                        # Remove 'export ' prefix if present
                        if line.startswith('export '):
                            line = line[7:]
                        # Parse KEY=VALUE
                        if '=' in line:
                            key, value = line.split('=', 1)
                            # Remove quotes if present
                            value = value.strip('\'"')
                            env_data[key.strip()] = value
                logger.info(f"Loaded config file: {path}")
        except Exception as e:
            logger.warning(f"Could not load config file {path}: {e}")
        return env_data

    @staticmethod
    def _query_metadata(endpoint):
        """Fetch value from AWS metadata service using IMDSv2"""
        try:
            # Get token for IMDSv2
            token_request = urllib.request.Request(
                'http://169.254.169.254/latest/api/token',
                headers={'X-aws-ec2-metadata-token-ttl-seconds': '21600'},
                method='PUT'
            )
            token = urllib.request.urlopen(token_request, timeout=2).read().decode()

            # Fetch metadata using token
            metadata_request = urllib.request.Request(
                f'http://169.254.169.254/latest/meta-data/{endpoint}',
                headers={'X-aws-ec2-metadata-token': token}
            )
            value = urllib.request.urlopen(metadata_request, timeout=2).read().decode()
            return value
        except Exception as e:
            logger.debug(f"Could not fetch metadata {endpoint}: {e}")
            return None

    def _get_from_metadata(self, endpoint):
        """Fetch value from AWS metadata service using IMDSv2"""
        return ConfigLoader._query_metadata(endpoint)

    def get_config_value(self, key, metadata_endpoint=None, default=None):
        """Get config value with priority: env var → config file → metadata → default"""
        # 1. Check environment variable
        if key in os.environ:
            logger.info(f"Config {key}: loaded from environment variable")
            return os.environ[key]

        # 2. Check config file
        if key in self.env_file_data:
            logger.info(f"Config {key}: loaded from config file ({self.config_file_path})")
            return self.env_file_data[key]

        # 3. Check AWS metadata
        if metadata_endpoint:
            value = self._get_from_metadata(metadata_endpoint)
            if value:
                logger.info(f"Config {key}: loaded from AWS metadata service")
                return value

        # 4. Use default
        if default is not None:
            logger.info(f"Config {key}: using default value")
        return default

class Config:
    # Initialize config loader
    _loader = ConfigLoader()

    SECRET_KEY = os.environ.get('SECRET_KEY', os.urandom(24).hex())

    # Dynamic security group ID (loaded from env, config file, or default)
    SECURITY_GROUP_ID = _loader.get_config_value(
        'SECURITY_GROUP_ID',
        default='sg-0d485b4ffe8c8f886'
    )

    # Instance identifier for security group resolution
    # Can be: Public IP, Instance ID (i-xxx), or Instance Name
    # If not set, will use get_instance_ip()
    INSTANCE_IDENTIFIER = _loader.get_config_value(
        'INSTANCE_IDENTIFIER',
        default=None
    )

    # Instance metadata (populated by initialize_instance_metadata)
    INSTANCE_ID = None
    INSTANCE_PUBLIC_IP = None
    INSTANCE_PRIVATE_IP = None
    INSTANCE_SECURITY_GROUPS = []

    # Metadata caching
    _instance_metadata_cache = None
    _metadata_cache_time = None
    _metadata_cache_ttl = 300  # 5 minutes

    # SSH Configuration - configurable via environment variables
    SSH_KEY_PATH = _loader.get_config_value(
        'SSH_KEY_PATH',
        default='/home/ubuntu/src/deploy-portal/keys/deploy-key.pem'
    )
    SSH_KEY_NAME = _loader.get_config_value(
        'SSH_KEY_NAME',
        default='deploy-key'
    )
    ACTIVITY_LOG_DIR = '/var/log/deploy-sessions'
    EC2_USER = 'ubuntu'
    DUCKDNS_DOMAIN = 'capsule-deploy.duckdns.org'

    # Deployment configuration
    DEPLOYMENT_ROOT = '/home/ubuntu/deployments'
    PORT_RANGE_START = 5001
    PORT_RANGE_END = 5999
    REGISTRY_FILE = '/home/ubuntu/deployments/.registry.json'

    # Version management
    DEPLOYMENT_VERSION_FORMAT = "%Y%m%d.%H%M%S"
    SESSION_TIMEOUT_MINUTES = 30
    SKILL_FILE_PATH = "deploy-skill.yaml"

    # Get AWS region from config
    @staticmethod
    def get_region():
        loader = ConfigLoader()
        return loader.get_config_value(
            'AWS_REGION',
            metadata_endpoint='placement/region',
            default='us-west-2'
        )

    # Get instance IP or domain
    @staticmethod
    def get_instance_ip():
        """
        Get instance IP address or domain.
        Prefers INSTANCE_DOMAIN from config, falls back to instance metadata.
        """
        # 1. Check for custom domain first (highest priority)
        loader = ConfigLoader()
        domain = loader.get_config_value('INSTANCE_DOMAIN', default=None)
        if domain:
            logger.info(f"Using instance domain: {domain}")
            return domain

        # 2. If metadata initialized, use it
        if Config.INSTANCE_PUBLIC_IP:
            return Config.INSTANCE_PUBLIC_IP

        # 3. Otherwise get public IP from config or metadata
        ip = loader.get_config_value(
            'PUBLIC_IP',
            metadata_endpoint='public-ipv4',
            default='127.0.0.1'
        )
        return ip

    @staticmethod
    def get_instance_id():
        """Get the EC2 instance ID from metadata service."""
        if Config.INSTANCE_ID:
            return Config.INSTANCE_ID

        instance_id = ConfigLoader._query_metadata('instance-id')
        return instance_id

    @staticmethod
    def get_instance_metadata():
        """
        Query EC2 instance metadata and return comprehensive info.

        Returns:
            dict: {
                'instance_id': str,
                'public_ip': str or None,
                'private_ip': str,
                'security_groups': [{'GroupId': str, 'GroupName': str}, ...],
                'region': str,
                'availability_zone': str
            } or None if not on EC2
        """
        import boto3
        from botocore.exceptions import ClientError, NoCredentialsError

        try:
            # 1. Get instance ID from metadata service
            instance_id = ConfigLoader._query_metadata('instance-id')
            if not instance_id:
                logger.warning("Not running on EC2 or metadata unavailable")
                return None

            # 2. Get region
            region = ConfigLoader._query_metadata('placement/region')
            if not region:
                region = os.environ.get('AWS_REGION', 'us-east-1')

            # 3. Query EC2 API for full instance details
            ec2 = boto3.client('ec2', region_name=region)
            response = ec2.describe_instances(InstanceIds=[instance_id])

            if not response['Reservations']:
                logger.error(f"Instance {instance_id} not found")
                return None

            instance = response['Reservations'][0]['Instances'][0]

            # 4. Extract relevant data
            metadata = {
                'instance_id': instance_id,
                'public_ip': instance.get('PublicIpAddress'),  # May be None
                'private_ip': instance.get('PrivateIpAddress'),
                'security_groups': instance.get('SecurityGroups', []),
                'region': region,
                'availability_zone': instance.get('Placement', {}).get('AvailabilityZone')
            }

            logger.info(f"Instance metadata: {metadata['instance_id']} - "
                       f"Public: {metadata['public_ip']}, "
                       f"Private: {metadata['private_ip']}")

            return metadata

        except NoCredentialsError:
            logger.error("No AWS credentials available (IAM role not attached?)")
            return None
        except ClientError as e:
            logger.error(f"AWS API error: {e}")
            return None
        except Exception as e:
            logger.error(f"Error getting instance metadata: {e}")
            return None

    @classmethod
    def get_cached_instance_metadata(cls):
        """Get instance metadata with caching."""
        now = time.time()

        # Return cached if fresh
        if (cls._instance_metadata_cache and
            cls._metadata_cache_time and
            now - cls._metadata_cache_time < cls._metadata_cache_ttl):
            return cls._instance_metadata_cache

        # Refresh cache
        cls._instance_metadata_cache = cls.get_instance_metadata()
        cls._metadata_cache_time = now
        return cls._instance_metadata_cache

    @classmethod
    def initialize_instance_metadata(cls):
        """Initialize instance metadata on startup."""
        try:
            metadata = cls.get_instance_metadata()
            if metadata:
                cls.INSTANCE_ID = metadata['instance_id']
                cls.INSTANCE_PUBLIC_IP = metadata['public_ip']
                cls.INSTANCE_PRIVATE_IP = metadata['private_ip']
                cls.INSTANCE_SECURITY_GROUPS = metadata['security_groups']

                # Update SECURITY_GROUP_ID to use discovered SG if not already set
                if cls.INSTANCE_SECURITY_GROUPS and not cls._loader.get_config_value('SECURITY_GROUP_ID', default=None):
                    # Use first security group (prefer the one with SSH access if we can determine it)
                    for sg in cls.INSTANCE_SECURITY_GROUPS:
                        if sg.get('GroupId'):
                            cls.SECURITY_GROUP_ID = sg['GroupId']
                            logger.info(f"Using discovered security group: {cls.SECURITY_GROUP_ID}")
                            break

                logger.info("Instance metadata initialized successfully")
            else:
                logger.warning("Could not initialize instance metadata - using config fallbacks")
        except Exception as e:
            logger.error(f"Error initializing instance metadata: {e}")
            logger.warning("Continuing with config file fallbacks")

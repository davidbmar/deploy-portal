# SSL/HTTPS Configuration Guide

This guide covers SSL certificate management, HTTPS configuration, and troubleshooting for the deployment portal.

## Overview

The deployment portal supports both HTTP and HTTPS access:
- **HTTP (port 80)**: Unencrypted access, works without SSL certificates
- **HTTPS (port 443)**: Encrypted access using SSL/TLS certificates

Both protocols work independently with no forced redirect, allowing flexibility for different deployment scenarios.

## Current SSL Configuration

### Certificate Details
- **Type**: Self-signed certificate
- **Validity**: 10 years (expires 2036-01-30)
- **Location**:
  - Certificate: `/etc/nginx/ssl/selfsigned.crt`
  - Private key: `/etc/nginx/ssl/selfsigned.key`
- **Subject**: `CN=3.87.27.213, O=DeploymentPortal, C=US`

### TLS Configuration
- **Protocols**: TLS 1.2, TLS 1.3
- **Cipher suites**: Modern, secure ciphers (ECDHE, AES-GCM, ChaCha20-Poly1305)
- **Session cache**: 50MB shared cache, 1-day timeout
- **OCSP stapling**: Disabled (not applicable for self-signed)

### Security Headers
The HTTPS server block includes:
- `Strict-Transport-Security: max-age=31536000` (HSTS)
- `X-Frame-Options: SAMEORIGIN` (clickjacking protection)
- `X-Content-Type-Options: nosniff` (MIME sniffing protection)
- `X-XSS-Protection: 1; mode=block` (XSS protection)

## Automated SSL Setup

### For New Deployments

SSL is automatically configured when running `bootstrap.sh`:

```bash
git clone https://github.com/davidbmar/deploy-portal.git
cd deploy-portal
./bootstrap.sh
```

The bootstrap process:
1. Installs nginx and deploy-portal dependencies
2. Runs `scripts/setup-ssl.sh` to generate certificates
3. Applies `nginx/server.conf` template with SSL configuration
4. Verifies port 443 is listening

### Manual SSL Setup

If you need to set up SSL manually or on an existing instance:

```bash
cd /home/ubuntu/src/deploy-portal

# Generate SSL certificates (10-year validity)
sudo bash scripts/setup-ssl.sh

# Configure nginx with SSL server block
sudo bash scripts/configure-nginx-ssl.sh

# Verify nginx configuration
sudo nginx -t

# Reload nginx
sudo systemctl reload nginx

# Verify port 443 is listening
sudo netstat -tlnp | grep ':443'
```

## Certificate Management

### Checking Certificate Expiration

```bash
# View certificate validity dates
sudo openssl x509 -in /etc/nginx/ssl/selfsigned.crt -noout -dates

# Full certificate details
sudo openssl x509 -in /etc/nginx/ssl/selfsigned.crt -text -noout
```

### Regenerating Certificates

The `setup-ssl.sh` script automatically regenerates certificates if:
- No certificate exists
- Certificate expires in less than 30 days

To force regeneration:

```bash
# Backup and remove existing certificates
sudo mv /etc/nginx/ssl/selfsigned.crt /etc/nginx/ssl/selfsigned.crt.old
sudo mv /etc/nginx/ssl/selfsigned.key /etc/nginx/ssl/selfsigned.key.old

# Regenerate
sudo bash /home/ubuntu/src/deploy-portal/scripts/setup-ssl.sh

# Reload nginx
sudo systemctl reload nginx
```

### Custom Certificate Parameters

To generate a certificate with custom parameters:

```bash
sudo openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
  -keyout /etc/nginx/ssl/selfsigned.key \
  -out /etc/nginx/ssl/selfsigned.crt \
  -subj "/C=US/ST=YourState/L=YourCity/O=YourOrg/CN=yourdomain.com"

sudo chmod 644 /etc/nginx/ssl/selfsigned.crt
sudo chmod 600 /etc/nginx/ssl/selfsigned.key
sudo systemctl reload nginx
```

## Migrating to Let's Encrypt

For production deployments with a domain name, migrate to Let's Encrypt for trusted certificates:

### Prerequisites
- Domain name pointing to your server IP
- Port 80 accessible from the internet (for ACME challenge)

### Installation

```bash
# Install certbot
sudo apt-get update
sudo apt-get install certbot python3-certbot-nginx

# Obtain and install certificate
sudo certbot --nginx -d yourdomain.com

# Certbot automatically:
# - Obtains certificate from Let's Encrypt
# - Updates nginx configuration
# - Sets up auto-renewal

# Verify auto-renewal
sudo certbot renew --dry-run
```

### Manual Let's Encrypt Configuration

If you prefer manual configuration:

```bash
# Obtain certificate only (no nginx auto-config)
sudo certbot certonly --webroot -w /var/www/html -d yourdomain.com

# Update nginx SSL certificate paths
sudo nano /etc/nginx/conf.d/deploy-portal-server.conf
# Change:
#   ssl_certificate /etc/nginx/ssl/selfsigned.crt;
#   ssl_certificate_key /etc/nginx/ssl/selfsigned.key;
# To:
#   ssl_certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
#   ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;

# Enable OCSP stapling for Let's Encrypt
# Change:
#   ssl_stapling off;
#   ssl_stapling_verify off;
# To:
#   ssl_stapling on;
#   ssl_stapling_verify on;
#   ssl_trusted_certificate /etc/letsencrypt/live/yourdomain.com/chain.pem;

sudo nginx -t
sudo systemctl reload nginx
```

## SSL Detection in Deploy Portal

The deployment portal automatically detects SSL availability using `services/framework_detector.py`:

### Detection Logic

```python
def detect_ssl_on_server(target_ip, ssh_key_path):
    """
    Returns "https" if:
    1. SSL certificate exists (Let's Encrypt OR self-signed)
    2. Port 443 is listening

    Otherwise returns "http"
    """
```

### Checked Locations
- Let's Encrypt: `/etc/letsencrypt/live/*/fullchain.pem`
- Self-signed: `/etc/nginx/ssl/selfsigned.crt`
- Port listening: `netstat -tlnp | grep ':443'`

### Testing SSL Detection

```bash
cd /home/ubuntu/src/deploy-portal
python3 << 'EOF'
from services.framework_detector import FrameworkDetector

detector = FrameworkDetector()
protocol = detector.detect_ssl_on_server(
    '3.87.27.213',
    '/home/ubuntu/login/deployment-portal-vibeland-us-east-1.pem'
)
print(f"Detected protocol: {protocol}")
EOF
```

## Troubleshooting

### Port 443 Not Listening

```bash
# Check if nginx is running
sudo systemctl status nginx

# Check nginx configuration
sudo nginx -t

# Check for SSL server block
sudo grep -A 5 "listen 443" /etc/nginx/conf.d/deploy-portal-server.conf

# Restart nginx
sudo systemctl restart nginx

# Verify port 443
sudo netstat -tlnp | grep ':443'
```

### Certificate Permission Issues

```bash
# Check certificate file permissions
ls -la /etc/nginx/ssl/

# Fix permissions
sudo chmod 644 /etc/nginx/ssl/selfsigned.crt
sudo chmod 600 /etc/nginx/ssl/selfsigned.key
sudo chown root:root /etc/nginx/ssl/selfsigned.*
```

### Browser Certificate Warnings

Self-signed certificates will show warnings in browsers:
- **Chrome/Edge**: "Your connection is not private" (NET::ERR_CERT_AUTHORITY_INVALID)
- **Firefox**: "Warning: Potential Security Risk Ahead"
- **Safari**: "This Connection Is Not Private"

**Options:**
1. **Accept the risk**: Click "Advanced" → "Proceed" (for testing)
2. **Import certificate**: Add to browser/OS trusted certificates
3. **Use curl with -k flag**: `curl -k https://...`
4. **Migrate to Let's Encrypt**: Trusted by all browsers

### macOS Certificate Trust

To trust the self-signed certificate on macOS:

```bash
# Download certificate
curl -k https://3.87.27.213 --output deployment-portal.crt

# Import to keychain
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain deployment-portal.crt
```

### nginx Configuration Conflicts

If nginx fails to start:

```bash
# Check for duplicate default_server declarations
sudo grep -r "listen 443.*default_server" /etc/nginx/

# Only one config should have "default_server" on port 443
# Remove or edit conflicting configs

sudo nginx -t
sudo systemctl restart nginx
```

### Firewall/Security Group Issues

```bash
# Check local firewall (if using ufw)
sudo ufw status
sudo ufw allow 443/tcp

# AWS Security Group (via aws-cli)
aws ec2 describe-security-groups --group-ids sg-0d485b4ffe8c8f886 \
  --query 'SecurityGroups[0].IpPermissions[?ToPort==`443`]'

# Add rule if missing
aws ec2 authorize-security-group-ingress \
  --group-id sg-0d485b4ffe8c8f886 \
  --protocol tcp --port 443 --cidr YOUR_IP/32
```

## Testing SSL Configuration

### Basic HTTPS Test

```bash
# Test from server
curl -k -I https://localhost/health

# Test from remote
curl -k -I https://3.87.27.213/health

# Should return:
# HTTP/1.1 200 OK
# Strict-Transport-Security: max-age=31536000
```

### SSL Protocol/Cipher Test

```bash
# Show SSL handshake details
openssl s_client -connect 3.87.27.213:443 -brief

# Test specific TLS version
openssl s_client -connect 3.87.27.213:443 -tls1_2
openssl s_client -connect 3.87.27.213:443 -tls1_3

# Verify TLS 1.0/1.1 are disabled (should fail)
openssl s_client -connect 3.87.27.213:443 -tls1
```

### Security Headers Test

```bash
curl -k -I https://3.87.27.213/health | grep -E "Strict-Transport|X-Frame|X-Content|X-XSS"

# Expected output:
# Strict-Transport-Security: max-age=31536000
# X-Frame-Options: SAMEORIGIN
# X-Content-Type-Options: nosniff
# X-XSS-Protection: 1; mode=block
```

### Online SSL Testing

For publicly accessible servers:
- [SSL Labs](https://www.ssllabs.com/ssltest/): Comprehensive SSL/TLS analysis
- [Security Headers](https://securityheaders.com/): Security header analysis

## VPC and Private Network Deployment

For internal VPC deployments:

### Benefits of Self-Signed Certificates
- ✅ No external certificate authority required
- ✅ No certificate renewal process
- ✅ Suitable for private networks
- ✅ Encryption without browser warnings (with VPN)

### Recommended Setup
1. Deploy portal in private VPC subnet
2. Access via VPN only
3. Use self-signed certificates (no Let's Encrypt needed)
4. Update security groups to restrict access to VPN CIDR

```bash
# Example: Restrict to VPN subnet
aws ec2 authorize-security-group-ingress \
  --group-id sg-0d485b4ffe8c8f886 \
  --protocol tcp --port 443 --cidr 10.0.0.0/16
```

## Architecture: HTTP vs HTTPS

```
┌─────────────────────────────────────────────────┐
│  User Browser                                   │
├─────────────────────────────────────────────────┤
│  HTTP (80)          │      HTTPS (443)          │
│  Unencrypted        │      TLS encrypted        │
│        ↓            │            ↓              │
│   nginx HTTP        │       nginx HTTPS         │
│   server block      │       server block        │
└────────┬────────────┴───────────┬────────────────┘
         │                        │
         └────────┬───────────────┘
                  ↓
         ┌────────────────┐
         │  oauth2-proxy  │
         │    (:4180)     │
         └────────┬───────┘
                  ↓
         ┌────────────────┐
         │ Deploy Portal  │
         │   (:5000)      │
         └────────────────┘
```

Both HTTP and HTTPS routes:
- Use the same oauth2-proxy authentication
- Include the same application routes (via `/etc/nginx/conf.d/routes/*.conf`)
- Set appropriate `X-Forwarded-Proto` headers

## Best Practices

### Development/Testing
- ✅ Self-signed certificates are acceptable
- ✅ Use `-k` flag with curl for testing
- ✅ Accept browser certificate warnings

### Staging/Internal
- ✅ Self-signed certificates for VPC deployments
- ✅ Import certificate to client trust stores
- ✅ Use VPN for access

### Production
- ✅ Use Let's Encrypt for public-facing deployments
- ✅ Enable HSTS with long max-age
- ✅ Implement certificate monitoring
- ✅ Set up auto-renewal

## Related Documentation

- [nginx/server.conf](../nginx/server.conf) - Server configuration template
- [scripts/setup-ssl.sh](../scripts/setup-ssl.sh) - SSL certificate automation
- [scripts/configure-nginx-ssl.sh](../scripts/configure-nginx-ssl.sh) - nginx SSL configuration
- [services/framework_detector.py](../services/framework_detector.py) - SSL detection logic
- [bootstrap.sh](../bootstrap.sh) - Automated setup script

## Support

For issues or questions:
1. Check nginx error logs: `sudo tail -f /var/log/nginx/error.log`
2. Check deploy-portal logs: `sudo journalctl -u deploy-portal -f`
3. Verify SSL detection: Run the SSL detection test above
4. Review this troubleshooting guide
5. Open an issue on GitHub with logs and error messages

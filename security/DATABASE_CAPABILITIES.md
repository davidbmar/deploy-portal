# Database Container Capabilities

## Overview

Database containers require additional Linux capabilities beyond standard application containers to manage their data directories and socket files.

## Standard Application Profile

**Services:** Backend APIs, Frontend apps, Web servers, Worker processes

**Capabilities:**
- `NET_BIND_SERVICE` - Bind to network ports
- `CHOWN` - Change file ownership
- `SETUID` - Set user ID
- `SETGID` - Set group ID

## Database Profile

**Services:** PostgreSQL, MySQL, MariaDB, MongoDB, Redis, Cassandra, CouchDB, Neo4j, TimescaleDB

**Additional Capabilities:**
- `DAC_OVERRIDE` - Bypass file permission checks (needed for data directory management)
- `FOWNER` - Bypass permission checks for file ownership operations (needed for socket creation)

## Auto-Detection

The `inject-seccomp.sh` script automatically detects database services by:

### 1. Service Name Pattern
```yaml
services:
  postgres:        # ✓ Detected as database
  postgresql:      # ✓ Detected as database
  mysql:           # ✓ Detected as database
  mongo:           # ✓ Detected as database
  redis:           # ✓ Detected as database
  api-backend:     # ✗ Standard profile
  dashboard:       # ✗ Standard profile
```

### 2. Image Name Pattern
```yaml
services:
  db:
    image: postgres:16              # ✓ Detected as database
  cache:
    image: redis:alpine             # ✓ Detected as database
  database:
    image: pgvector/pgvector:pg16   # ✓ Detected as database
  app:
    image: node:20                  # ✗ Standard profile
```

## Supported Database Types

The script recognizes these database patterns:

| Database | Service Names | Image Patterns |
|----------|--------------|----------------|
| **PostgreSQL** | postgres, postgresql | postgres, pgvector, timescale |
| **MySQL** | mysql | mysql, mariadb |
| **MariaDB** | mariadb | mariadb |
| **MongoDB** | mongo, mongodb | mongo |
| **Redis** | redis | redis |
| **Cassandra** | cassandra | cassandra |
| **CockroachDB** | cockroach | cockroach |
| **CouchDB** | couchdb | couchdb |
| **Neo4j** | neo4j | neo4j |

## Why These Capabilities Are Needed

### DAC_OVERRIDE
Allows bypassing Discretionary Access Control (file read/write/execute permissions).

**Example - PostgreSQL Init:**
```bash
# PostgreSQL needs to:
chmod 0700 /var/lib/postgresql/data  # Set strict directory permissions
chown postgres:postgres /var/lib/postgresql/data  # Change ownership
```

Without `DAC_OVERRIDE`, these operations fail with "Operation not permitted"

### FOWNER
Allows bypassing ownership checks for file operations.

**Example - PostgreSQL Socket:**
```bash
# PostgreSQL creates Unix domain socket:
/var/run/postgresql/.s.PGSQL.5432
chown postgres:postgres /var/run/postgresql
chmod 0755 /var/run/postgresql
```

Without `FOWNER`, socket creation fails with permission errors.

## Troubleshooting

### Container Fails to Start After Applying Seccomp

**Symptom:**
```
postgres-1  | chmod: changing permissions of '/var/lib/postgresql/data': Operation not permitted
```

**Solution:**
Ensure the database service has both `DAC_OVERRIDE` and `FOWNER` capabilities:

```yaml
services:
  postgres:
    cap_add:
      - NET_BIND_SERVICE
      - CHOWN
      - SETUID
      - SETGID
      - DAC_OVERRIDE   # ← Required for databases
      - FOWNER         # ← Required for databases
```

### Adding Custom Database Detection

If you have a custom database that isn't auto-detected, update the `is_database_service()` function in `inject-seccomp.sh`:

```bash
is_database_service() {
    local service_name="$1"
    local compose_file="$2"
    
    # Add your custom database name here
    if echo "$service_name" | grep -qiE '^(postgres|mysql|mongo|your-custom-db)'; then
        return 0
    fi
    
    # Add your custom image pattern here
    local image=$(yq eval ".services.$service_name.image" "$compose_file" 2>/dev/null || echo "")
    if echo "$image" | grep -qiE '(postgres|mysql|mongo|your-custom-image)'; then
        return 0
    fi
    
    return 1
}
```

## Testing

After applying seccomp profiles, verify database containers start correctly:

```bash
# Check container status
docker-compose ps

# Check for permission errors in logs
docker-compose logs database | grep -i permission

# Verify capabilities are applied
docker inspect <container-name> --format '{{.HostConfig.CapAdd}}'
```

Expected output for database containers:
```
[NET_BIND_SERVICE CHOWN SETUID SETGID DAC_OVERRIDE FOWNER]
```

## Security Considerations

While `DAC_OVERRIDE` and `FOWNER` provide elevated filesystem access, they are:

1. **Still restricted by seccomp** - Only whitelisted syscalls are allowed
2. **Container-scoped** - Cannot affect host filesystem
3. **No privilege escalation** - `no-new-privileges:true` prevents gaining additional privileges
4. **Standard for databases** - These capabilities are required by production database containers

## References

- [Linux Capabilities](https://man7.org/linux/man-pages/man7/capabilities.7.html)
- [Docker Security Best Practices](https://docs.docker.com/engine/security/)
- [PostgreSQL Container Requirements](https://github.com/docker-library/postgres)
- [MySQL Container Requirements](https://github.com/docker-library/mysql)

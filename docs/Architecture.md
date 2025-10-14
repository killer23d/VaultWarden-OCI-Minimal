# Architecture Documentation

## Overview

VaultWarden-OCI-Minimal is designed as a production-ready, small-scale password management solution with enterprise-grade reliability built for teams of 10 or fewer users. The architecture prioritizes simplicity, security, and automation while avoiding over-engineering.

## Core Design Principles

### 1. Dynamic Configuration
- **Zero Hardcoding**: All paths, names, and identifiers are computed at runtime
- **Project Identity**: Derived from the root directory name
- **Portability**: Complete project can be renamed/moved without configuration changes
- **Environment Adaptation**: Automatically adapts to different deployment environments

### 2. Library-First Architecture
- **Modular Design**: Core functionality split into reusable libraries
- **Separation of Concerns**: Clear boundaries between configuration, logging, validation, etc.
- **Code Reuse**: Common functions shared across all scripts
- **Testing**: Each library can be tested independently

### 3. Security by Design
- **Principle of Least Privilege**: Minimal required permissions
- **Secure Defaults**: Safe configuration out of the box  
- **Defense in Depth**: Multiple security layers (firewall, fail2ban, SSL, etc.)
- **Secret Management**: Proper handling of sensitive data

### 4. Automation First
- **Set and Forget**: Minimal manual intervention required
- **Self-Healing**: Automatic recovery from common failures
- **Comprehensive Monitoring**: Proactive issue detection
- **Maintenance Automation**: Scheduled tasks for all routine operations

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Internet/Cloudflare                      │
└─────────────────────────┬───────────────────────────────────────┘
                          │ HTTPS (443) / HTTP (80)
                          │
┌─────────────────────────▼───────────────────────────────────────┐
│                    Ubuntu 24.04 Host                           │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                  Docker Network                         │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │    │
│  │  │    Caddy    │  │ VaultWarden │  │  Fail2ban   │    │    │
│  │  │  (Proxy)    │◄─┤ (Password   │  │ (Security)  │    │    │
│  │  │             │  │  Manager)   │  │             │    │    │
│  │  └─────────────┘  └─────────────┘  └─────────────┘    │    │
│  │        │                 │               │            │    │
│  │  ┌─────────────┐  ┌─────────────┐       │            │    │
│  │  │ Watchtower  │  │  DDClient   │       │            │    │
│  │  │ (Updates)   │  │   (DDNS)    │       │            │    │
│  │  └─────────────┘  └─────────────┘       │            │    │
│  └──────────────────────────────────────────┼────────────┘    │
│                                             │                 │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │              Host Services                              │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │  │
│  │  │    UFW      │  │    Cron     │  │   Docker    │    │  │
│  │  │ (Firewall)  │  │ (Scheduler) │  │  (Runtime)  │    │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘    │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │                Data Storage                             │  │
│  │  /var/lib/{project-name}/                              │  │
│  │  ├── data/bwdata/        (VaultWarden database)        │  │
│  │  ├── logs/               (Service logs)                │  │
│  │  ├── backups/            (Automated backups)           │  │
│  │  ├── caddy_data/         (SSL certificates)            │  │
│  │  └── caddy_config/       (Caddy configuration)         │  │
│  └─────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Component Architecture

### Container Stack

#### VaultWarden (Core Service)
- **Purpose**: Password manager and web interface
- **Image**: `vaultwarden/server:latest`
- **Resources**: 512MB RAM, 1 CPU
- **Data**: SQLite database in `/data/db.sqlite3`
- **Features**: Web UI, REST API, WebSocket support (optional)
- **Health**: HTTP endpoint check on port 8080

#### Caddy (Reverse Proxy)
- **Purpose**: SSL termination, reverse proxy, security headers
- **Image**: `caddy:2`
- **Resources**: 256MB RAM, 0.5 CPU  
- **Ports**: 80 (HTTP), 443 (HTTPS)
- **Features**: Automatic SSL, Cloudflare IP filtering, security headers
- **Health**: Metrics endpoint on port 2019

#### Fail2ban (Security)
- **Purpose**: Intrusion detection and IP blocking
- **Image**: `crazymax/fail2ban:latest`
- **Resources**: 128MB RAM, 0.25 CPU
- **Network**: Host network for iptables access
- **Features**: Log analysis, automatic IP banning, Cloudflare integration
- **Data**: Ban database and configuration

#### Watchtower (Maintenance)
- **Purpose**: Automated container updates
- **Image**: `containrrr/watchtower:latest`
- **Resources**: 128MB RAM, 0.25 CPU
- **Schedule**: Monthly (first Monday at 4 AM)
- **Features**: Rolling updates, email notifications, label-based targeting
- **Safety**: Only updates labeled containers

#### DDClient (Optional)
- **Purpose**: Dynamic DNS updates
- **Image**: `lscr.io/linuxserver/ddclient:latest`
- **Resources**: 64MB RAM, 0.1 CPU
- **Enabled**: Via `DDCLIENT_ENABLED` configuration
- **Providers**: Cloudflare, other DDNS providers
- **Health**: Process and configuration file checks

### Library System

#### lib/config.sh (Configuration Management)
```bash
# Core Functions
_load_configuration()        # Load from OCI Vault or local file
_export_configuration()      # Export to environment variables
_get_config_value()         # Retrieve specific configuration values
_validate_configuration()    # Validate configuration completeness
_backup_current_config()    # Create configuration backups

# Dynamic Path Generation
PROJECT_NAME                 # Computed from directory name
PROJECT_STATE_DIR           # /var/lib/{project-name}
SERVICE_NAME                # {project-name}.service
```

#### lib/system.sh (System Operations)
```bash
# Package Management
_install_package()          # Install system packages
_update_package_index()     # Update package repositories
_validate_package()         # Check if package is installed

# Service Management  
_enable_service()           # Enable systemd services
_start_service()            # Start systemd services
_restart_service()          # Restart systemd services

# File Operations
_create_directory_secure()  # Create directories with proper permissions
_create_file_secure()       # Create files with secure permissions
_backup_file()             # Create timestamped backups
```

## Security Architecture

### Access Control Layer
```
Internet → Cloudflare → UFW → Caddy → VaultWarden
    │         │         │      │         │
    │         │         │      │         └─ Application-level auth
    │         │         │      └─ SSL/TLS termination
    │         │         └─ Host firewall (UFW)
    │         └─ DDoS protection, WAF
    └─ DNS resolution, CDN
```

### File System Security
```
/var/lib/{project-name}/     (755, root:root)
├── data/                    (755, 33:33)     # VaultWarden user
├── logs/                    (755, root:root)
├── backups/                 (700, root:root) # Sensitive data
├── caddy_data/             (755, root:root)
└── caddy_config/           (755, root:root)

/project-root/
├── settings.json           (600, root:root) # Sensitive config
├── lib/                    (755, root:root)
├── tools/                  (755, root:root)
└── *.sh                    (755, root:root)
```

## Key Architectural Decisions

### 1. SQLite vs PostgreSQL
**Decision**: SQLite for small teams (≤10 users)
**Rationale**: 
- Simplicity: No separate database server to manage
- Performance: Excellent for read-heavy workloads with low concurrency
- Backup: Simple file-based backups
- Resources: Minimal memory and CPU overhead

### 2. Caddy vs Nginx/Apache
**Decision**: Caddy as reverse proxy
**Rationale**:
- Automatic SSL: Let's Encrypt integration out of the box
- Configuration: Simple, human-readable config files
- Security: Modern defaults, easy security header configuration
- Cloudflare: Built-in support for IP filtering

### 3. Docker Compose vs Kubernetes
**Decision**: Docker Compose for orchestration
**Rationale**:
- Simplicity: Single-host deployment model
- Resource Efficiency: Lower overhead than K8s
- Maintenance: Easier troubleshooting and updates
- Learning Curve: Accessible to small team administrators

### 4. Local vs Cloud Configuration
**Decision**: Hybrid approach (local file + OCI Vault option)
**Rationale**:
- Flexibility: Works in air-gapped and cloud environments
- Security: Local files for basic setups, vault for enterprise
- Reliability: Automatic fallback to local configuration
- Portability: No cloud vendor lock-in

## Performance Characteristics

### Resource Utilization (Typical)
```
Container          CPU     Memory   Storage
VaultWarden       5-15%    100-300MB   <100MB (DB)
Caddy             1-5%     50-100MB    <50MB (configs)
Fail2ban          1-3%     30-60MB     <20MB (logs)
Watchtower        <1%      20-40MB     <10MB
DDClient          <1%      10-20MB     <5MB

Total System      10-25%   210-520MB   ~200MB
```

### Scalability Limits
- **Users**: 10-15 concurrent users (web interface)
- **Vaults**: 100+ vaults per user
- **Items**: 1000+ items per vault  
- **Database**: 100MB+ database size supported
- **Traffic**: 100+ requests per minute

### Performance Tuning
- **Database**: Regular SQLite VACUUM operations
- **Logs**: Automatic rotation and cleanup
- **Resources**: Container resource limits prevent starvation
- **Caching**: Caddy provides efficient static asset caching

## Disaster Recovery

### Backup Strategy
1. **Database Backups**: Daily, multiple formats (binary, SQL, JSON)
2. **Configuration Backups**: Before each change
3. **Full System Backups**: Weekly complete archives
4. **Off-site Storage**: Integration with cloud providers

### Recovery Procedures
1. **Service Recovery**: Automatic restart via monitoring
2. **Data Recovery**: Restore from latest backup
3. **Full System Recovery**: Rebuild from backup archive
4. **Disaster Recovery**: Deploy to new infrastructure

### Recovery Time Objectives
- **Service Restart**: < 5 minutes (automatic)
- **Data Restore**: < 30 minutes (manual)
- **Full Recovery**: < 2 hours (includes new infrastructure)
- **Disaster Recovery**: < 4 hours (new region deployment)

## Monitoring and Observability

### Health Check Hierarchy
```
Level 1: Container Health (30s intervals)
├── HTTP endpoint checks
├── Process validation
├── Resource utilization
└── Log file analysis

Level 2: Service Functionality (5min intervals)
├── Authentication tests
├── Database connectivity
├── SSL certificate validity
└── Proxy functionality

Level 3: System Resources (5min intervals)
├── Disk space monitoring
├── Memory usage tracking
├── CPU load analysis
└── Network connectivity

Level 4: External Dependencies (15min intervals)
├── DNS resolution tests
├── SMTP server connectivity
├── OCI Vault accessibility
└── Container registry access
```

### Alerting Strategy
- **Critical**: Immediate email alerts (service failures)
- **Warning**: Daily digest emails (resource usage)
- **Info**: Weekly reports (system health summary)
- **Debug**: Log files only (detailed troubleshooting)

## Security Model

### Threat Model
**Protected Against**:
- Brute force attacks (fail2ban)
- DDoS attacks (Cloudflare)
- Unauthorized access (authentication)
- Data interception (SSL/TLS)
- Configuration exposure (file permissions)

**Assumptions**:
- Host system is trusted and secure
- Network infrastructure is reasonably secure
- Users follow basic security practices
- Regular updates are applied

### Security Controls
1. **Network Security**: Firewall, DDoS protection, IP filtering
2. **Application Security**: Authentication, authorization, session management
3. **Data Security**: Encryption at rest and in transit
4. **Infrastructure Security**: Container isolation, resource limits
5. **Operational Security**: Secure defaults, audit logging

## Maintenance and Operations

### Automated Tasks
- **Daily**: Database backups, log rotation, health checks
- **Weekly**: Full system backups, security updates
- **Monthly**: Container updates, certificate renewal checks
- **Quarterly**: Security audit, performance review

### Manual Operations
- **Configuration Changes**: Via settings.json or OCI Vault
- **Troubleshooting**: Log analysis, service restart
- **Upgrades**: Major version updates (VaultWarden, containers)
- **Disaster Recovery**: Backup restoration, system rebuild

### Operational Procedures
1. **Change Management**: Backup before changes, validation after
2. **Incident Response**: Automated recovery, escalation procedures
3. **Capacity Planning**: Resource monitoring, growth projections
4. **Security Management**: Regular updates, vulnerability scanning

This architecture successfully balances simplicity with robustness, making it an ideal solution for small team VaultWarden deployments while maintaining production-grade reliability and security standards.

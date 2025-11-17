# MD Handler Configuration Guide

This document explains the configuration structure for the MD Handler application, which consists of two servers: a main content server and an admin management server.

## Configuration Architecture

The MD Handler uses a shared `ConfigReader` base class that supports configuration from multiple sources in the following priority order:

1. **Command Line Arguments** (highest priority)
2. **Environment Variables**
3. **Configuration Files** (JSON)
4. **Default Values** (lowest priority)

## Main Server Configuration

The main server handles markdown file serving and processing.

### Configuration Sources

| Source | Key | Environment Variable | CLI Argument | Default | Description |
|--------|-----|---------------------|--------------|---------|-------------|
| Port | `port` | `PORT` | `--port`, `-p` | `8080` | HTTP server port |
| Base Path | `basePath` | `BASE_PATH` | `--base-path`, `-b` | `process.cwd()` | Root directory for content |
| Host | `host` | `HOST` | `--host`, `-h` | `0.0.0.0` | Server bind address |

### Example config.json
```json
{
  "port": 8081,
  "basePath": "/materials",
  "host": "0.0.0.0"
}
```

## Admin Server Configuration

The admin server provides a management interface for template configuration.

### Configuration Sources

All admin configuration keys use the `admin-` prefix to avoid conflicts with main server config.

| Source | Key | Environment Variable | CLI Argument | Default | Description |
|--------|-----|---------------------|--------------|---------|-------------|
| Port | `admin-port` | `ADMIN_PORT` | `--admin-port` | `8082` | Admin server port |
| Host | `admin-host` | `ADMIN_HOST` | `--admin-host` | `0.0.0.0` | Admin server bind address |
| Template File | `admin-templateFile` | `TEMPLATE_FILE` | `--template-file` | `template.json` | Template variables file path |

### Template Variables

The admin server manages a simple template variables file (`template.json`) that contains variables used in markdown processing:

- **Variables**: Key-value pairs for template substitution in markdown files
- **Usage**: Variables can be referenced in markdown using `{{variableName}}` syntax

### Example template.json

```json
{
  "variables": {
    "title": "Integration Jam Materials",
    "author": "IBM Cloud Pak for Integration", 
    "date": "2025-11-10",
    "version": "1.0.0",
    "organization": "IBM",
    "description": "Training materials for IBM Cloud Pak for Integration",
    "contact": "support@ibm.com",
    "baseUrl": "/materials",
    "logoUrl": "/public/ibm-logo.png"
  }
}
```

## Kubernetes Deployment Configuration

### ConfigMap Structure

The Kubernetes deployment includes a ConfigMap with both configuration files:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-md-handler-config
data:
  config.json: |
    {
      "port": 8081,
      "basePath": "/materials",
      "host": "0.0.0.0",
      "admin-port": 8082,
      "admin-host": "0.0.0.0",
      "admin-templateFile": "template.json"
    }
  template.json: |
    {
      "variables": { ... }
    }
```

### Environment Variables

The deployment sets environment variables for both servers:

```yaml
env:
- name: PORT
  value: "8081"
- name: BASE_PATH
  value: "/materials"
- name: ADMIN_PORT
  value: "8082"
```

## Usage Examples

### Starting with CLI Arguments
```bash
# Main server only
node src/index.js --port 8080 --base-path ./materials

# With admin server
node src/index.js --port 8080 --admin-port 8082 --admin-config-file ./admin-config.json
```

### Using Environment Variables
```bash
export PORT=8081
export BASE_PATH=/materials
export ADMIN_PORT=8082
export TEMPLATE_CONFIG_FILE=/config/admin-config.json
node src/index.js
```

### Configuration File Only
Create `config.json` with all settings and run:
```bash
node src/index.js
```

## Admin API Endpoints

The admin server exposes the following endpoints:

- `GET /health` - Health check
- `GET /config` - Get current template configuration
- `POST /config` - Update template configuration
- `GET /` - Admin interface documentation

## File Locations in Kubernetes

- Main config: `/app/config/config.json`
- Admin config: `/app/config/admin-config.json`
- Materials: `/materials` (PVC mount)
- Working directory: `/app`

## Troubleshooting

1. **Port conflicts**: Ensure main and admin ports don't conflict
2. **File permissions**: Config files must be readable by the node process
3. **Path resolution**: Use absolute paths in Kubernetes environments
4. **Environment precedence**: CLI args override env vars, which override config files
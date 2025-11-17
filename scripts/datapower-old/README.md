# Tech Jam DataPower Management Scripts

This repository contains automation scripts for managing IBM DataPower Gateway
environments. The main entry point is `script-runner.sh`, which provides a
framework for executing various DataPower management tasks across multiple
gateway instances.

## Prerequisites

- SSH access to DataPower Gateway instances
- REST Management Interface access to DataPower Gateways
- `curl` and `jq` utilities installed
- Bash shell environment

## Quick Start

1. **Configure Environment**: Copy `env/example` to `env/<your-env-name>` and
   customize:

   ```bash
   cp env/example env/production
   # Edit env/production with your gateway details
   ```

2. **Basic Usage**:

   ```bash
   ./script-runner.sh <command> --env=<env-name> [options]
   ```

## Environment Configuration

Create environment files in the `env/` directory. Each environment file
should define:

- `BASE_DOMAIN`: Base domain for DataPower gateways
- `HOSTS`: Array of gateway hostnames
- `ADMIN_USER`: DataPower admin username  
- `ADMIN_PASS`: DataPower admin password

### Environment File Example

```bash
#!/bin/bash

# Base domain for the DataPower gateways
BASE_DOMAIN='mycompany.com'

# Gateway hostnames (supports various formats)
# Format options:
#   hostname                    -- default ports (SSH:22, REST:5554)
#   hostname:port               -- custom SSH port, default REST port
#   ssh-host/rest-host          -- different SSH and REST hostnames
#   ssh-host:port/rest-host:port -- custom ports for both
HOSTS=(gateway1 gateway2:9022/rest-gateway2)

# DataPower credentials
ADMIN_USER="admin"
ADMIN_PASS="your-password-here"
```

## Available Commands

### setup

FILL IN

**Usage:**

```bash
./script-runner.sh setup --env=jb
```

**Parameters:**

none

**What it does:**

Sets up everything needed for the jam in a box

- Sets up SSH admin
- Sets up console

**Example:**

```bash
./script-runner.sh jb-setup --env=jb
```

### reset

Removes settings for the jam in a box

**Usage:**

```bash
./script-runner.sh reset
```

**Parameters:**

none

**What it does:**

- Disables console
- Disables SSH admin

**Example:**

```bash
./script-runner.sh reset
```

## Global Options

- `--env=<name>` (required): Specifies which environment configuration to
  use
- `--debug`: Enables verbose output showing all commands and responses
- `--help, -h`: Displays usage information

## Host Name Formats

The `HOSTS` array in environment files supports flexible hostname formats:

| Format | Description | SSH Port | REST Port |
|--------|-------------|----------|-----------|
| `gateway1` | Simple hostname | 22 | 5554 |
| `gateway1:9022/gateway1` | Custom SSH port | 9022 | 5554 |
| `ssh-gw1/rest-gw1` | Different SSH/REST hosts | 22 | 5554 |
| `ssh-gw1:9022/rest-gw1:9554` | Custom ports for both | 9022 | 9554 |

All hostnames are automatically suffixed with the `BASE_DOMAIN`.

## Script Architecture

The framework consists of:

- **script-runner.sh**: Main orchestration script
- **env/**: Environment-specific configurations
- **scripts/**: Individual command implementations
- **scripts/abstract-script.sh**: Common functions for script development

### Adding Custom Commands

1. Create a new script in `scripts/<command-name>.sh`
2. Implement required functions:
   - `readParams()`: Parse command-line arguments
   - `dataPowerScript()`: Generate DataPower CLI commands
   - Optional: `beforeAllHosts()`, `afterAllHosts()`, `beforeEachHost()`,
     `afterEachHost()`

3. Use the script:

   ```bash
   ./script-runner.sh <command-name> --env=<env-name>
   ```

## Security Considerations

- Store passwords securely (consider using secrets management)
- Use SSH key authentication where possible
- Limit REST interface IP binding in production
- Review generated DataPower commands before execution in production

## Troubleshooting

### Common Issues

1. **SSH Connection Failed**: Check SSH connectivity and credentials
2. **REST API Errors**: Verify REST interface is enabled and credentials
   are correct
3. **Command Not Found**: Ensure script file exists in `scripts/` directory
4. **Environment Not Found**: Check environment file exists in `env/`
   directory

### Debug Mode

Use `--debug` flag to see detailed execution information:

```bash
./script-runner.sh add-debug --env=production --mpgw=MyGW --debug
```

This will show:

- Generated DataPower CLI commands
- REST API requests and responses
- SSH connection details

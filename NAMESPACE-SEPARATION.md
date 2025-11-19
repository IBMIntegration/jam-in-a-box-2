# Namespace Separation Guide

## Overview

This integration-jam-in-a-box project uses separate namespaces to isolate CloudPak for Integration components from jam-in-a-box educational resources:

- **`tools` namespace**: CloudPak for Integration components (DO NOT MODIFY)
- **`jam-in-a-box` namespace**: All jam-in-a-box educational components

## Usage

Simply deploy with the updated scripts - they now automatically use the correct namespaces:

```bash
# Deploy with separated namespaces
./main.sh --clean --start-here-app-password=jam
```

## What Changed

- **main.sh**: Now creates and uses `jam-in-a-box` namespace automatically
- **start-here-app.sh**: Defaults to `jam-in-a-box` namespace
- **jb-datapower.sh**: Creates config in `jam-in-a-box`, patches CloudPak in `tools`

## Resources by Namespace

### `tools` namespace (CloudPak - DO NOT TOUCH)

- APIConnectCluster `apim-demo`
- GatewayCluster `apim-demo-gw`
- Cloud Pak Navigator
- All IBM Cloud Pak operators and services

### `jam-in-a-box` namespace (Your Components)

- Start Here App (`jb-start-here`)
- MD Handler (`jb-start-here-md-handler`)
- DataPower configuration (`jb-datapower-config`)
- Setup output and secrets

## Verification

To verify the separation works correctly:

```bash
# Deploy to separated namespaces
./main.sh --clean --start-here-app-password=jam

# Verify resources are in correct namespaces
oc get all -n jam-in-a-box
oc get all -n tools | grep -E "jb-|jam"  # Should be empty
```
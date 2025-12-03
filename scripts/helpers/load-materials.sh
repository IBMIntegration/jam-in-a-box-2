#!/bin/bash

# This script checks if there are already materials in the /materials folder,
# and if not, clones the default materials from the GitHub repository.

# It assumes all necessary environment varialbes are set as this is the
# responsibility of the deployment that runs this script.

set -e

if [ -d "/materials/." ] && [ "$(ls -A /materials)" ]; then
  echo "==> Materials already exist in /materials, skipping clone."
else
  echo "==> Cloning default materials into /materials..."
  git clone "${MATERIALS_GIT_URL}" /materials
fi

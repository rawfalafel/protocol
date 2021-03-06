#!/usr/bin/env bash
set -e

# Usage:
# REACT_APP_MODE=default ./scripts/deploy_dapp.sh <your_file.yaml> <additional_args_for_gcloud_app_deploy>

# If you'd like to deploy the monitoring dapp:
# REACT_APP_MODE=monitoring ./scripts/deploy_dapp.sh <your_file.yaml> <additional_args_for_gcloud_app_deploy>

# Note: you must have the gcloud CLI tool installed and authenticated before using this script.

# Get the absolute path of a file.
# Credit: https://stackoverflow.com/a/21188136
get_abs_filename() {
  # $1 : relative filename
  echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
}

# Grab the absolute path for the provided file.
APP_YAML_PATH=$(get_abs_filename $1)
PROTOCOL_DIR=$(pwd)

# Shift the arguments to provide to gcloud app deploy.
shift

# Move to the core directory for contract compilation.
cd $PROTOCOL_DIR/core

# Compile contracts, load deployed addresses for mainnet and ropsten.
echo "Compiling contracts."
$(npm bin)/truffle compile

# Turn on custom error handling while calling apply-registry.
set +e

# Apply the registry - since the registry doesn't produce a nonzero error code, we have to grep the printout for
# errors.
echo "Applying saved deployments to truffle artifacts."
APPLY_REGISTRY_OUTPUT=$($(npm bin)/apply-registry)
NUM_FAILURES=$(echo $APPLY_REGISTRY_OUTPUT | grep -ci "missing")
echo "$APPLY_REGISTRY_OUTPUT"
if [ $NUM_FAILURES -ne 0 ]
then
    # If we found failures, exit.
    echo "Aborting because no persistent deployment artifacts were found (the networks/ dir is empty or doesn't exist)."
    exit 1
fi

# Disable special error handling - exit on nonzero exit code.
set -e

# Link the contracts dir to the dapp dir and build the dapp.
cd $PROTOCOL_DIR/sponsor-dapp
echo "Linking contracts to dapp."
npm run link-contracts
echo "Building dapp."
npm run build

# Make sure to cleanup the temp directory for any exits after this line.
function cleanup() {
  local protocol_directory=$1
  # Clean up temporary directory.
  echo "Cleaning up."
  cd $protocol_directory
  rm -rf $protocol_directory/sponsor-dapp/.gae_deploy
}
trap "cleanup $PROTOCOL_DIR" EXIT

# Make a temporary directory to isolate the files to upload to GAE.
# Note: otherwise, it will attempt to upload all files in all subdirectories.
echo "Copying dapp build to temporary directory."
mkdir -p .gae_deploy
cp -R build .gae_deploy/
cp -R $APP_YAML_PATH .gae_deploy/app.yaml
cd .gae_deploy

# Run gcloud app deploy to deploy.
gcloud app deploy "$@"

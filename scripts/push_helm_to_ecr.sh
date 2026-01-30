#!/bin/bash
set -e

# Validate required environment variables
if [ -z "$GITHUB_TOKEN" ]; then
  echo "Error: GITHUB_TOKEN is not set."
  exit 1
fi

if [ -z "$ORGID" ]; then
  echo "Error: ORGID is not set."
  exit 1
fi

if [ -z "$PACKAGE" ]; then
  echo "Error: PACKAGE is not set."
  exit 1
fi

if [ -z "$VERSION" ]; then
  echo "Error: VERSION is not set."
  exit 1
fi

if [ -z "$REGISTRY" ]; then
  echo "Error: REGISTRY is not set."
  exit 1
fi

# Login to GitHub Container Registry
echo "Logging into GitHub Container Registry..."
echo "$GITHUB_TOKEN" | helm registry login ghcr.io --username "$GITHUB_ACTOR" --password-stdin

# Pull the Helm chart from GHCR
# Package is stored as oci://ghcr.io/PACKAGE
SOURCE_URI="oci://ghcr.io/${PACKAGE}"

echo "Pulling Helm chart from ${SOURCE_URI} with version ${VERSION}..."
helm pull "${SOURCE_URI}" --version "${VERSION}"

# The pulled file will be named based on the chart name and version
CHART_FILE="${CHART_ARCHIVE}-${VERSION}.tgz"

if [ ! -f "$CHART_FILE" ]; then
  echo "Error: Expected chart file $CHART_FILE not found after pull."
  echo "Listing current directory:"
  ls -la
  exit 1
fi

echo "Pushing Helm chart to ECR: oci://${REGISTRY}..."
helm push "$CHART_FILE" "oci://${REGISTRY}"

echo "Successfully pushed $CHART_FILE to oci://${REGISTRY}"

#!/bin/bash
set -e

# Validate required environment variables
if [ -z "$GITHUB_TOKEN" ]; then
  echo "Error: GITHUB_TOKEN is not set."
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

if [ -z "$DOCKERHUB_USERNAME" ]; then
  echo "Error: DOCKERHUB_USERNAME is not set."
  exit 1
fi

if [ -z "$DOCKERHUB_TOKEN" ]; then
  echo "Error: DOCKERHUB_TOKEN is not set."
  exit 1
fi

TARGET_REPO="${REPOSITORY:-$DOCKERHUB_USERNAME}"
if [ "$TARGET_REPO" == "platform" ]; then
  TARGET_REPO="$DOCKERHUB_USERNAME"
fi

# Login to GitHub Container Registry
echo "Logging into GitHub Container Registry..."
helm registry login ghcr.io --username "$GITHUB_ACTOR" --password-stdin <<< "$GITHUB_TOKEN"

# Pull the Helm chart from GHCR
SOURCE_URI="oci://ghcr.io/${PACKAGE}"

echo "Pulling Helm chart from ${SOURCE_URI} with version ${VERSION}..."
helm pull "${SOURCE_URI}" --version "${VERSION}"

CHART_FILE="${CHART_ARCHIVE}"

if [ ! -f "$CHART_FILE" ]; then
  echo "Error: Expected chart file $CHART_FILE not found after pull."
  echo "Listing current directory:"
  ls -la
  exit 1
fi

# Login to Docker Hub
echo "Logging into Docker Hub..."
helm registry login registry-1.docker.io --username "$DOCKERHUB_USERNAME" --password-stdin <<< "$DOCKERHUB_TOKEN"

# Push Helm chart to Docker Hub
# Helm push to oci://registry-1.docker.io/TARGET_REPO will push to oci://registry-1.docker.io/TARGET_REPO/CHART_NAME
echo "Pushing Helm chart to Docker Hub: oci://registry-1.docker.io/${TARGET_REPO}..."
helm push "$CHART_FILE" "oci://registry-1.docker.io/${TARGET_REPO}"

echo "Successfully pushed $CHART_FILE to oci://registry-1.docker.io/${TARGET_REPO}"

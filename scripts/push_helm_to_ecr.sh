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

if [ -z "$REGISTRY" ]; then
  echo "Error: REGISTRY is not set."
  exit 1
fi

if [ -z "$REPOSITORY" ]; then
  echo "Error: REPOSITORY is not set."
  exit 1
fi

if [ -z "$REGION" ]; then
  echo "Error: REGION is not set."
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
CHART_FILE="${CHART_ARCHIVE}"

if [ ! -f "$CHART_FILE" ]; then
  echo "Error: Expected chart file $CHART_FILE not found after pull."
  echo "Listing current directory:"
  ls -la
  exit 1
fi


# Check if ECR repository exists and create if not
# Helm push to oci://REGISTRY/REPOSITORY will push to oci://REGISTRY/REPOSITORY/CHART_NAME
# So the actual ECR repository we need to create is REPOSITORY/CHART_NAME

# Extract chart name from CHART_ARCHIVE (removing .tgz and version)
CHART_BASENAME="${CHART_ARCHIVE%.tgz}"
CHART_NAME="${CHART_BASENAME%-$VERSION}"

ECR_REPO_NAME="${REPOSITORY}/${CHART_NAME}"

echo "Checking if ECR repository $ECR_REPO_NAME exists..."
if ! aws ecr describe-repositories --repository-names "$ECR_REPO_NAME" --region "$REGION" >/dev/null 2>&1; then
  echo "Repository $ECR_REPO_NAME does not exist. Creating..."
  aws ecr create-repository --repository-name "$ECR_REPO_NAME" --region "$REGION" --tags "Key=orgid,Value=$ORGID" "Key=appid,Value=$APPID" "Key=buid,Value=$BUID"
  echo "Repository $ECR_REPO_NAME created."
else
  echo "Repository $ECR_REPO_NAME already exists."
fi

echo "Pushing Helm chart to ECR: oci://${REGISTRY}/${REPOSITORY}..."
helm push "$CHART_FILE" "oci://${REGISTRY}/${REPOSITORY}"

echo "Successfully pushed $CHART_FILE to oci://${REGISTRY}/${REPOSITORY}"

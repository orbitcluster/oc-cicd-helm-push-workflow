#!/bin/bash
set -e

# Validate required environment variables
if [ -z "$BRANCH_NAME" ]; then
  echo "Error: BRANCH_NAME is not set."
  exit 1
fi

if [ -z "$REPOSITORY" ]; then
  echo "Error: REPOSITORY is not set."
  exit 1
fi

if [ -z "$CHART_ARCHIVE" ]; then
  echo "Error: CHART_ARCHIVE is not set."
  exit 1
fi

if [ -z "$REGION" ]; then
  echo "Error: REGION is not set."
  exit 1
fi

if [ -z "$VERSION" ]; then
    echo "Error: VERSION is not set."
    exit 1
fi

# Sanitize branch name (replace / with -) to match potential tag formatting
# This assumes the version generation logic uses a similar sanitization
SAFE_BRANCH_NAME=${BRANCH_NAME//\//-}
echo "Cleaning up Helm charts for branch: $BRANCH_NAME (safe: $SAFE_BRANCH_NAME)"

# Derive ECR Repository Name
# Same logic as push_helm_to_ecr.sh
CHART_BASENAME="${CHART_ARCHIVE%.tgz}"
CHART_NAME="${CHART_BASENAME%-$VERSION}"
ECR_REPO_NAME="${REPOSITORY}/${CHART_NAME}"

echo "Target ECR Repository: $ECR_REPO_NAME"

# List images containing the branch name
# using JMESPath to filter.
# Tag pattern usually: version-branch.build or similar.
# We look for the safe branch name in the imageTag.

echo "Finding images..."
IMAGE_DIGESTS=$(aws ecr list-images --repository-name "$ECR_REPO_NAME" --region "$REGION" \
    --query "imageIds[?imageTag!=null && contains(imageTag, '${SAFE_BRANCH_NAME}')].imageDigest" \
    --output text)

if [ -z "$IMAGE_DIGESTS" ]; then
    echo "No images found for branch $BRANCH_NAME in ECR."
else
    echo "Found images to delete:"
    echo "$IMAGE_DIGESTS"

    # Convert space-delimited digests to format needed for batch-delete-image
    DELETE_ARGS=""
    for digest in $IMAGE_DIGESTS; do
        DELETE_ARGS="$DELETE_ARGS imageDigest=$digest"
    done

    echo "Deleting images..."
    aws ecr batch-delete-image --repository-name "$ECR_REPO_NAME" --region "$REGION" --image-ids $DELETE_ARGS

    echo "ECR Cleanup complete."
fi

# ------------------------------------------------------------------
# GHCR Cleanup Logic
# ------------------------------------------------------------------

if [ -z "$GITHUB_TOKEN" ]; then
  echo "GITHUB_TOKEN is not set. Skipping GHCR cleanup."
  exit 0
fi

if [ -z "$PACKAGE" ]; then
  echo "PACKAGE is not set. Skipping GHCR cleanup."
  exit 0
fi

echo "Starting GHCR cleanup for package: $PACKAGE"

# PACKAGE format is expected to be "owner/image-name" (or with sub-paths)
# e.g. "orbitcluster/oc-helm-kubernetes-services/k8s-service"
# We need to split this into OWNER and the rest (IMAGE_NAME)
OWNER=$(echo "$PACKAGE" | cut -d'/' -f1)
IMAGE_NAME=$(echo "$PACKAGE" | cut -d'/' -f2-)

# URL Encode the image name for the API (replace / with %2F)
ENCODED_IMAGE_NAME=${IMAGE_NAME//\//%2f}

echo "Detected Owner: $OWNER"
echo "Detected Image Name: $IMAGE_NAME (Encoded: $ENCODED_IMAGE_NAME)"

# Determine if this is an Organization or User package
# We check access to the Org endpoint first.
API_PREFIX="/orgs/$OWNER"
if ! gh api "$API_PREFIX/packages/container/$ENCODED_IMAGE_NAME/versions" -H "Accept: application/vnd.github+json" --silent >/dev/null 2>&1; then
  echo "Package not found in Org endpoint, checking User endpoint..."
  API_PREFIX="/users/$OWNER"
fi

echo "Listing GHCR versions matching branch tag '${SAFE_BRANCH_NAME}'..."

# List versions and filter by tag
# We use jq to select versions where any tag contains the SAFE_BRANCH_NAME
# Note: handling null tags gracefully
VERSION_IDS=$(gh api "$API_PREFIX/packages/container/$ENCODED_IMAGE_NAME/versions" \
  -H "Accept: application/vnd.github+json" \
  --jq ".[] | select(.metadata.container.tags != null) | select(any(.metadata.container.tags[]; contains(\"$SAFE_BRANCH_NAME\"))) | .id")

if [ -z "$VERSION_IDS" ]; then
  echo "No GHCR versions found for branch $BRANCH_NAME."
else
  echo "Found matching versions. Deleting..."
  for vid in $VERSION_IDS; do
    echo "Deleting GHCR version ID: $vid"
    if gh api --method DELETE "$API_PREFIX/packages/container/$ENCODED_IMAGE_NAME/versions/$vid" -H "Accept: application/vnd.github+json"; then
      echo "Deleted $vid"
    else
      echo "Failed to delete $vid"
    fi
  done
  echo "GHCR Cleanup complete."
fi

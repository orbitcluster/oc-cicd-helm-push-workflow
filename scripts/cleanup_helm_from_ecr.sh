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
    echo "No images found for branch $BRANCH_NAME."
    exit 0
fi

echo "Found images to delete:"
echo "$IMAGE_DIGESTS"

# Convert space-delimited digests to format needed for batch-delete-image
DELETE_ARGS=""
for digest in $IMAGE_DIGESTS; do
    DELETE_ARGS="$DELETE_ARGS imageDigest=$digest"
done

echo "Deleting images..."
aws ecr batch-delete-image --repository-name "$ECR_REPO_NAME" --region "$REGION" --image-ids $DELETE_ARGS

echo "Cleanup complete."

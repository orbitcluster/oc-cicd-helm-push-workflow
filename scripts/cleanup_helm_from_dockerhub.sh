#!/bin/bash
set -e

# Validate required environment variables
if [ -z "$BRANCH_NAME" ]; then
  echo "Error: BRANCH_NAME is not set."
  exit 1
fi

if [ -z "$CHART_ARCHIVE" ]; then
  echo "Error: CHART_ARCHIVE is not set."
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

# Sanitize branch name
SAFE_BRANCH_NAME=${BRANCH_NAME//\//-}
echo "Cleaning up Helm charts for branch: $BRANCH_NAME (safe: $SAFE_BRANCH_NAME)"

if [ -n "$REPOSITORY" ]; then
  TARGET_REPO="${DOCKERHUB_USERNAME}/${REPOSITORY}"
else
  TARGET_REPO="${DOCKERHUB_USERNAME}"
fi

CHART_BASENAME="${CHART_ARCHIVE%.tgz}"
CHART_NAME="${CHART_BASENAME%-$VERSION}"

echo "Target Docker Hub Repository: ${TARGET_REPO}/${CHART_NAME}"

# ------------------------------------------------------------------
# Docker Hub Cleanup Logic
# ------------------------------------------------------------------
echo "Authenticating with Docker Hub API..."
PAYLOAD=$(jq -n --arg username "$DOCKERHUB_USERNAME" --arg password "$DOCKERHUB_TOKEN" '{username: $username, password: $password}')
TOKEN_RESPONSE=$(curl -s -H "Content-Type: application/json" -X POST -d "$PAYLOAD" https://hub.docker.com/v2/users/login/)
JWT_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r .token)

if [ "$JWT_TOKEN" == "null" ] || [ -z "$JWT_TOKEN" ]; then
  echo "Failed to authenticate with Docker Hub API. Skipping Docker Hub cleanup."
else
  # Get tags
  echo "Fetching tags for repository ${TARGET_REPO}/${CHART_NAME}..."
  TAGS_RESPONSE=$(curl -s -H "Authorization: JWT ${JWT_TOKEN}" "https://hub.docker.com/v2/repositories/${TARGET_REPO}/${CHART_NAME}/tags/?page_size=100")

  if echo "$TAGS_RESPONSE" | jq -e '.results' >/dev/null; then
    TAGS_TO_DELETE=$(echo "$TAGS_RESPONSE" | jq -r ".results[] | select(.name | contains(\"${SAFE_BRANCH_NAME}\")) | .name")

    if [ -z "$TAGS_TO_DELETE" ]; then
      echo "No images found for branch $BRANCH_NAME in Docker Hub."
    else
      echo "Found tags to delete:"
      echo "$TAGS_TO_DELETE"

      for TAG in $TAGS_TO_DELETE; do
        echo "Deleting tag $TAG..."
        DELETE_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE -H "Authorization: JWT ${JWT_TOKEN}" "https://hub.docker.com/v2/repositories/${TARGET_REPO}/${CHART_NAME}/tags/${TAG}/")
        if [ "$DELETE_RESPONSE" == "204" ] || [ "$DELETE_RESPONSE" == "200" ]; then
          echo "Successfully deleted tag $TAG."
        else
          echo "Failed to delete tag $TAG. HTTP status code: $DELETE_RESPONSE"
        fi
      done

      echo "Docker Hub Cleanup complete."
    fi
  else
    echo "Repository ${TARGET_REPO}/${CHART_NAME} not found or no access. Skipping Docker Hub cleanup."
  fi
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

OWNER=$(echo "$PACKAGE" | cut -d'/' -f1)
IMAGE_NAME=$(echo "$PACKAGE" | cut -d'/' -f2-)
ENCODED_IMAGE_NAME=${IMAGE_NAME//\//%2f}

API_PREFIX="/orgs/$OWNER"
if ! gh api "$API_PREFIX/packages/container/$ENCODED_IMAGE_NAME/versions" -H "Accept: application/vnd.github+json" --silent >/dev/null 2>&1; then
  echo "Package not found in Org endpoint, checking User endpoint..."
  API_PREFIX="/users/$OWNER"
fi

echo "Listing GHCR versions matching branch tag '${SAFE_BRANCH_NAME}'..."
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

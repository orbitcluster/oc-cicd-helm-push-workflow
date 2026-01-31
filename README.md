# OC CICD Helm Push Workflow

This GitHub Action performs a Helm Chart promotion workflow. It pulls a Helm chart from the GitHub Container Registry (GHCR) and pushes it to an Amazon Elastic Container Registry (ECR) repository. It also handles the automatic creation of the ECR repository if it does not already exist.

## Features

- **Authenticate with GHCR**: Logs in to GitHub Container Registry using the provided token.
- **Pull Chart**: Retrieves the specified Helm chart version from GHCR (`oci://ghcr.io/PACKAGE`).
- **AWS Authentication**: Configures AWS credentials using OIDC/Assume Role.
- **ECR Login**: Logs in to Amazon ECR.
- **ECR Repository Management**: Checks if the target ECR repository exists and **automatically creates it** if missing.
- **Push to ECR**: Pushes the Helm chart to the specified ECR repository (`oci://REGISTRY/REPOSITORY`).

## Inputs

| Input            | Description                                       | Required | Default               |
| :--------------- | :------------------------------------------------ | :------- | :-------------------- |
| `appid`          | Application ID                                    | **Yes**  |                       |
| `orgid`          | Organization ID                                   | **Yes**  |                       |
| `buid`           | Build ID                                          | **Yes**  |                       |
| `role-to-assume` | IAM Role ARN to assume for AWS access             | **Yes**  |                       |
| `region`         | AWS Region                                        | No       | `us-east-1`           |
| `chart-archive`  | The name of the chart archive (without extension) | **Yes**  |                       |
| `package`        | Package path in GHCR (e.g., `owner/repo/chart`)   | **Yes**  |                       |
| `version`        | The version of the chart to pull and push         | **Yes**  |                       |
| `github-token`   | GitHub Token for authenticating with GHCR         | No       | `${{ github.token }}` |
| `repository`     | Target ECR Repository name                        | No       | `platform`            |

## Usage Example

```yaml
jobs:
  promote-helm:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: actions/checkout@v3

      - name: Push Helm to ECR
        uses: orbitcluster/oc-cicd-helm-push-workflow@main
        with:
          appid: "my-app"
          orgid: "my-org"
          buid: "123"
          role-to-assume: "arn:aws:iam::123456789012:role/GithubActionsRole"
          region: "us-east-1"
          chart-archive: "my-chart"
          package: "my-org/charts/my-chart"
          version: "1.0.0"
          repository: "my-ecr-repo-name"
```

## Workflow Details

1.  **Configure AWS Credentials**: Uses `aws-actions/configure-aws-credentials` to assume the specified IAM role.
2.  **Login to ECR**: Uses `aws-actions/amazon-ecr-login` to authenticate with ECR.
3.  **Execute Script (`push_helm_to_ecr.sh`)**:
    - Logs in to GHCR.
    - Pulls the chart: `helm pull oci://ghcr.io/${PACKAGE} --version ${VERSION}`
    - Checks if the ECR repository (`${REPOSITORY}`) exists in the configured region.
    - **Creates the repository** if it doesn't exist.
    - Pushes the chart: `helm push ${CHART_ARCHIVE}-${VERSION}.tgz oci://${REGISTRY}/${REPOSITORY}`

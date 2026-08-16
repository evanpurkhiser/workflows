# Reusable GitHub Actions Workflows

A collection of reusable GitHub Actions workflows for common CI/CD tasks.

## Workflows

- [**docker.yml**](.github/workflows/docker.yml) - Build Docker images and optionally publish to GHCR with Buildx caching
- [**bump-homebrew.yml**](.github/workflows/bump-homebrew.yml) - Dispatch the Homebrew tap `main.yml` workflow to bump a formula version
- [**bump-aur.yml**](.github/workflows/bump-aur.yml) - Dispatch the PKGBUILDs `main.yml` workflow to bump an AUR package version

## Quick Usage

Use these workflows from another repository with `workflow_call`:

```yaml
jobs:
  docker:
    uses: evanpurkhiser/workflows/.github/workflows/docker.yml@main
    with:
      publish: ${{ github.ref == 'refs/heads/main' }}

  bump_homebrew:
    uses: evanpurkhiser/workflows/.github/workflows/bump-homebrew.yml@main
    with:
      formula: my-tool
      version: ${{ needs.release_meta.outputs.tag_name }}
    secrets:
      token: ${{ secrets.HOMEBREW_TAP_TOKEN }}

  bump_aur:
    uses: evanpurkhiser/workflows/.github/workflows/bump-aur.yml@main
    with:
      package: my-tool
      version: ${{ needs.release_meta.outputs.tag_name }}
    secrets:
      token: ${{ secrets.AUR_BUMP_DISPATCH_PAT }}
```

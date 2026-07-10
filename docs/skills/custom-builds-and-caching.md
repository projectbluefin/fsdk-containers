---
name: custom-builds-and-caching
description: Guide for developers and agents to configure custom BuildStream builds and cache servers, including GHA caching.
metadata:
  context7-sources:
    - /apache/buildstream
---

# Custom Builds and Caching

This guide explains how developers and LLM agents who clone or fork this repository can configure their own custom builds, maintain them in GitHub Actions, and utilize caching (both the public GNOME and FSDK caches and their own custom caches).

## Caching Architecture

BuildStream 2 is designed with a strong cache-sharing model. In `project.conf`, the repository is pre-configured with two public, read-only (pull-only) cache servers:
- **GNOME Build Meta Cache:** `https://gbm.gnome.org:11003` (provides pre-built core elements from GNOME and FSDK)
- **Project Bluefin Cache:** `https://cache.projectbluefin.io:11001` (provides pre-built base and runtime elements for fsdk-containers)

Because these are pre-configured in `project.conf`, any local build or GitHub Actions workflow automatically pulls pre-built layers. You do not need to rebuild the entire Freedesktop SDK from scratch.

---

## Local Custom Builds

When running custom builds locally, you can configure your own writeable cache or override/augment the defaults using the BuildStream user configuration file.

### User Configuration File
The user configuration is located at `~/.config/buildstream.conf`.

### Setting Up a Custom Local Push Cache
To push your locally built artifacts to your own self-hosted BuildStream CAS (Content Addressable Storage) server, add the following to `~/.config/buildstream.conf`:

```yaml
projects:
  fsdk-containers:
    artifacts:
      # Set to false to keep using the GNOME/Bluefin public pull-caches alongside your own
      override-project-caches: false
      servers:
      - url: https://your-custom-cas-server:11001
        push: true
        auth:
          server-cert: /path/to/server.crt
          client-cert: /path/to/client.crt
          client-key: /path/to/client.key
```

If you do not have certificates (e.g. testing over localhost or a secure private network), you can omit the `auth` section or use an unencrypted server:

```yaml
projects:
  fsdk-containers:
    artifacts:
      override-project-caches: false
      servers:
      - url: http://localhost:11001
        push: true
```

---

## GitHub Actions: Fork and Custom Build Configuration

When a user or agent forks or clones this repository, the GitHub Actions workflows (`.github/workflows/build.yml`) run automatically under their own GitHub namespace.

### 1. Registry Destination (GHCR)
The workflows are pre-configured to dynamically detect the repository owner and publish to their GitHub Container Registry:
- Image name template: `ghcr.io/${{ github.repository_owner }}/<image>`
- Push credentials: Uses the built-in `${{ secrets.GITHUB_TOKEN }}` which has write access.

**Agent action required:** Ensure that GHA Workflow permissions are set to "Read and write permissions" (under Repository Settings > Actions > General > Workflow permissions) so the `GITHUB_TOKEN` is allowed to push packages.

### 2. Speeding Up Builds with GitHub Actions Local Cache
By default, the workflow does not cache the local build artifacts produced by BuildStream because they can be large. However, for active development branches, you can speed up builds by adding GHA's `actions/cache` to cache BuildStream's local directory (`~/.cache/buildstream`).

Add the following step in `.github/workflows/build.yml` before the build steps (e.g., after checkout):

```yaml
      - name: Cache BuildStream Local Directory
        uses: actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6
        with:
          path: ~/.cache/buildstream
          key: bst-cache-${{ runner.os }}-${{ github.sha }}
          restore-keys: |
            bst-cache-${{ runner.os }}-
```

*Note: GitHub Actions has a 10GB total cache limit per repository. BuildStream local caches can grow quickly. Ensure you monitor usage.*

### 3. Setting Up Custom Push CAS in GitHub Actions
For enterprise or heavy development workflows, using a remote BuildStream CAS (remote cache server) is recommended. To set this up in GitHub Actions:

1. Deploy a BuildStream CAS server (using BuildGrid, BuildBarn, or a simple `buildstream-share` container).
2. Store the CAS client certificates as GHA secrets in your repository:
   - `BST_CLIENT_CERT`
   - `BST_CLIENT_KEY`
   - `BST_SERVER_CERT`
3. Modify the workflow step to write these secrets to the runner's filesystem and create a custom user configuration. For example:

```yaml
      - name: Configure Custom BuildStream Push Cache
        run: |
          mkdir -p ~/.config
          mkdir -p ~/.certs
          echo "${{ secrets.BST_CLIENT_CERT }}" > ~/.certs/client.crt
          echo "${{ secrets.BST_CLIENT_KEY }}" > ~/.certs/client.key
          echo "${{ secrets.BST_SERVER_CERT }}" > ~/.certs/server.crt
          
          cat <<EOF > ~/.config/buildstream.conf
          projects:
            fsdk-containers:
              artifacts:
                override-project-caches: false
                servers:
                - url: https://your-custom-cas-server:11001
                  push: true
                  auth:
                    server-cert: /home/runner/.certs/server.crt
                    client-cert: /home/runner/.certs/client.crt
                    client-key: /home/runner/.certs/client.key
          EOF
```

This configuration ensures BuildStream pushes newly compiled artifacts back to your server, dramatically reducing subsequent build times.

## Maintaining Custom Builds (For AI Agents)

When an AI agent is tasked with maintaining or updating a custom build of these images in a fork or clone:

1. **Verify the baseline:** Run `just validate` to ensure the project graph resolves correctly using the public pull caches.
2. **Setup a devcontainer:** If working on a remote machine, utilize the devcontainer settings to ensure you are running in a consistent workspace environment (utilizing `podman` and `just`).
3. **Configure the target registry:** Ensure `image_registry` in the `Justfile` or `BUILD_IMAGE_REGISTRY` environment variable is pointing to the custom registry where you have push permission.
4. **Trigger tests:** After modifying elements, always execute `just build && just verify` before pushing or creating a PR. No build should be pushed to a testing branch without verified local or remote test results.

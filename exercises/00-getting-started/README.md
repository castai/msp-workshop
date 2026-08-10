# Step 0: Getting Started

Welcome to the workshop. This lesson gets your Linux environment ready so you
can follow along with every exercise that follows. If you just want to get
going, run the **Quick start** below — it installs everything you need and
creates a local Kubernetes cluster. The sections that follow explain what the
script does and how to recover if a step fails.

## Quick start

Run these commands in order. The setup script installs Docker (if missing),
`kubectl`, `helm`, and `cast-cli`, then creates a local kind cluster named
`workshop-cluster`. It stops immediately if any step fails.

```bash
git clone https://github.com/castai/msp-workshop.git $HOME/workshop
cd $HOME/workshop
./setup/setup-all.sh
```

If the script prints a message about the `docker` group (this happens after
Docker is freshly installed), your current shell does not yet have the
membership applied. Switch to a shell that does and re-run the same setup:

```bash
newgrp docker
./setup/setup-all.sh
```

When setup finishes successfully, verify the cluster is up:

```bash
kubectl get nodes --context kind-workshop-cluster
```

You should see a single `Ready` node named something like
`workshop-cluster-control-plane`.

> If anything fails, fix the underlying issue and re-run
> `./setup/setup-all.sh`. It is idempotent. For step-by-step recovery, see
> the [Troubleshooting Guide](../common/troubleshooting.md).

## What this lesson does

`./setup/setup-all.sh` is the single entry point for preparing your machine.
It runs four helper scripts in order and aborts on the first failure:

1. `install-docker.sh` — installs Docker if it is not already present.
2. `validate-setup.sh` — installs `kubectl`, `helm`, and `cast-cli` if they
   are missing, and configures the `k=kubectl` shell alias.
3. `install-kind.sh` — creates the local `workshop-cluster` kind cluster.
4. `verify-kind.sh` — confirms the cluster is reachable and healthy.

You do not need to run these by hand — `setup-all.sh` orchestrates them for
you. Re-running it is safe: each step is idempotent and skips work that has
already been done.

## Prerequisites

- **A Linux environment** running `bash` (Ubuntu, Debian, Fedora, RHEL, or a
  derivative).
- **`curl`** for downloading release artifacts.
- **Internet access** to GitHub releases and `get.helm.sh`. Configure
  `HTTP_PROXY` / `HTTPS_PROXY` if you are behind a corporate proxy.
- **`sudo`** (only if your user cannot write to `/usr/local/bin`).

## Next step

When `./setup/setup-all.sh` finishes and
`kubectl get nodes --context kind-workshop-cluster` shows a `Ready` node, you
are ready to move on to the next lesson.

If anything went wrong along the way, see the
[Troubleshooting Guide](../common/troubleshooting.md) for recovery steps,
then re-run `./setup/setup-all.sh` to pick up where you left off.

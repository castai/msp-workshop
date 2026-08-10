# MSP Workshop

A hands-on workshop covering MSP workflows on Kubernetes, using a local kind
cluster as the lab environment.

## Setup

Before working through the lessons, prepare your local environment with the
one-command setup script at the repository root:

```bash
./setup/setup-all.sh
```

That script installs Docker, `kubectl`, `helm`, `cast-cli`, creates the
`workshop-cluster` kind cluster, and verifies it is healthy. Run
`./setup/setup-all.sh --help` for all options, or
`./setup/setup-all.sh --recreate` to force a fresh cluster.

For more detail on what the setup scripts do and how to invoke them
individually, see [`setup/README.md`](./setup/README.md).

## Lessons

The lessons live under `exercises/`. Start with
[`exercises/00-getting-started/README.md`](./exercises/00-getting-started/README.md),
which walks you through validating your environment and then moves on to the
first Kubernetes lesson.

A per-lesson reset helper (`exercises/common/reset-lesson.sh`) is available
for clearing a single lesson's namespace without rebuilding the whole
cluster. If you run into trouble during setup, see
[`exercises/common/troubleshooting.md`](./exercises/common/troubleshooting.md).

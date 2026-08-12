# MSP Workshop

A hands-on workshop covering MSP workflows on Kubernetes.

## Setup

Before working through the lessons, prepare your local environment by
running the validator at the repository root:

```bash
./setup/validate-setup.sh
```

That script installs (or checks) `aws`, `kubectl`, `helm`, and `cast-cli`.
You bring your own Kubernetes cluster to follow the lessons.

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

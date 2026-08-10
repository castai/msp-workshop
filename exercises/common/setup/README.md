# MSP Workshop — kind Cluster Setup

These scripts manage the local Kubernetes cluster used by the workshop
lessons. They are intended to be run once by the instructor (or the learner)
before the lessons begin.

## Quick start

1. Install the command-line tools (`kubectl`, `helm`, and `cast-cli`):

   ```bash
   ./exercises/00-getting-started/validate-setup.sh
   # or, for cast-cli only:
   ./exercises/common/setup/install-cast-cli.sh
   ```

2. Create the kind cluster:

   ```bash
   ./exercises/common/setup/install-kind.sh
   ```

3. Verify the cluster is healthy:

   ```bash
   ./exercises/common/setup/verify-kind.sh
   ```

## Scripts

| Script | Purpose |
|---|---|
| `install-kind.sh` | Checks Docker, installs `kubectl`/`helm`/`kind` if missing, and creates the `workshop-cluster` kind cluster. |
| `kind-cluster-config.yaml` | kind configuration: 1 control-plane + 3 workers, NodePorts `30000-30003`/`30080`. |
| `install-cast-cli.sh` | Idempotently installs the `cast-cli` MSP workshop CLI via `get.cast.ai/linux`. |
| `verify-kind.sh` | Verifies the cluster exists, context, nodes, labels, and kube-system pods. |
| `health-check-kind.sh` | Lightweight health check of Docker, cluster, nodes, system pods, and CNI. |
| `reset-lesson.sh` | Deletes and recreates a lesson namespace while keeping the cluster. |
| `cleanup-all.sh` | Deletes the `workshop-cluster` and optionally prunes Docker resources. |

## Per-lesson reset

Each lesson should place its resources in a dedicated namespace, for example
`lesson-01-workloads`. To reset just that lesson while keeping the cluster:

```bash
./exercises/common/setup/reset-lesson.sh lesson-01-workloads
```

The script deletes the namespace, waits for it to be removed, then recreates
it empty.

## Recreating the cluster

To force a full cluster recreation:

```bash
./exercises/common/setup/install-kind.sh --recreate
```

To remove everything, including the cluster:

```bash
./exercises/common/setup/cleanup-all.sh
```

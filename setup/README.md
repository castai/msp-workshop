# MSP Workshop — kind Cluster Setup

These scripts manage the local Kubernetes cluster used by the workshop
lessons. They are intended to be run once by the instructor (or the learner)
before the lessons begin.

## One-command setup

If you want everything set up in one go, run the orchestrator. It installs
Docker, installs `kubectl`/`helm`/`cast-cli`, creates the kind cluster, and
verifies it:

```bash
./setup-all.sh
```

To force a fresh cluster (delete + recreate):

```bash
./setup-all.sh --recreate
```

Run `./setup-all.sh --help` for all options.

`setup-all.sh` runs the following scripts in order:

1. `install-docker.sh` — installs and starts Docker if missing.
2. `validate-setup.sh` — installs `kubectl`, `helm`, and `cast-cli`, and
   configures the `k=kubectl` alias.
3. `install-kind.sh` (with `--recreate` if requested) — creates the
   `workshop-cluster` kind cluster.
4. `verify-kind.sh` — confirms the cluster is healthy.

## Quick start

1. Install the command-line tools (`kubectl`, `helm`, and `cast-cli`):

   ```bash
   ./validate-setup.sh
   # or, for cast-cli only:
   ./install-cast-cli.sh
   ```

2. Create the kind cluster:

   ```bash
   ./install-kind.sh
   ```

3. Verify the cluster is healthy:

   ```bash
   ./verify-kind.sh
   ```

## Scripts

| Script | Purpose |
|---|---|
| `setup-all.sh` | One-command setup: runs `install-docker.sh`, `validate-setup.sh`, `install-kind.sh`, and `verify-kind.sh` in order. |
| `install-docker.sh` | Idempotently installs Docker (Linux via `get.docker.com`, macOS via Homebrew Cask) and starts the daemon. |
| `install-kind.sh` | Checks Docker, installs `kubectl`/`helm`/`kind` if missing, and creates the `workshop-cluster` kind cluster. |
| `kind-cluster-config.yaml` | kind configuration: 1 control-plane + 3 workers, NodePorts `30000-30003`/`30080`. |
| `install-cast-cli.sh` | Idempotently installs the `cast-cli` MSP workshop CLI via `get.cast.ai/linux`. |
| `verify-kind.sh` | Verifies the cluster exists, context, nodes, labels, and kube-system pods. |
| `health-check-kind.sh` | Lightweight health check of Docker, cluster, nodes, system pods, and CNI. |
| `validate-setup.sh` | Idempotent validator that installs `kubectl`, `helm`, and `cast-cli` if missing, and sets up the `k=kubectl` alias. |
| `cleanup-all.sh` | Deletes the `workshop-cluster` and optionally prunes Docker resources. |

## Per-lesson reset

Each lesson should place its resources in a dedicated namespace, for example
`lesson-01-workloads`. To reset just that lesson while keeping the cluster,
run the per-lesson reset script that lives in the shared `exercises/common/`
directory:

```bash
../exercises/common/reset-lesson.sh lesson-01-workloads
```

The script deletes the namespace, waits for it to be removed, then recreates
it empty.

## Recreating the cluster

To force a full cluster recreation:

```bash
./install-kind.sh --recreate
```

To remove everything, including the cluster:

```bash
./cleanup-all.sh
```

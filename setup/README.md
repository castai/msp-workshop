# MSP Workshop — Environment Setup

These scripts install and check the command-line tools (`aws`, `kubectl`,
`helm`, `cast-cli`) used by the lessons. They do **not** manage Docker and
they do not orchestrate multiple steps — run them once, or re-run them to
repair a broken environment.

## Quick start

1. Install/check the command-line tools (`aws`, `kubectl`, `helm`, and
   `cast-cli`):

   ```bash
   ./validate-setup.sh
   ```

   The script is idempotent: missing tools are installed; tools that are
   already present are left alone. Run it again any time you want to verify
   the toolchain.

2. To install only `cast-cli` (or repair an existing install), use the
   dedicated installer:

   ```bash
   ./install-cast-cli.sh
   ```

## Scripts

| Script | Purpose |
|---|---|
| `install-cast-cli.sh` | Idempotently installs the `cast-cli` MSP workshop CLI via `get.cast.ai/linux`. |
| `validate-setup.sh` | Idempotent validator that installs `aws`, `kubectl`, `helm`, and `cast-cli` (or `castctl`) if missing, and sets up the `k=kubectl` alias. |
| `configure-k8s.sh` | Configures AWS credentials (profile `workshop`), derives the EKS cluster name from the IAM user name, pulls the kubeconfig, and validates access with `kubectl get nodes`. |

## Per-lesson reset

Each lesson should place its resources in a dedicated namespace, for example
`lesson-01-workloads`. To reset just that lesson while keeping the rest of the
cluster intact, run the per-lesson reset script that lives in the shared
`exercises/common/` directory:

```bash
../exercises/common/reset-lesson.sh lesson-01-workloads
```

The script deletes the namespace, waits for it to be removed, then recreates
it empty.

# Bank of Anthos demo

A working, stress-testable deploy of Google's [Bank of Anthos](https://github.com/GoogleCloudPlatform/bank-of-anthos)
sample application. It brings up the full microservice topology — frontend,
userservice, contacts, ledgerwriter, transactionhistory, balancereader, plus
`accounts-db` and `ledger-db` Postgres backends — as a single Helm release.

The intent is to give MSP engineers a realistic target system to poke at:
drain nodes, kill pods, watch the frontend re-route, exercise the database
tier, drive load through Locust, etc.

## Layout

```
demos/bank-of-anthos/
├── README.md
├── deploy.sh                 # idempotent one-shot deploy
├── teardown.sh               # removes the demo namespace
└── bank-of-anthos/           # the Helm chart (do not edit in place)
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
        ├── frontend.yaml
        ├── userservice.yaml
        ├── contacts.yaml
        ├── ledgerwriter.yaml
        ├── transactionhistory.yaml
        ├── balancereader.yaml
        ├── accounts-db.yaml
        ├── ledger-db.yaml
        ├── config.yaml
        └── jwt-secret.yaml
```

The chart wraps the upstream `v0.6.10` container images and exposes
per-service replica, resource, image, service-type, and scheduling overrides
under each service key in `values.yaml`.

The upstream `loadgenerator` is intentionally excluded — use the shared
[demos/locust/](../locust/) chart for load generation so the workshop has one
canonical load-testing tool across demos.

## Prerequisites

- A healthy Kubernetes cluster reachable from your machine via `kubectl`.
- `kubectl` and `helm` on your PATH.
- A cloud provider that can provision `LoadBalancer` Services (or a
  controller such as MetalLB on bare metal) — the frontend is exposed via a
  `LoadBalancer` Service by default.

## Deploy

```bash
./deploy.sh
```

What it does:

1. Verifies `kubectl`, `helm`, and cluster connectivity.
2. Runs `helm upgrade --install bank-of-anthos ./bank-of-anthos --namespace bank-of-anthos --create-namespace --wait --timeout 10m`.
3. Waits up to 5 minutes for the `frontend` `LoadBalancer` Service to receive
   an external endpoint (hostname or IP).
4. Prints the public URL and verification commands.

Use `--dry-run` to print the helm command without executing anything:

```bash
./deploy.sh --dry-run
```

## Verify

Once `deploy.sh` finishes, the `frontend` `LoadBalancer` should have an
external endpoint:

```bash
# Pods (should be Running)
kubectl get pods -n bank-of-anthos

# Services (frontend should be type LoadBalancer)
kubectl get svc -n bank-of-anthos

# Helm release status
helm list -n bank-of-anthos

# Public URL of the frontend
kubectl get svc frontend -n bank-of-anthos \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
# (use '.ip' instead of '.hostname' if your cloud returns IPs)

# Reach the frontend from inside the cluster
curl http://frontend.bank-of-anthos.svc.cluster.local:80

# Stream pod logs if something is misbehaving
kubectl logs -n bank-of-anthos -l app=frontend -f --tail=50
kubectl logs -n bank-of-anthos -l app=userservice -f --tail=50
```

## Teardown

```bash
./teardown.sh
```

Removes the `bank-of-anthos` namespace and everything inside it (the Helm
release, all workloads, services, secrets, and the LoadBalancer). Use
`./teardown.sh --yes` to skip the confirmation prompt.

## Load testing

Use the shared [demos/locust/](../locust/) chart to drive traffic. The
in-cluster target URL for Bank of Anthos is:

```
http://frontend.bank-of-anthos.svc.cluster.local:80
```

In Locust, select the **BankUser** task set (it targets the frontend's
home, login, and accounts endpoints).

## Resource reference

| Service             | Image                                                                       | Replicas (default) | CPU req/lim   | Memory req/lim |
| ------------------- | --------------------------------------------------------------------------- | ------------------ | ------------- | -------------- |
| frontend            | `us-central1-docker.pkg.dev/bank-of-anthos-ci/bank-of-anthos/frontend`     | 1                  | 100m / 250m   | 64Mi / 128Mi   |
| userservice         | `.../userservice`                                                           | 1                  | 260m / 500m   | 128Mi / 256Mi  |
| contacts            | `.../contacts`                                                              | 1                  | 100m / 250m   | 64Mi / 128Mi   |
| ledgerwriter        | `.../ledgerwriter`                                                          | 1                  | 100m / 500m   | 256Mi / 512Mi  |
| transactionhistory  | `.../transactionhistory`                                                    | 1                  | 100m / 500m   | 256Mi / 512Mi  |
| balancereader       | `.../balancereader`                                                         | 1                  | 100m / 500m   | 256Mi / 512Mi  |
| accounts-db (Pg)    | `.../accounts-db`                                                           | 1                  | 100m / 250m   | 128Mi / 512Mi  |
| ledger-db (Pg)      | `.../ledger-db`                                                             | 1                  | 100m / 250m   | 512Mi / 1Gi    |

- Images are pinned to `v0.6.10` in `values.yaml`.
- The frontend is exposed via a `LoadBalancer` Service on port 80 -> 8080.
- All other services are `ClusterIP` and reached through DNS inside the namespace.
- All overrides live under each service key in `values.yaml` (replicaCount,
  image.repository, image.tag, resources, service, nodeSelector, tolerations,
  affinity).

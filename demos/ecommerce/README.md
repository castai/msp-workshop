# E-commerce demo

A working, stress-testable e-commerce platform deployed to the
`workshop-cluster` kind cluster. Provides realistic resource requests,
an autoscaler, a PodDisruptionBudget, and a continuous
load generator.

The intent is to give MSP engineers a target system they can poke at:
drain nodes, watch HPAs fire, kill pods, observe PDB behaviour, etc.

## Layout

```
demos/ecommerce/
├── README.md
├── deploy.sh                  # idempotent one-shot deploy
├── teardown.sh                # removes the demo namespace
├── install-metrics-server.sh  # standalone metrics-server installer
└── manifests/
    ├── namespace.yaml
    ├── workloads.yaml         # web-frontend, order-service, notification-service
    ├── hpa.yaml               # HPAs for web-frontend and order-service
    ├── pdb.yaml               # PDBs for web-frontend and order-service
    └── load-generator.yaml    # busybox pods driving HTTP traffic
```

## Prerequisites

- A healthy `kind-workshop-cluster` (created via `setup/setup-all.sh`).
- `kubectl` and `helm` on your PATH.

## Deploy

```bash
./deploy.sh
```

What it does:

1. Verifies cluster connectivity.
2. Creates the `demo-ecommerce` namespace (idempotent).
3. Installs `metrics-server` via Helm (idempotent — exits if already
   serving data).
4. Applies all manifests.
5. Waits for every deployment to be `Available`.
6. Waits for both HPAs to be registered.
7. Prints verification + port-forward commands.

## Verify

Once `deploy.sh` finishes:

```bash
# Pods (should be Running)
kubectl get pods -n demo-ecommerce -o wide

# HPA registration (targets should show <unknown>/50% until metrics flow)
kubectl get hpa -n demo-ecommerce

# PodDisruptionBudgets
kubectl get pdb -n demo-ecommerce

# Metrics (requires metrics-server, ~30s after install)
kubectl top pods -n demo-ecommerce
```

Watch the HPA under load:

```bash
kubectl get hpa -n demo-ecommerce -w
```

Within 3-5 minutes the load generator should push average CPU above 50%
and you should see `REPLICAS` climb from 2 toward 10.

## Access via port-forward

Each service is a `ClusterIP`; reach it from your laptop with
`kubectl port-forward`. Run each in its own terminal:

```bash
kubectl port-forward -n demo-ecommerce svc/web-frontend         8080:80
kubectl port-forward -n demo-ecommerce svc/order-service        8081:80
kubectl port-forward -n demo-ecommerce svc/notification-service 8082:80
```

Then probe them:

```bash
curl http://localhost:8080   # web-frontend (hpa-example "Hello" page)
curl http://localhost:8081   # order-service
curl http://localhost:8082   # notification-service (nginx default page)
```

The `hpa-example` image serves a CPU-burning endpoint — every request
costs CPU. That is what makes the load generator effective.

## Tail the load generator

```bash
kubectl logs -n demo-ecommerce -l app=load-generator -f --tail=20
```

You should see "Generating load on ..." once per container, then quiet
output (the `wget` calls are silenced with `-q`).

## Teardown

```bash
./teardown.sh
```

Removes the `demo-ecommerce` namespace and everything inside it (deployments,
services, HPAs, PDBs, load generator). `metrics-server` is **not**
removed — it is shared with other demos. Use `./teardown.sh --yes` to
skip the confirmation prompt.

To remove metrics-server too:

```bash
helm uninstall metrics-server -n kube-system
```

Or wipe the whole cluster:

```bash
./setup/cleanup-all.sh
```

## Resource reference

| Service               | Image                            | Replicas (min/max) | CPU req/lim   | Memory req/lim   |
| --------------------- | -------------------------------- | ------------------ | ------------- | ---------------- |
| web-frontend          | `registry.k8s.io/hpa-example`    | 2 / 10             | 200m / 1000m  | 128Mi / 256Mi    |
| order-service         | `registry.k8s.io/hpa-example`    | 2 / 10             | 200m / 1000m  | 128Mi / 256Mi    |
| notification-service  | `nginx:1.27-alpine`              | 2                  | 200m / 1000m  | 128Mi / 256Mi    |
| load-generator        | `busybox:1.36` (x2 containers)   | 1                  | 10m / 100m    | 32Mi / 64Mi      |

- HPAs target `cpu` `averageUtilization: 50%`.
- PDBs hold `minAvailable: 1` for web-frontend and order-service.
- Pods are spread across nodes via topology spread constraints
  (`maxSkew: 1`, `ScheduleAnyway`) so replicas land on different
  nodes for HA without requiring any node labels.

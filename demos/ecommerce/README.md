# E-commerce demo

A working, stress-testable e-commerce platform deployable to any
Kubernetes cluster. Provides realistic resource requests, an
autoscaler, and a PodDisruptionBudget. The frontend is exposed via
`LoadBalancer` for browser access; load is generated externally with
Locust (see `../locust/`).

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
    └── pdb.yaml               # PDBs for web-frontend and order-service
```

## Prerequisites

- A healthy Kubernetes cluster reachable from your machine via `kubectl`.
- `kubectl` and `helm` on your PATH.
- (Optional) A LoadBalancer controller — kind/minikube/most bare clusters
  will leave the LB in `<pending>` and you should use the port-forward
  fallback below.

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
7. Waits up to 5 minutes for the `web-frontend` LoadBalancer to get an
   external endpoint, then prints the URL.
8. Prints verification + port-forward commands.

## Access

### Via the LoadBalancer (default)

The `web-frontend` Service is `type: LoadBalancer`. On clusters with a
working LB controller (GKE, EKS, AKS, bare-metal with MetalLB, etc.)
`deploy.sh` will print the public URL once the endpoint is assigned:

```
Access the frontend via the LoadBalancer:
  http://<external-ip-or-hostname>
```

On clusters without an LB controller (kind, minikube without MetalLB,
most local setups) the endpoint stays `<pending>`. `deploy.sh` will warn
and you should fall back to port-forward.

### Port-forward fallback (works on any cluster)

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
costs CPU. That is what makes Locust effective at driving the HPA.

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

# LoadBalancer status (EXTERNAL-IP may be <pending> without an LB controller)
kubectl get svc web-frontend -n demo-ecommerce
```

Watch the HPA under load:

```bash
kubectl get hpa -n demo-ecommerce -w
```

Within 3-5 minutes of sustained traffic the average CPU should rise above
50% and you should see `REPLICAS` climb from 2 toward 10.

## Generate load with Locust

This demo no longer ships an in-cluster load generator. Use the
workshop's Locust harness to drive traffic at the frontend.

```bash
# from demos/ecommerce/
../locust/deploy.sh
```

`../locust/deploy.sh` prints the public Locust UI URL once the LoadBalancer
endpoint is assigned. Open that URL in a browser and enter:

- **Host**: `http://web-frontend.demo-ecommerce.svc.cluster.local:80`
- **Number of users**: 50–200
- **Spawn rate**: 10–25
- **User class**: `GenericUser`

`GenericUser` issues `GET /` repeatedly with a short wait — it is the
correct class for the e-commerce frontend (the hpa-example image burns
CPU on each request).

If the Locust LoadBalancer is still `<pending>`, use port-forward as a
fallback:

```bash
kubectl port-forward -n locust svc/locust 8089:8089
```

Then open http://localhost:8089.

## Teardown

```bash
./teardown.sh
```

Removes the `demo-ecommerce` namespace and everything inside it (deployments,
services, HPAs, PDBs). `metrics-server` is **not** removed — it is shared
with other demos. Use `./teardown.sh --yes` to skip the confirmation prompt.

To remove metrics-server too:

```bash
helm uninstall metrics-server -n kube-system
```

Or wipe the whole cluster using your provider's standard teardown
command (e.g. `minikube delete`, your managed cluster's CLI, etc.).

## Resource reference

| Service               | Image                            | Replicas (min/max) | CPU req/lim   | Memory req/lim   |
| --------------------- | -------------------------------- | ------------------ | ------------- | ---------------- |
| web-frontend          | `registry.k8s.io/hpa-example`    | 2 / 10             | 200m / 1000m  | 128Mi / 256Mi    |
| order-service         | `registry.k8s.io/hpa-example`    | 2 / 10             | 200m / 1000m  | 128Mi / 256Mi    |
| notification-service  | `nginx:1.27-alpine`              | 2                  | 200m / 1000m  | 128Mi / 256Mi    |

- HPAs target `cpu` `averageUtilization: 50%`.
- PDBs hold `minAvailable: 1` for web-frontend and order-service.
- Pods are spread across nodes via topology spread constraints
  (`maxSkew: 1`, `ScheduleAnyway`) so replicas land on different
  nodes for HA without requiring any node labels.
- `web-frontend` is exposed as `type: LoadBalancer` for browser access;
  `order-service` and `notification-service` remain `ClusterIP`.

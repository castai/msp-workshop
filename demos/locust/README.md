# Locust — shared load generator

A single Locust instance, deployed once, used by every demo in this workshop
(`ecommerce`, `online-boutique`, `bank-of-anthos`). It is exposed over the
internet via a `LoadBalancer` Service so any workshop participant can reach
the web UI from a browser.

Workshop users choose **what to load-test** and **which user class** to
run directly in the Locust web UI — no chart edits required.

## Layout

```
demos/locust/
├── README.md
├── deploy.sh        # idempotent one-shot deploy
├── teardown.sh      # removes the locust namespace
└── locust/          # Helm chart (Locust 2.32.2)
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
        ├── _helpers.tpl
        ├── configmap-locustfile.yaml   # BoutiqueUser, BankUser, GenericUser
        ├── deployment.yaml
        └── service.yaml
```

## Prerequisites

- A healthy Kubernetes cluster reachable from your machine via `kubectl`.
- `kubectl` and `helm` on your PATH.

## Deploy

```bash
./deploy.sh
```

What it does:

1. Verifies `kubectl`, `helm`, and cluster reachability.
2. Runs `helm upgrade --install locust ./locust --namespace locust --create-namespace --wait --timeout 5m`.
3. Waits up to 5 minutes for the `LoadBalancer` Service to receive an
   endpoint (hostname on EKS, IP on most other providers).
4. Prints the public Locust UI URL and a port-forward fallback command.

### Dry-run

```bash
./deploy.sh --dry-run
```

Prints the helm command and exits — no cluster changes.

## Open the Locust UI

Once deployed, the script prints the public URL:

```
http://<loadbalancer-hostname-or-ip>:8089
```

If the LoadBalancer endpoint has not been assigned yet (cloud provider is
slow), use the port-forward fallback:

```bash
kubectl port-forward -n locust svc/locust 8089:8089
# then open http://localhost:8089
```

> **Note:** the Locust web UI has **no authentication**. Acceptable for a
> workshop environment; do not expose this Service to the public internet
> in production.

## Use the Locust UI

The Locust UI is a one-page form. To run a load test:

1. **Host** — enter the target application's URL (see examples below).
2. **Number of users** to simulate.
3. **Spawn rate** (users started per second).
4. Pick a **user class** in the Locust UI's class selector. The chart
   does **not** pre-select a class — all three are available:
   - `BoutiqueUser` — Online Boutique product / cart / checkout flow.
   - `BankUser` — Bank of Anthos login / dashboard flow.
   - `GenericUser` — `GET /` repeatedly with a short wait. Works against
     any frontend, including the E-commerce demo. Use this when in doubt.
5. Click **Start swarming**.

### Example target URLs

Pick the URL that matches the application you deployed:

| Demo             | User class      | Target URL                                                          |
| ---------------- | --------------- | ------------------------------------------------------------------- |
| E-commerce       | `GenericUser`   | `http://web-frontend.demo-ecommerce.svc.cluster.local:80`           |
| Online Boutique  | `BoutiqueUser`  | `http://online-boutique-frontend.online-boutique.svc.cluster.local:80` |
| Bank of Anthos   | `BankUser`      | `http://frontend.bank-of-anthos.svc.cluster.local:80`               |

> **Tip:** using the wrong user class for an application usually produces
> a wall of 4xx/5xx in the Locust stats — pick the class from the same row
> as the demo you are targeting.

## Verify

```bash
# Pods (master should be Running)
kubectl get pods -n locust -o wide

# Service (type should be LoadBalancer)
kubectl get svc -n locust

# Endpoint progress
kubectl get svc -n locust -w
```

## Teardown

```bash
./teardown.sh           # prompts for confirmation
./teardown.sh --yes     # skip the confirmation prompt
```

Removes the `locust` namespace and everything inside it (locust pods,
ConfigMap, LoadBalancer Service). Deleting the Service triggers AWS ELB
cleanup; the class-level `setup-class/eks/delete-eks-cluster.sh` waits on
the matching ELBs to disappear before tearing down the cluster, so the
cluster teardown will not hang on a leftover load balancer.

## Chart notes

- Default `targetHost` is `""`. When empty, the Deployment template omits
  the `--host` argument entirely, so Locust starts with no default host
  and the UI prompts the user for one.
- Default `taskSet` is `""`. When empty, the Deployment template omits
  `LOCUST_USER_CLASSES` in both master and worker pods, so the Locust UI
  lists every class registered in the locustfile and lets users pick.
- Override `targetHost` / `taskSet` with `--set` to restore the old
  pre-prompt behaviour, e.g.
  `helm upgrade --install locust ./locust --set targetHost=http://frontend.bank-of-anthos.svc.cluster.local:80 --set taskSet=bank`.

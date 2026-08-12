# Online Boutique demo

A cloud-native, microservices-based demo shop from Google's
[microservices-demo](https://github.com/GoogleCloudPlatform/microservices-demo)
project. Deployed via the bundled Helm wrapper chart, exposed to the
internet through a `LoadBalancer` Service, and ready to be poked at from
the workshop's shared Locust load generator.

The intent is to give MSP engineers a realistic polyglot-microservice
target: a Go/Python/Node/Java/C# stack spread across ~12 Deployments,
all reachable through a single in-cluster DNS name.

## Layout

```
demos/online-boutique/
├── README.md
├── deploy.sh                  # idempotent one-shot deploy
├── teardown.sh                # removes the demo namespace
└── online-boutique/           # Helm wrapper chart (pinned to v0.10.6)
    ├── Chart.yaml
    ├── values.yaml
    ├── Chart.lock
    └── templates/
        ├── frontend.yaml      # LoadBalancer Service
        └── NOTES.txt
```

## Prerequisites

- A healthy Kubernetes cluster reachable from your machine via `kubectl`.
- `kubectl` and `helm` on your PATH.

The chart pulls the upstream `onlineboutique` subchart from
`oci://us-docker.pkg.dev/online-boutique-ci/charts` — make sure your
machine (or a pre-pulled image cache) can reach that OCI registry.

## Deploy

```bash
./deploy.sh
```

What it does:

1. Verifies `kubectl`, `helm`, and cluster connectivity.
2. Runs
   `helm upgrade --install online-boutique ./online-boutique --namespace online-boutique --create-namespace --wait --timeout 10m`.
3. Waits up to 5 minutes for the LoadBalancer Service
   `online-boutique-frontend` to receive an endpoint.
4. Prints the public URL plus verification and port-forward commands.

Dry-run mode prints the helm command and exits without applying
anything:

```bash
./deploy.sh --dry-run
```

## Verify

Once `deploy.sh` finishes:

```bash
# Pods (every microservice should be Running)
kubectl get pods -n online-boutique -o wide

# Services (frontend must be type LoadBalancer)
kubectl get svc -n online-boutique

# Public URL of the frontend
kubectl get svc online-boutique-frontend \
  -n online-boutique \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Helm release status
helm status online-boutique -n online-boutique
```

The in-cluster URL of the frontend is stable and used by the shared
Locust demo:

```
http://online-boutique-frontend.online-boutique.svc.cluster.local:80
```

## Access the storefront

Open the public LoadBalancer URL printed at the end of `deploy.sh`
in a browser. You can browse products, add them to a cart, check out,
and see the request fan out across the microservice graph.

If you cannot reach the LoadBalancer from your laptop, fall back to
port-forwarding:

```bash
kubectl port-forward -n online-boutique svc/online-boutique-frontend 8080:80
```

Then open <http://localhost:8080>.

## Load testing

The wrapper chart disables the upstream built-in load generator. Use
the shared [`../locust/`](../locust/README.md) demo instead:

1. Deploy Locust:

   ```bash
   cd ../locust
   ./deploy.sh
   ```

2. Open the Locust web UI at the URL printed by `demos/locust/deploy.sh`.

3. On the Locust "Start new load test" screen enter:

   | Field             | Value                                                            |
   | ----------------- | ---------------------------------------------------------------- |
   | Number of users   | e.g. `50`                                                        |
   | Spawn rate        | e.g. `5`                                                         |
   | Host              | `http://online-boutique-frontend.online-boutique.svc.cluster.local:80` |

   The Host field is the in-cluster URL of the Online Boutique frontend
   Service — Locust runs in the same cluster, so it talks directly to
   the ClusterIP backing the LoadBalancer.

4. From the user-class picker, choose **`BoutiqueUser`** (it walks the
   product catalog, cart and checkout endpoints that this app
   exposes). Other user classes target different demos and will return
   mostly 404s against Online Boutique.

5. Click **Start swarming** and watch the per-microservice latency in
   the Locust charts; cross-check with `kubectl get pods -n
   online-boutique -w` on the workshop cluster.

For a headless smoke test:

```bash
kubectl run -n locust --rm -it --restart=Never \
  --image=locustio/locust -- \
  -f /mnt/locust/locustfile.py \
  --host http://online-boutique-frontend.online-boutique.svc.cluster.local:80 \
  --headless -u 10 -r 2 --run-time 60s
```

## Teardown

```bash
./teardown.sh
```

Removes the `online-boutique` namespace and everything inside it
(upstream microservices, in-cluster Redis cart database, and the
LoadBalancer Service). Namespace deletion also triggers AWS ELB
cleanup — on EKS this can take a minute or two after the
`kubectl delete namespace` call returns.

Use `./teardown.sh --yes` to skip the confirmation prompt.

The shared Locust demo and metrics-server are **not** removed by this
script — run their own `teardown.sh` to do that.

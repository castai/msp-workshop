# MSP Workshop

A hands-on workshop covering Managed Service Provider (MSP) workflows on
Kubernetes using the CAST AI platform. Participants deploy a sample ecommerce
application, generate load, and then use CAST AI to optimize the cluster step
by step.

## What this repository contains

- **`exercises/`** — Workshop lessons, one per directory. Each lesson is a
  Markdown file loaded into the Strigo training platform via `.strigo/config.yml`.
- **`demos/`** — Demo applications used during the lessons:
  - `online-boutique/` — The sample ecommerce application
  - `locust/` — The load generator used to simulate traffic
- **`setup/`** — Scripts for participants to install and validate required
  tools (`aws`, `kubectl`, `helm`, `cast-cli`) and configure Kubernetes access.
- **`setup-class/`** — Scripts for instructors to provision and tear down
  per-participant AWS resources for the workshop.
- **`exercises/common/`** — Shared helpers such as the lesson reset script and
  troubleshooting guide.

## Workshop flow

1. Participants create a CAST AI account and connect their cluster.
2. The demo application is deployed and load is generated with Locust.
3. Participants apply optimizations in the CAST AI console:
   - Vertical Pod Autoscaling (VPA)
   - Bin packing with Evictor
   - Horizontal Pod Autoscaling (HPA)
   - Node Autoscaler
   - Cluster rebalancing
   - Cluster hibernation
4. The closing lesson summarizes what was learned.

## Setting up a class

Class setup is automated for AWS/EKS. The instructor scripts in
`setup-class/eks/` create a dedicated IAM user, IAM policy, IAM roles, and an
EKS cluster for each participant.

### Prerequisites

- AWS CLI (`aws`)
- `python3`
- `eksctl`
- Either `AWS_PROFILE` or `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION` set or configured in AWS CLI

### Create a participant environment

Run the master orchestrator with a unique identifier for the participant:

```bash
./setup-class/eks/create.sh <uniqueId>
```

This runs in dependency order:

1. Creates an IAM user and access key
2. Creates a per-user IAM policy
3. Attaches the policy to the user
4. Creates EKS cluster and nodegroup IAM roles
5. Creates the EKS cluster via `eksctl`

When the script finishes, it prints the participant's IAM user name and the
location of two files:

- `setup-class/eks/workshop-participant-IAM.md` — credentials and policy details
- `.env.<uniqueId>` at the repo root — environment variables for the participant

Hand both files to the participant securely. The credentials file is git-ignored
and must not be committed.

### Delete a participant environment

To tear down the same environment:

```bash
./setup-class/eks/delete.sh <uniqueId>
```

Add `--yes` to skip the interactive confirmation:

```bash
./setup-class/eks/delete.sh --yes <uniqueId>
```

This deletes the EKS cluster, IAM roles, IAM policy, IAM user, access keys, and
the local credentials and env files.

## Participant setup

Before working through the lessons, participants should prepare their local
environment by running the validator at the repository root:

```bash
./setup/validate-setup.sh
```

That script installs or checks `aws`, `kubectl`, `helm`, and `cast-cli`.

For more detail on the setup scripts, see [`setup/README.md`](./setup/README.md).

# Step 0: Getting Started

Prepare your environment for the workshop.

## Steps

1. **Clone the workshop repository**

   ```bash
   git clone https://github.com/castai/msp-workshop.git $HOME/workshop
   cd $HOME/workshop
   ```

2. **Install `castctl`**

   ```bash
   ./setup/install-cast-cli.sh
   ```

3. **Run the setup validator**

   This installs `aws`, `kubectl`, `helm`, and `cast-cli` if any are missing.

   ```bash
   ./setup/validate-setup.sh
   ```

4. **Receive AWS credentials**

   The lecturer or workshop host will provide your AWS access key, secret key,
   and default region.

5. **Configure your environment**

   Run the Kubernetes configuration script and follow the prompts. The script
   reads your IAM user name, derives the matching EKS cluster name, and pulls
   the kubeconfig. Sourcing keeps `AWS_PROFILE=workshop` active in your
   current shell:

   ```bash
   source ./setup/configure-k8s.sh
   ```

6. **Validate cluster access**

   List the Kubernetes cluster nodes to confirm everything is configured:

   ```bash
   kubectl get nodes
   ```

7. **Proceed to the next lesson**

   Once `kubectl get nodes` returns your cluster nodes, you are ready to
   continue.

# Closing

Congratulations — you have completed the CAST AI MSP Workshop!

## What we achieved

During this workshop we took a Kubernetes cluster and an ecommerce application,
then optimized it end-to-end using the CAST AI platform:

- **Connected the cluster** to the CAST AI console
- **Deployed the Online Boutique demo application** and simulated production
  load with Locust
- **Enabled VPA** with a custom `Zero-confidence` scaling policy to right-size
  workloads and eliminate resource starvation
- **Enabled Evictor in aggressive mode** to pack workloads densely and drive
  node consolidation
- **Enabled Node Autoscaler** with tailored node templates so the cluster adds
  the right nodes on demand and stays within budget
- **Configured HPA** to handle sudden traffic spikes by scaling out replicas
- **Rebalanced the cluster** to replace many small nodes with a more efficient
  node layout
- **Configured cluster hibernation** to shut down non-production clusters when
  they are not needed and wake them back up automatically

## What we learned

- CAST AI products work together: VPA for long-term resource optimization, HPA
  for short-term spikes, Evictor for dense bin packing, Node Autoscaler for
  elastic capacity, and Rebalancer for periodic cluster reshaping.
- Optimization is not a single action — it is a continuous loop of right-sizing,
  packing, scaling, rebalancing, and scheduling.
- Cost savings and performance improvements can be achieved without manual
  capacity planning or intrusive application changes.

## Questions and answers

Thank you for participating. If you have any questions about what we covered,
how to apply these optimizations to your own clusters, or what CAST AI can do
next, this is the time to ask.

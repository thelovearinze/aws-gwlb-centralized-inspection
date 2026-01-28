# AWS Gateway Load Balancer (GWLB) - Centralized Inspection Hub

## Project Overview
This project implements a Centralized Security Inspection Architecture on AWS using the Gateway Load Balancer (GWLB) and the GENEVE protocol. It demonstrates a "bump-in-the-wire" security model, where a firewall appliance is transparently inserted into the traffic path of a spoke VPC. This allows for centralized traffic inspection without requiring complex VPNs, NAT instances, or changes to the application logic.

**Key Technologies:** AWS Gateway Load Balancer, Terraform (Infrastructure as Code), GENEVE Protocol (UDP 6081), Linux Packet Routing, VPC Endpoints.

## Architecture Description
The infrastructure is divided into two distinct Virtual Private Clouds (VPCs) to simulate a real-world hub-and-spoke network topology:

1. **Consumer VPC (Spoke)**
   - **Role:** Simulates the application environment.
   - **Components:** Contains the application server (EC2) and a Gateway Load Balancer Endpoint (GWLBE).
   - **Routing Logic:** The Route Table is configured to intercept specific outbound traffic (e.g., to 8.8.8.8) and route it to the GWLBE for inspection, while allowing management traffic (SSH) to bypass the inspection for connectivity resilience.

2. **Security VPC (Hub)**
   - **Role:** Centralized inspection zone.
   - **Components:** Hosted the Gateway Load Balancer and the Inspection Appliance (Linux-based Firewall).
   - **Traffic Flow:** The GWLB encapsulates incoming traffic in GENEVE headers and forwards it to the firewall appliance. The appliance inspects, processes, and returns the traffic to the GWLB, which then forwards it to the destination.

## Key Features
- **Transparent Inspection:** Application servers operate without knowledge of the inspection layer; traffic redirection is handled entirely at the VPC routing level.
- **Infrastructure as Code:** The entire environment, including VPCs, Subnets, Routing Tables, and EC2 instances, is provisioned and managed using Terraform.
- **High Availability & Scalability:** Leverages AWS Gateway Load Balancer to distribute traffic across potential fleets of security appliances, removing the single point of failure common in legacy NAT instance setups.
- **Decoupled Architecture:** Separates the security infrastructure from the application infrastructure, allowing security teams to update firewall rules without impacting application deployment.

## Technical Challenges & Solutions
During the implementation of this architecture, several advanced networking challenges were encountered and resolved:

### 1. Asymmetric Routing & Traffic Drops
**Problem:** Initial SSH connections to the application server failed. The request packets reached the server, but the return traffic was routed into the inspection appliance, which dropped the packets due to a lack of state/context.

**Solution:** Implemented Split Routing in the Spoke VPC Route Table.

- Management traffic (0.0.0.0/0) is routed directly to the Internet Gateway.
- Test traffic (8.8.8.8/32) is routed specifically to the GWLB Endpoint.
This ensures management connectivity remains robust while proving the inspection capability.

### 2. GWLB Target Health Failures
**Problem:** The Target Group consistently reported the inspection appliance as "Unhealthy," preventing traffic flow.

**Root Cause:** The Terraform configuration defined the Load Balancer and Target Group but was missing the Listener resource. Without a listener, the GWLB could not forward health checks or traffic.

**Solution:** Added an `aws_lb_listener` resource in Terraform to explicitly bridge the GWLB to the Target Group using the GENEVE protocol.

### 3. GENEVE Encapsulation Verification
**Problem:** Confirming that traffic was actually passing through the GWLB rather than bypassing it.

**Verification:** Used `tcpdump` on the inspection appliance to capture UDP port 6081. Successfully captured packets showing the outer GENEVE headers wrapping the inner ICMP (ping) packets, validating the architecture works as designed.

## Deployment Instructions

### Prerequisites
- AWS CLI configured with appropriate permissions.
- Terraform installed (v1.0+).
- An SSH Key Pair generated locally.

### Steps
1. **Clone the Repository:**
   `git clone https://github.com/thelovearinze/aws-gwlb-centralized-inspection.git`
   
2. **Initialize Terraform:**
   `terraform init`

3. **Plan and Apply:**
   `terraform plan`
   `terraform apply`

4. **Verify Traffic:**
   - SSH into the Spoke App Server.
   - Run `ping 8.8.8.8`.
   - Simultaneously, SSH into the Inspection Appliance and run `sudo tcpdump -nni ens5 udp port 6081` to observe the encapsulated traffic.

5. **Cleanup:**
   Run `terraform destroy` to remove all resources and stop billing.

## Related Documentation
For a deep dive into the architectural decisions, routing logic, and "War Stories" from this implementation, read the full case study on Medium:
[**Building a Centralized Traffic Inspection Hub on AWS**]https://medium.com/@thelovearinze/f6ed4ee3b56d
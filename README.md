# Enable Supervisor on VCF 9.0 (Multi AZ) Automation Script

## Overview

This script automates the process of enabling  Supervisor on a vCenter Server instance, specifically tailored for VMware Cloud Foundation (VCF) 9.0 multi-Availability Zone (AZ) deployments. It streamlines the setup by making necessary API calls to vCenter and, if applicable, NSX Manager.

The script supports several deployment types by using different JSON configuration templates:

*   **VPC:** For VMware Cloud on AWS (VMC) or similar NSX-T VPC environments.
*   **NSX:** For on-premises deployments utilizing NSX-T as the primary networking and load balancing solution.
*   **AVI:** For deployments using NSX Advanced Load Balancer (AVI) as the load balancing solution.
*   **FLB:** Intended for "Foundation Load Balancer" type deployments. (**Note:** The template for this type is currently a placeholder and non-functional.)

## Important Notes

*   **Caution:** This script makes significant configuration changes to your vSphere environment. It is strongly recommended that you understand the script's operations, back up any existing configurations, and test thoroughly in a non-production environment before using it in a live environment.
*   **Review Variables:** Carefully review and update all variables in the `enable-wcp.sh` script to match your specific environment details before execution. Incorrect configurations can lead to errors or an improperly configured Supervisor.

## Prerequisites

Before running this script, ensure the following prerequisites are met:

**Software/Tools:**

*   **Bash Shell:** A bash-compatible environment (Linux, macOS, WSL on Windows).
*   **`jq`:** Command-line JSON processor. The script will check for its presence.
*   **`curl`:** Command-line tool for transferring data with URLs. The script will check for its presence.
*   **`envsubst`:** This is a Utility from the GNU gettext package that is used to substitute environment variables in the JSON templates.
*   **`openssl`:** Required only if `DEPLOYMENT_TYPE` is set to `AVI`, for fetching the AVI Controller's CA certificate.

**Network Connectivity:**

*   The machine running the script must have HTTPS (port 443) connectivity to:
    *   vCenter Server.
    *   NSX Manager (if `DEPLOYMENT_TYPE="NSX"`).
    *   AVI Controller (if `DEPLOYMENT_TYPE="AVI"`).
*   The Supervisor control plane VMs and workloads will require access to the DNS and NTP servers specified in the configuration.

**vCenter & NSX Permissions:**

*   **vCenter User (`VCENTER_USERNAME`):** Must have permissions to:
    *   Authenticate and create a session.
    *   Read storage policies.
    *   Read consumption domain zones.
    *   Read network details (port groups, distributed switches).
    *   Find content libraries.
    *   Enable Supervisor on zones.
    *   Check NSX distributed switch compatibility (for NSX deployments).
*   **NSX Manager User (`NSX_USERNAME`):** (Required if `DEPLOYMENT_TYPE="NSX"`) Must have permissions to:
    *   Read Edge Clusters.
    *   Read Tier-0 Gateways.

**Pre-configured Environment:**

*   **vCenter Server:** Installed and configured.
*   **Availability Zones:** The Availability Zones specified in `K8S_SUP_ZONE1`, `K8S_SUP_ZONE2`, `K8S_SUP_ZONE3` must be pre-configured in vCenter.
*   **Networks:**
    *   Management port groups (e.g., `K8S_MGMT_PORTGROUP1`) must exist in each AZ.
    *   Workload network port group (`K8S_WKD0_PORTGROUP`) must exist (not required for NSX deployments).
*   **Storage Policy:** The storage policy specified in `K8S_STORAGE_POLICY` must exist.
*   **Content Library:** The content library (`K8S_CONTENT_LIBRARY`) must exist and be subscribed to the VMware Tanzu Kubernetes release OVA/OVF templates.
*   **NSX Specific (if `DEPLOYMENT_TYPE="NSX"`):**
    *   NSX Manager deployed and configured.
    *   NSX Edge Cluster (`NSX_EDGE_CLUSTER`) must exist.
    *   NSX Tier-0 Gateway (`NSX_T0_GATEWAY`) must exist.
    *   A compatible NSX Distributed Virtual Switch (DVS/VDS) (`NSX_DVS_PORTGROUP`) must exist.
*   **AVI Specific (if `DEPLOYMENT_TYPE="AVI"`):**
    *   NSX Advanced Load Balancer (AVI) Controller deployed and configured.
*   **VPC Specific (if `DEPLOYMENT_TYPE="VPC"`):**
    *   NSX VPC Organization, Project, and Connectivity Profile must be configured.

## Configuration

All configuration is performed by editing the environment variables within the `enable-wcp.sh` script. **Do NOT directly edit the JSON template files for variable substitution**, as the script handles this via `envsubst`.

Open `enable-wcp.sh` in a text editor and modify the following sections:

**1. Infrastructure Variables (Mandatory):**

*   `VCENTER_VERSION`: vCenter version (script defaults to 9).
*   `VCENTER_HOSTNAME`: FQDN or IP of vCenter Server.
*   `VCENTER_USERNAME`: vCenter username (e.g., `administrator@vsphere.local`).
*   `VCENTER_PASSWORD`: vCenter password.
*   `NSX_MANAGER`: FQDN or IP of NSX Manager (required for `NSX` deployments).
*   `NSX_USERNAME`: NSX Manager username (required for `NSX` deployments).
*   `NSX_PASSWORD`: NSX Manager password (required for `NSX` deployments).
*   `K8S_SUP_ZONE1`, `K8S_SUP_ZONE2`, `K8S_SUP_ZONE3`: Names of your pre-configured vCenter Availability Zones.
*   `DEPLOYMENT_TYPE`: **Crucial.** Sets the deployment mode. Allowed values:
    *   `VPC`
    *   `NSX`
    *   `AVI`
    *   `FLB` (Currently non-functional due to empty template)

**2. Standard Variables (Review and Update all):**

*   `DNS_SERVER`: IP address of DNS server.
*   `NTP_SERVER`: FQDN or IP of NTP server.
*   `DNS_SEARCHDOMAIN`: DNS search domain.
*   `MGMT_STARTING_IP`: Starting IP for Supervisor control plane VMs (script reserves 5 IPs).
*   `MGMT_GATEWAY_CIDR`: Gateway IP and CIDR for the management network (e.g., `10.0.0.1/24`).
*   `K8S_SERVICE_SUBNET`: Subnet for Kubernetes services (e.g., `10.96.0.0`).
*   `K8S_SERVICE_SUBNET_COUNT`: Number of IPs for K8s service subnet (e.g., 512 for /23).
*   `SUPERVISOR_NAME`: Desired name for the Supervisor.
*   `SUPERVISOR_SIZE`: Size of Supervisor control plane VMs (`TINY`, `SMALL`, `MEDIUM`, `LARGE`).
*   `SUPERVISOR_VM_COUNT`: Number of Supervisor control plane VMs (1 or 3).
*   `K8S_CONTENT_LIBRARY`: Name of the Content Library for Tanzu Kubernetes releases.
*   `K8S_MGMT_PORTGROUP1`, `K8S_MGMT_PORTGROUP2`, `K8S_MGMT_PORTGROUP3`: Management network port groups for each AZ.
*   `K8S_WKD0_PORTGROUP`: Workload network port group (not needed for `NSX` deployments).
*   `K8S_STORAGE_POLICY`: Name of the vSphere storage policy.

**3. AVI Specific Variables (used if `DEPLOYMENT_TYPE='AVI'`):**

*   `AVI_CONTROLLER`: FQDN or IP of the AVI Controller.
*   `AVI_CLOUD`: AVI Cloud name (Note: The script comments this out; ensure it's set if your `enable_on_zone_avi.json` requires it).
*   `AVI_USERNAME`: AVI Controller username.
*   `AVI_PASSWORD`: AVI Controller password.
*   `AVI_WORKLOAD_NW_GATEWAY_CIDR`: Gateway and CIDR for AVI workload network.
*   `AVI_WORKLOAD_STARTING_IP`: Starting IP for AVI workload network.
*   `AVI_WORKLOAD_IP_COUNT`: Number of IPs for AVI workload network.
    *   **Important for AVI:** Review `enable_on_zone_avi.json`. Fields like `cloud_name`, `username`, `password`, and `server` within this JSON are **not directly parameterized by environment variables in the current script version**, apart from the CA certificate (`AVI_CACERT`, which the script fetches). You may need to manually edit these fields in `enable_on_zone_avi.json` or modify the script if you need to parameterize them further.

**4. NSX Specific Variables (used if `DEPLOYMENT_TYPE='NSX'`):**

*   `NSX_EDGE_CLUSTER`: Display name of the NSX Edge Cluster.
*   `NSX_T0_GATEWAY`: Display name of the NSX Tier-0 Gateway.
*   `NSX_DVS_PORTGROUP`: Name of the NSX-compatible VDS/DVS.
*   `NSX_INGRESS_NW`: Starting IP for Ingress network range.
*   `NSX_INGRESS_COUNT`: Number of IPs for Ingress range.
*   `NSX_EGRESS_NW`: Starting IP for Egress network range.
*   `NSX_EGRESS_COUNT`: Number of IPs for Egress range.
*   `NSX_NAMESPACE_NW`: Starting IP for vSphere Namespace (Pod CIDRs) network range.
*   `NSX_NAMESPACE_COUNT`: Number of IPs for the vSphere Namespace range.

**5. VPC Specific Variables (used if `DEPLOYMENT_TYPE='VPC'`):**

*   `VPC_ORG`: NSX VPC Organization ID.
*   `VPC_PROJECT`: NSX VPC Project ID.
*   `VPC_CONNECTIVITY_PROFILE`: NSX VPC Connectivity Profile ID.
*   `VPC_DEFAULT_PRIVATE_CIDRS_ADDRESS`: Default private CIDR address for VPC.
*   `VPC_DEFAULT_PRIVATE_CIDRS_PREFIX`: Prefix for the default private CIDR.

## Usage

1.  **Download/Clone:** Obtain the `enable-wcp.sh` script and all `enable_on_zone_*.json` template files.
2.  **Configure:** Open `enable-wcp.sh` in a text editor. Meticulously update the variables described in the "Configuration" section to match your environment. Double-check the `DEPLOYMENT_TYPE`.
3.  **Make Executable:**
    ```bash
    chmod +x enable-wcp.sh
    ```
4.  **Run Script:**
    ```bash
    ./enable-wcp.sh
    ```
5.  **Monitor Output:** Observe the script's console output. It will show authentication status, details of fetched resources, and the final API call. Note any error messages.
6.  **Post-Execution:**
    *   The script **initiates** the Supervisor enablement process.
    *   **Crucially, monitor the actual progress and completion status in the vCenter UI (Tasks and Events consoles).**
    *   The script automatically cleans up temporary files (`/tmp/temp_*.*`, `temp_final.json`, `zone.json`) upon completion or error.

## JSON Template Files

These files serve as templates for the JSON payload required by the vCenter API to enable the Supervisor. The `enable-wcp.sh` script selects one based on `DEPLOYMENT_TYPE`, substitutes the configured environment variables into it using `envsubst`, and then uses this final JSON for the API call.

*   **`enable_on_zone_avi.json`**: Used when `DEPLOYMENT_TYPE="AVI"`. Configures Supervisor with NSX Advanced Load Balancer.
    *   *Note:* As mentioned in the configuration section, some fields in this template might require manual editing for your specific AVI setup, as the script does not fully parameterize them.
*   **`enable_on_zone_flb.json`**: Used when `DEPLOYMENT_TYPE="FLB"`.
    *   **Warning: This template is currently empty and non-functional. Using `DEPLOYMENT_TYPE="FLB"` will result in a failed deployment.**
*   **`enable_on_zone_nsx.json`**: Used when `DEPLOYMENT_TYPE="NSX"`. Configures Supervisor with NSX-T networking.
*   **`enable_on_zone_vpc.json`**: Used when `DEPLOYMENT_TYPE="VPC"`. Configures Supervisor for VMC on AWS or similar NSX-T VPC environments.

Users generally should not need to modify these JSON files directly unless comfortable with the vCenter API and the specific requirements for a deployment type (e.g., for the AVI scenario mentioned).

## Troubleshooting

*   **Typos & Configuration Errors:**
    *   Double-check all variable names and values in `enable-wcp.sh` for typos.
    *   Ensure the correct `DEPLOYMENT_TYPE` is set for your environment.
*   **Script Execution Failures:**
    *   **`jq could not be found` / `curl could not be found`:** Install `jq` or `curl` respectively.
    *   **`envsubst: command not found`:** Install `gettext` package (which includes `envsubst`).
    *   **`Permission Denied` running script:** Use `chmod +x enable-wcp.sh`.
*   **Authentication/Connection Issues:**
    *   **`Could not connect to the VCenter`**: Verify `VCENTER_HOSTNAME`, credentials, and network connectivity to vCenter. Check the vCenter service status.
    *   **`Could not connect to the NSX ALB endpoint` (AVI):** Verify `AVI_CONTROLLER` address, network connectivity, and AVI Controller status.
    *   **`Could not fetch Edge Cluster details` (NSX):** Verify `NSX_MANAGER` address, NSX credentials, network connectivity, and NSX Manager service status. Ensure NSX entity names are correct.
*   **API Call Failures / Resource Not Found:**
    *   **`Could not fetch storage policy/zone/portgroup/content library`**: Verify the exact names of these entities in vCenter and match them in `enable-wcp.sh`.
    *   **`Could not fetch NSX compatible VDS` (NSX):** Verify VDS/DVS name and its NSX compatibility.
    *   **Supervisor enablement API call fails (final step):**
        *   This can have many causes (IP conflicts, resource exhaustion, incompatible settings).
        *   Temporarily comment out the `rm -f temp_final.json` line in the script to inspect the generated JSON payload.
        *   **Check vCenter Tasks and Events for detailed error messages from the Supervisor enablement process itself.**
*   **General Debugging Tips:**
    *   Add `set -x` at the top of `enable-wcp.sh` (after `#!/bin/bash`) to print each command before execution. Remove after debugging.
    *   Manually test API calls using `curl` if you are familiar with the vCenter APIs, using the session ID logged by the script.

## License

Refer to the `LICENSE` file in this repository for licensing details.

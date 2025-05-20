#!/bin/bash

###################################################
# Enter Infrastructure variables here
###################################################
VCENTER_VERSION=9
VCENTER_HOSTNAME=10.11.10.130
VCENTER_USERNAME=administrator@sfo-w01.local
VCENTER_PASSWORD='VMw@re1!VMw@re1!'
NSX_MANAGER=10.11.10.131
NSX_USERNAME='admin'
NSX_PASSWORD='VMw@re1!VMw@re1!'
K8S_SUP_ZONE1='zone-cl01'
K8S_SUP_ZONE2='zone-cl04'
K8S_SUP_ZONE3='zone-cl05'

DEPLOYMENT_TYPE='VPC' # Allowed values are VPC, NSX, AVI, FLB

#####################################################
# Common variables
#####################################################
export DNS_SERVER='10.11.10.4'
export NTP_SERVER='ntp0.sfo.rainpole.io'
export DNS_SEARCHDOMAIN='sfo.rainpole.io'
export MGMT_STARTING_IP='10.13.10.151'
export MGMT_GATEWAY_CIDR='10.13.10.1/24'
export K8S_SERVICE_SUBNET='10.96.0.0'
export K8S_SERVICE_SUBNET_COUNT=512 # Allowed values are 256, 512, 1024, 2048, 4096...
export SUPERVISOR_NAME='supervisor01'
export SUPERVISOR_SIZE=TINY # Allowed values are TINY, SMALL, MEDIUM, LARGE
export SUPERVISOR_VM_COUNT=3 # Allowed values are 1, 3
K8S_CONTENT_LIBRARY='vks'
K8S_MGMT_PORTGROUP1='sfo-w01-cl01-vds01-pg-vm-mgmt'
K8S_MGMT_PORTGROUP2='sfo-w01-cl04-vds01-pg-vm-mgmt'
K8S_MGMT_PORTGROUP3='sfo-w01-cl05-vds01-pg-vm-mgmt'
K8S_WKD0_PORTGROUP='Workload0-VDS-PG' # Not needed for NSX
K8S_STORAGE_POLICY='vSAN Default Storage Policy'

###############################################################
# AVI specific variables
###############################################################
#export AVI_CONTROLLER='10.0.0.20'
#export AVI_CLOUD='domain-c10'
#export AVI_USERNAME=admin
#export AVI_PASSWORD='VMware123!VMware123!'
#export AVI_WORKLOAD_NW_GATEWAY_CIDR='192.168.102.1/23'
#export AVI_WORKLOAD_STARTING_IP='192.168.102.100'
#export AVI_WORKLOAD_IP_COUNT=64

#############################################################
# NSX specific variables
#############################################################
#export NSX_EDGE_CLUSTER='edge-cluster-01'
#export NSX_T0_GATEWAY='t0-01'
#export NSX_DVS_PORTGROUP='vds1'
#export NSX_INGRESS_NW='10.220.3.16'
#export NSX_INGRESS_COUNT=16
#export NSX_EGRESS_NW='10.220.30.80'
#export NSX_EGRESS_COUNT=16
#export NSX_NAMESPACE_NW='10.244.0.0'
#export NSX_NAMESPACE_COUNT=4096

#############################################################
# VPC specific variables
#############################################################
export VPC_ORG='default'
export VPC_PROJECT='default'
export VPC_CONNECTIVITY_PROFILE='default'
export VPC_DEFAULT_PRIVATE_CIDRS_ADDRESS='172.16.0.0'
export VPC_DEFAULT_PRIVATE_CIDRS_PREFIX=24

################################################
# Check if jq is installed
################################################
if ! command -v jq &> /dev/null
then
    echo "jq could not be found. Please install jq to run this script."
    exit
fi

################################################
# Check if curl is installed
################################################
if ! command -v curl &> /dev/null
then
    echo "curl could not be found. Please install curl to run this script."
    exit
fi

if [ ${DEPLOYMENT_TYPE} == "AVI" ]
then
        cp enable_on_zone_avi.json zone.json
elif [ ${DEPLOYMENT_TYPE} == "VPC" ]
then
        cp enable_on_zone_vpc.json zone.json
elif [ ${DEPLOYMENT_TYPE} == "NSX" ]
then
        cp enable_on_zone_nsx.json zone.json
elif [ ${DEPLOYMENT_TYPE} == "FLB" ]
then
        cp enable_on_zone_flb.json zone.json
else
        echo "Error: Invalid deployment type. Allowed values are VPC, NSX, AVI, FLB"
        exit 1
fi  

content_library_json()
{
        cat <<EOF
{
        "name": "${K8S_CONTENT_LIBRARY}"
}
EOF
}

################################################
# Login to VCenter and get Session ID
###############################################
HEADER_CONTENTTYPE="Content-Type: application/json"
SESSION_ID=$(curl -sk -X POST https://${VCENTER_HOSTNAME}/rest/com/vmware/cis/session --user ${VCENTER_USERNAME}:${VCENTER_PASSWORD} |jq -r '.value')
if [ -z "${SESSION_ID}" ]
then
        echo "Error: Could not connect to the VCenter. Please validate!!"
        exit 1
fi
echo Authenticated successfully to VC with Session ID - "${SESSION_ID}" ...
HEADER_SESSIONID="vmware-api-session-id: ${SESSION_ID}"

################################################
# Get storage policy details from vCenter
###############################################
echo "Searching for Storage Policy ${K8S_STORAGE_POLICY} ..."
response=$(curl -ks --write-out "%{http_code}" -X GET  -H "${HEADER_SESSIONID}" https://${VCENTER_HOSTNAME}/api/vcenter/storage/policies --output /tmp/temp_storagepolicies.json)
if [[ "${response}" -ne 200 ]] ; then
  echo "Error: Could not fetch storage policy. Please validate!!"
  exit 1
fi

export VKS_STORAGE_POLICY=$(jq -r --arg K8S_STORAGE_POLICY "$K8S_STORAGE_POLICY" '.[]| select(.name == $K8S_STORAGE_POLICY)|.policy' /tmp/temp_storagepolicies.json)
#export VKS_StoragePolicy=$(jq -r --arg K8S_STORAGE_POLICY "$K8S_STORAGE_POLICY" '.[]| select(.name|contains($K8S_STORAGE_POLICY))|.policy' /tmp/temp_storagepolicies.json)
if [ -z "${VKS_STORAGE_POLICY}" ]
then
        echo "Error: Could not fetch storage policy - ${K8S_STORAGE_POLICY} . Please validate!!"
        exit 1
fi

################################################
# Get zone details from vCenter
###############################################
echo "Searching for Zones ${K8S_SUP_ZONE1}, ${K8S_SUP_ZONE2}, ${K8S_SUP_ZONE3}..."
response=$(curl -ks --write-out "%{http_code}" -X GET  -H "${HEADER_SESSIONID}" https://${VCENTER_HOSTNAME}/api/vcenter/consumption-domains/zones --output /tmp/temp_zones.json)
if [[ "${response}" -ne 200 ]] ; then
  echo "Error: Could not fetch zones. Please validate!!"
  exit 1
fi

export VKSZone1=$(jq -r --arg K8S_SUP_ZONE1 "$K8S_SUP_ZONE1" '.items[]|select(.zone == $K8S_SUP_ZONE1).zone' /tmp/temp_zones.json)
if [ -z "${VKSZone1}" ]
then
        echo "Error: Could not fetch zone - ${K8S_SUP_ZONE1} . Please validate!!"
        exit 1
fi
export VKSZone2=$(jq -r --arg K8S_SUP_ZONE2 "$K8S_SUP_ZONE2" '.items[]|select(.zone == $K8S_SUP_ZONE2).zone' /tmp/temp_zones.json)
if [ -z "${VKSZone2}" ]
then
        echo "Error: Could not fetch zone - ${K8S_SUP_ZONE2} . Please validate!!"
        exit 1
fi
export VKSZone3=$(jq -r --arg K8S_SUP_ZONE3 "$K8S_SUP_ZONE3" '.items[]|select(.zone == $K8S_SUP_ZONE3).zone' /tmp/temp_zones.json)
if [ -z "${VKSZone3}" ]
then
        echo "Error: Could not fetch zone - ${K8S_SUP_ZONE3} . Please validate!!"
        exit 1
fi

################################################
# Get network details from vCenter
###############################################
echo "Searching for Network portgroups ${K8S_MGMT_PORTGROUP1}, ${K8S_MGMT_PORTGROUP2}, ${K8S_MGMT_PORTGROUP3} ..."
response=$(curl -ks --write-out "%{http_code}" -X GET  -H "${HEADER_SESSIONID}" https://${VCENTER_HOSTNAME}/api/vcenter/network --output /tmp/temp_networkportgroups.json)
if [[ "${response}" -ne 200 ]] ; then
  echo "Error: Could not fetch network details. Please validate!!"
  exit 1
fi

export VKS_MGMT_NETWORK1=$(jq -r --arg K8S_MGMT_PORTGROUP1 "$K8S_MGMT_PORTGROUP1" '.[]| select(.name == $K8S_MGMT_PORTGROUP1)|.network' /tmp/temp_networkportgroups.json)
export VKS_MGMT_NETWORK2=$(jq -r --arg K8S_MGMT_PORTGROUP2 "$K8S_MGMT_PORTGROUP2" '.[]| select(.name == $K8S_MGMT_PORTGROUP2)|.network' /tmp/temp_networkportgroups.json)
export VKS_MGMT_NETWORK3=$(jq -r --arg K8S_MGMT_PORTGROUP3 "$K8S_MGMT_PORTGROUP3" '.[]| select(.name == $K8S_MGMT_PORTGROUP3)|.network' /tmp/temp_networkportgroups.json)
export VKS_WKLD_NETWORK=$(jq -r --arg K8S_WKD0_PORTGROUP "$K8S_WKD0_PORTGROUP" '.[]| select(.name == $K8S_WKD0_PORTGROUP)|.network' /tmp/temp_networkportgroups.json)

if [ -z "${VKS_MGMT_NETWORK1}" ]
then
        echo "Error: Could not fetch portgroup - ${K8S_MGMT_PORTGROUP1} . Please validate!!"
        exit 1
fi
if [ -z "${VKS_MGMT_NETWORK2}" ]
then
        echo "Error: Could not fetch portgroup - ${K8S_MGMT_PORTGROUP2} . Please validate!!"
        exit 1
fi
if [ -z "${VKS_MGMT_NETWORK3}" ]
then
        echo "Error: Could not fetch portgroup - ${K8S_MGMT_PORTGROUP3} . Please validate!!"
        exit 1
fi

################################################
# Get contentlibrary details from vCenter
###############################################

echo "Searching for Content Library ${K8S_CONTENT_LIBRARY} ..."
response=$(curl -ks --write-out "%{http_code}" -X POST -H "${HEADER_SESSIONID}" -H "${HEADER_CONTENTTYPE}" -d "$(content_library_json)" https://${VCENTER_HOSTNAME}/api/content/library?action=find --output /tmp/temp_contentlib.json)
if [[ "${response}" -ne 200 ]] ; then
        echo "Error: Could not fetch content librarys. Please validate!!"
        exit 1
fi

export VKSContentLibrary=$(jq -r '.[]' /tmp/temp_contentlib.json)
if [ -z "${VKSContentLibrary}" ]
then
        echo "Error: Could not fetch content library - ${K8S_CONTENT_LIBRARY} . Please validate!!"
        exit 1
fi

################################################
# Get NSXALB CA CERT
###############################################
if [ ${DEPLOYMENT_TYPE} == "AVI" ]
then
        echo "Getting NSX ALB CA Certificate for  ${AVI_CONTROLLER} ..."
        openssl s_client -showcerts -connect ${AVI_CONTROLLER}:443  </dev/null 2>/dev/null|sed -ne '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' > /tmp/temp_avi-ca.cert
        if [ ! -s /tmp/temp_avi-ca.cert ]
        then
                echo "Error: Could not connect to the NSX ALB endpoint. Please validate!!"
                exit 1
        fi
        export AVI_CACERT=$(jq -sR . /tmp/temp_avi-ca.cert)

        if [ -z "${VKS_WKLD_NETWORK}" ]
        then
                echo "Error: Could not fetch portgroup - ${K8S_WKD0_PORTGROUP} . Please validate!!"
                exit 1
        fi
fi

################################################
# Complete NSX specific processing
###############################################
if [ ${DEPLOYMENT_TYPE} == "NSX" ]
then
        ################################################
        # Get NSX VDS from vCenter
        ###############################################
        echo "Searching for NSX compatible VDS switch ${$NSX_DVS_PORTGROUP}..."
        response=$(curl -ks --write-out "%{http_code}" -X POST  -H "${HEADER_SESSIONID}" https://${VCENTER_HOSTNAME}/api/vcenter/namespace-management/networks/nsx/distributed-switches?action=check_compatibility --output /tmp/temp_vds.json)
        if [[ "${response}" -ne 200 ]] ; then
                echo "Error: Could not fetch VDS details. Please validate!!"
                exit 1
        fi
        export NSX_DVS=$(jq -r --arg NSX_DVS_PORTGROUP "$NSX_DVS_PORTGROUP" '.[]| select((.compatible==true) and .name == $NSX_DVS_PORTGROUP)|.distributed_switch' /tmp/temp_vds.json)
        if [ -z "${NSX_DVS}" ]
        then
                echo "Error: Could not fetch NSX compatible VDS - ${NSX_DVS_PORTGROUP} . Please validate!!"
                exit 1
        fi

        ################################################
        # Get a Edge cluster ID from NSX Manager
        ###############################################
        echo "Searching for Edge cluster in NSX Manager ${$NSX_EDGE_CLUSTER} ..."
	    response=$(curl -ks --write-out "%{http_code}" -X GET -u "${NSX_USERNAME}:${NSX_PASSWORD}" -H 'Content-Type: application/json' https://${NSX_MANAGER}/api/v1/edge-clusters --output /tmp/temp_edgeclusters.json)
        if [[ "${response}" -ne 200 ]] ; then
                echo "Error: Could not fetch Edge Cluster details. Please validate!!"
                exit 1
	    fi
	    export NSX_EDGE_CLUSTER_ID=$(jq -r --arg NSX_EDGE_CLUSTER "$NSX_EDGE_CLUSTER" '.results[] | select( .display_name == $NSX_EDGE_CLUSTER)|.id' /tmp/temp_edgeclusters.json)
        if [ -z "${NSX_EDGE_CLUSTER_ID}" ]
        then
                echo "Error: Could not fetch NSX Edge cluster - ${NSX_EDGE_CLUSTER} . Please validate!!"
                exit 1
        fi

        ################################################
        # Get a Tier0 ID from NSX Manager
        ###############################################
        echo "Searching for Tier0 in NSX Manager ${$NSX_T0_GATEWAY}..."
	    response=$(curl -ks --write-out "%{http_code}" -X GET -u "${NSX_USERNAME}:${NSX_PASSWORD}" -H 'Content-Type: application/json' https://${NSX_MANAGER}/policy/api/v1/infra/tier-0s --output /tmp/temp_t0s.json)
        if [[ "${response}" -ne 200 ]] ; then
                echo "Error: Could not fetch Tier0 details. Please validate!!"
                exit 1
	    fi
	    export NSX_T0_GATEWAY_ID=$(jq -r --arg NSX_T0_GATEWAY "$NSX_T0_GATEWAY" '.results[] | select( .display_name == $NSX_T0_GATEWAY)|.id' /tmp/temp_t0s.json)
        if [ -z "${NSX_T0_GATEWAY_ID}" ]
        then
                echo "Error: Could not fetch NSX T0 - ${NSX_T0_GATEWAY} . Please validate!!"
                exit 1
        fi
fi

################################################
# Enable Supervisor
###############################################
envsubst < zone.json > temp_final.json
echo "Enabling Supervisor ..."
curl -ks --write-out "%{http_code}" -X POST -H "${HEADER_SESSIONID}" -H "${HEADER_CONTENTTYPE}" -d "@temp_final.json" https://${VCENTER_HOSTNAME}/api/vcenter/namespace-management/supervisors?action=enable_on_zones

#TODO while configuring, keep checking for status of Supervisor until ready
#curl -X POST 'https://vcsa-01.lab9.com/api/vcenter/namespace-management/supervisors/domain-c10?action=enable_on_compute_cluster'
rm -f /tmp/temp_*.*
rm -f temp_final.json
rm -f zone.json
#!/bin/bash
#Manage EKS CLuster and Node
# Help
#
#. Mandatory Options for script -f For CLuster Config file -b For build number -o Output File -c Cluster Name -v EKS Version -p VPC Config File Path
#. ./eks-config.sh -f <config-file> -b 1 -o <output-file> -c <cluster name> -v <eks-version> -p <vpc-config-file-path>
#
while getopts f:b:o:c:v:p: option
do
case "${option}"
in
b) BUILD=${OPTARG};;
c) CLUSTER_NAME=${OPTARG};;
f) CONFIG_FILE=${OPTARG};;
o) OUTPUT_FILE=${OPTARG};;
v) EKS_VERSION=${OPTARG};;
p) VPC_CONFIG_FILE_PATH=${OPTARG};;
*) 
esac
done

VPC_CONFIG_FILE=CODEBUILD_SRC_DIR_$VPC_CONFIG_FILE_PATH

$(cat ${!VPC_CONFIG_FILE}/StackOutput.json | jq -r 'keys[] as $k | "export CF_OUTPUT_\($k)=\(.[$k])"')

echo "Copying $CONFIG_FILE to $OUTPUT_FILE"
cp $CONFIG_FILE $OUTPUT_FILE

echo "Set Cluster Name"
yq w -i $OUTPUT_FILE metadata.name $CLUSTER_NAME

echo "Set Region"
yq w -i $OUTPUT_FILE metadata.region $CF_OUTPUT_REGION

echo "Set EKS Version"
yq w -i --tag '!!str' $OUTPUT_FILE metadata.version "${EKS_VERSION}"

echo "Creating VPC Object"
yq w -i $OUTPUT_FILE vpc.id $CF_OUTPUT_VPCID
yq w -i $OUTPUT_FILE vpc.subnets.private

for i in {1..5}; do
    AZ=CF_OUTPUT_PrivateSubnet$i\AZ
    ID=CF_OUTPUT_PrivateSubnet$i\ID
    if [ ${!ID} ] && [ ${!AZ} ] ; then
        echo "Adding Subnet ${!ID} in AZ ${!AZ} ]"
        yq w -i $OUTPUT_FILE vpc.subnets.private.${!AZ}\.id ${!ID}
    fi
done

echo "Counting number of NodeGroups"
NUMBER_OF_MANAGED_NODE_GROUPS=$( yq r $CONFIG_FILE --length managedNodeGroups)
NUMBER_OF_NODE_GROUPS=$( yq r $CONFIG_FILE --length nodeGroups)
echo "Found $NUMBER_OF_MANAGED_NODE_GROUPS managedNodeGroups"
echo "Found $NUMBER_OF_NODE_GROUPS NodeGroups"

for ((i=0;i<NUMBER_OF_MANAGED_NODE_GROUPS;i++)); do
    MANAGED_NODE_GROUP_NAME=$(yq r $CONFIG_FILE managedNodeGroups.[$i].name)
    MANAGED_NODE_GROUP_NEW_NAME=$(yq r $CONFIG_FILE managedNodeGroups.[$i].name)-$BUILD

    echo "Modifying Managed NodeGroup $MANAGED_NODE_GROUP_NAME To $MANAGED_NODE_GROUP_NEW_NAME"

    yq w -i $OUTPUT_FILE managedNodeGroups.[$i].name $MANAGED_NODE_GROUP_NEW_NAME
done

for ((i=0;i<NUMBER_OF_NODE_GROUPS;i++)); do
    NODE_GROUP_NAME=$(yq r $CONFIG_FILE nodeGroups.[$i].name)
    NODE_GROUP_NEW_NAME=$(yq r $CONFIG_FILE nodeGroups.[$i].name)-$BUILD

    echo "Modifying NodeGroup $NODE_GROUP_NAME To $NODE_GROUP_NEW_NAME"

    yq w -i $OUTPUT_FILE nodeGroups.[$i].name $NODE_GROUP_NEW_NAME
done

echo "Complete! Modified file can be found here $OUTPUT_FILE."




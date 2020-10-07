#!/bin/bash
#Build RDS Config File for RDS CF Template

while getopts o:c: option
do
case "${option}"
in
o) RDS_CONFIG_FILE=${OPTARG};;
c) VPC_CONFIG_FILE_PATH=${OPTARG};;
*) 
esac
done

VPC_CONFIG_FILE=CODEBUILD_SRC_DIR_$VPC_CONFIG_FILE_PATH

$(cat ${!VPC_CONFIG_FILE}/StackOutput.json | jq -r 'keys[] as $k | "export CF_OUTPUT_\($k)=\(.[$k])"')

AvailabilityZones=''
PrivateDBSubnets=''

for i in {1..5}; do
    AZ=CF_OUTPUT_PrivateSubnet$i\AZ
    ID=CF_OUTPUT_PrivateSubnet$i\ID
    if [ ${!ID} ] && [ ${!AZ} ] ; then
        if [ $AvailabilityZones ] ; then AvailabilityZones=${AvailabilityZones},${!AZ}; else AvailabilityZones=${!AZ}; fi
        if [ $PrivateDBSubnets ] ; then PrivateDBSubnets=${PrivateDBSubnets},${!ID}; else PrivateDBSubnets=${!ID}; fi
    fi
done

yq r config.yaml -j "RDS" | jq ". | { Parameters: . }" \
      | jq --arg CF_OUTPUT_VPCID "$CF_OUTPUT_VPCID" '.Parameters.VpcId = $CF_OUTPUT_VPCID' \
      | jq --arg AvailabilityZones "$AvailabilityZones" '.Parameters.AvailabilityZones = $AvailabilityZones' \
      | jq --arg PrivateDBSubnets "$PrivateDBSubnets" '.Parameters.PrivateDBSubnets = $PrivateDBSubnets' \
      > ${RDS_CONFIG_FILE}
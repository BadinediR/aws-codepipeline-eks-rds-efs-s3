#!/bin/bash
#Build RDS Config File for RDS CF Template

while getopts o:c: option
do
case "${option}"
in
o) EFS_CONFIG_FILE=${OPTARG};;
c) VPC_CONFIG_FILE_PATH=${OPTARG};;
*) 
esac
done

VPC_CONFIG_FILE=CODEBUILD_SRC_DIR_$VPC_CONFIG_FILE_PATH

$(cat ${!VPC_CONFIG_FILE}/StackOutput.json | jq -r 'keys[] as $k | "export CF_OUTPUT_\($k)=\(.[$k])"')

SUBNETS=''
SubnetNumber=0

for i in {1..5}; do
    ID=CF_OUTPUT_PrivateSubnet$i\ID
    if [ ${!ID} ] ; then
        if [ $SUBNETS ] ; then SUBNETS=${SUBNETS},${!ID}; else SUBNETS=${!ID}; fi
        SubnetNumber=$((SubnetNumber+1))
    fi
done

yq r config.yaml -j "EFS" | jq ". | { Parameters: . }" \
      | jq --arg CF_OUTPUT_VPCID "$CF_OUTPUT_VPCID" '.Parameters.VPC = $CF_OUTPUT_VPCID' \
      | jq --arg SUBNETS "$SUBNETS" '.Parameters.Subnets = $SUBNETS' \
      | jq --arg SubnetNumber "$SubnetNumber" '.Parameters.SubnetNumber = $SubnetNumber' \
      > ${EFS_CONFIG_FILE}
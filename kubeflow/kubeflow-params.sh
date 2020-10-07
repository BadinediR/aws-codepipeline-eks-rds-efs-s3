
export VPC_CONFIG_FILE=CODEBUILD_SRC_DIR_$SOURCE_CONFIGS

$(cat ${!VPC_CONFIG_FILE}/StackOutput.json | jq -r 'keys[] as $k | "export CF_OUTPUT_\($k)=\(.[$k])"')
$(cat $CODEBUILD_SRC_DIR_RDStackOutput/StackOutput.json | jq -r 'keys[] as $k | "export RDS_OUTPUT_\($k)=\(.[$k])"')

export CONFIG_YAML=$CODEBUILD_SRC_DIR\/config.yaml

# #Kubeflow feature toggle
export USE_S3=$(yq r $CONFIG_YAML 'Kubeflow.UseS3')
export USE_RDS=$(yq r $CONFIG_YAML 'Kubeflow.UseRDS')
export USE_EFS=$(yq r $CONFIG_YAML 'Kubeflow.UseEFS')
export USE_COGNITO=$(yq r $CONFIG_YAML 'Kubeflow.UseCognito')
export USE_EFS_CONTROL_PLANE=$(yq r $CONFIG_YAML 'Kubeflow.UseEFSControlPlane')


if "${USE_COGNITO}"; then
    # Alternatively, use the following kfctl configuration if you want to enable
    # authentication, authorization and multi-user:
    export CONFIG_URI=$(yq r $CONFIG_YAML 'Cognito.configURL')
    # Cognito Details
    export CERTARN=$(yq r $CONFIG_YAML 'Cognito.certARN')
    export cognitoAppClientId=$(yq r $CONFIG_YAML 'Cognito.cognitoAppClientId')
    export cognitoUserPoolArn=$(yq r $CONFIG_YAML 'Cognito.cognitoUserPoolArn')
    export cognitoUserPoolDomain=$(yq r $CONFIG_YAML 'Cognito.cognitoUserPoolDomain')
    export HostedZoneId=$(yq r $CONFIG_YAML 'Kubeflow.HostedZoneId')
    export Route53DomainName=$(yq r $CONFIG_YAML 'Kubeflow.Route53DomainName')

else
    # Use the following kfctl configuration file for the AWS setup without authentication:
    export CONFIG_URI=$(yq r $CONFIG_YAML 'Kubeflow.configURL')
fi

export ALBPolicyDocument=$(yq r $CONFIG_YAML 'Kubeflow.ALBPolicyDocument')

# Set an environment variable for your AWS cluster name, and set the name
# of the Kubeflow deployment to the same as the cluster name.
export KF_NAME=$(yq r $CONFIG_YAML 'EKS.ClusterName')

# Set the path to the base directory where you want to store one or more
# Kubeflow deployments. For example, /opt/.
# Then set the Kubeflow application directory for this deployment.
export BASE_DIR=/tmp
export KF_DIR=${BASE_DIR}/${KF_NAME}

export CONFIG_FILE=${KF_DIR}/kfctl_aws.yaml 

if "${USE_RDS}"; then
    # RDS Details 
    export RDSEndpoint=$RDS_OUTPUT_EndpointAddress
    export RDSPort=$RDS_OUTPUT_Port
    export DBUsername=$(echo $DB_PASSWORD | jq -r '.username')
    export DBPassword=$(echo $DB_PASSWORD | jq -r '.password')
    export DBName=$RDS_OUTPUT_DBName
fi

if "${USE_EFS}"; then
    # Application team EFS details
    export SETUP_EFS=true
    if [ ! -z $EXISTING_EFS ]; then
        export EFS_ID=$EXISTING_EFS
    else
        export EFS_ID=$(cat $CODEBUILD_SRC_DIR_EFSStackOutput/StackOutput.json | jq -r '.FileSystem')
    fi
fi

if "${USE_EFS_CONTROL_PLANE}"; then
    # Control plane EFS details
    if [ ! -z $EXISTING_EFS_CONTROL_PLANE ]; then
        export EFS_ID=$EXISTING_EFS_CONTROL_PLANE
    else
        export CONTROL_PLANE_EFS_ID=$(cat $CODEBUILD_SRC_DIR_EFSControlPlaneStackOutput/StackOutput.json | jq -r '.FileSystem')
    fi
fi
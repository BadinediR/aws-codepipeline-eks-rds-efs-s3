#!/bin/bash
#Install Kubeflow on AWS

TEMPLATE_FILE=pipeline/pipeline.yaml
DELETE_FILE=pipeline/pipeline-delete.yaml
VALUES_FILE=pipeline/pipeline-parameters.json

parse_yaml() {
    local prefix=$2
    local s
    local w
    local fs
    s='[[:space:]]*'
    w='[a-zA-Z0-9_]*'
    fs="$(echo @|tr @ '\034')"
    $(sed -ne "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s[:-]$s\(.*\)$s\$|\1$fs\2$fs\3|p" "$1" |
    awk -F"$fs" '{
    indent = length($1)/2;
    vname[indent] = $2;
    for (i in vname) {if (i > indent) {delete vname[i]}}
        if (length($3) > 0) {
            vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
            printf("export %s%s%s=%s\n", "'"$prefix"'",vn, $2, $3);
        }
    }')
}

parse_yaml config.yaml

delete () {
      aws codepipeline disable-stage-transition
      --pipeline-name ${Pipeline_StackName}-Pipeline
      --stage-name 'PullSourceConfigs'
      --transition-type 'Outbound'
      --reason 'Pipeline is being deleted'
      
      aws codebuild start-build \
        --project-name ${Pipeline_StackName}-DELETE
}

kubectl () {
  aws eks \
    --region ${Pipeline_Region} \
    update-kubeconfig \
    --name ${EKS_ClusterName}
}

deploy () {
    aws cloudformation deploy \
        --template-file $TEMPLATE_FILE \
        --stack-name ${Pipeline_StackName} \
        --parameter-overrides \
        StackName=${Pipeline_StackName} \
        BranchName=${Pipeline_BranchName} \
        RepositoryName=${Pipeline_RepositoryName} \
        EKSVersion=${EKS_EKSVersion} \
        UseExistingVPC=${EKS_UseExistingVPC} \
        UseRDS=${Kubeflow_UseRDS} \
        UseEFS=${Kubeflow_UseEFS} \
        UseEFSControlPlane=${Kubeflow_UseEFSControlPlane} \
        ExistingEFS=${Kubeflow_ExistingEFS} \
        ExistingEFSControlPlane=${Kubeflow_ExistingEFSControlPlane} \
        yqURL=${Packages_yq} \
        jqURL=${Packages_jq} \
        kfctlURL=${Packages_kfctl} \
        kubectlURL=${Packages_kubectl} \
        awsiamauthenticatorURL=${Packages_awsIamAuthenticator} \
        eksctlURL=${Packages_eksctl} \
        --capabilities CAPABILITY_NAMED_IAM
}

case $1 in

  delete)
    delete
    ;;

  redeploy)
    delete && create
    ;;

  deploy)
    deploy
    ;;

  kubectl)
    kubectl
    ;;

  *)
    echo "Unknown Command"
    ;;
esac
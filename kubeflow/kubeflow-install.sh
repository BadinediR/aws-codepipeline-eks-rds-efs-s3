#!/bin/bash
#
# Define functions to customize and install Kubeflow app.
#
set -x

if [[ ! $@ =~ ^\-.+ ]]
then
  echo "eks cluster_name and region must be provided using -c <AWS_CLUSTER_NAME> -r <AWS_REGION>" 1>&2
  exit 1
fi

while getopts :r:c: option;
do
    case "${option}"
    in
        r) AWS_REGION=${OPTARG};;
        c) AWS_CLUSTER_NAME=${OPTARG};;
        \?) echo "eks cluster_name and region must be provided using -c <AWS_CLUSTER_NAME> -r <AWS_REGION>" 1>&2
            exit 1
            ;;
    esac
done
export AWS_CLUSTER_NAME=${AWS_CLUSTER_NAME}
export AWS_REGION=${AWS_REGION}

################################ KubeFlow Install ################################

source $CODEBUILD_SRC_DIR\/kubeflow/kubeflow-params.sh

kubeflow_config_update(){
  # Create Working Dir For Kubeflow Install
  mkdir -p $KF_DIR
  # Download kubeflow config File 
  curl -L -o ${CONFIG_FILE} $CONFIG_URI 
  # If Cognito Param is set to True in Master Config File then Start configuring Kubeflow with Cognito
  if "${USE_COGNITO}"; then
     # Update Kubeflow config file to include Cognito Parameters
     replace_text_in_file "- eksctl-kubeflow-aws-nodegroup-ng-a2-NodeInstanceRole-xxxxx" "#- eksctl-kubeflow-aws-nodegroup-ng-a2-NodeInstanceRole-xxxxx" ${CONFIG_FILE}
     replace_text_in_file "arn:aws:acm:us-west-2:xxxxx:certificate/xxxxxxxxxxxxx-xxxx" ${CERTARN} ${CONFIG_FILE}
     replace_text_in_file "xxxxxbxxxxxx" ${cognitoAppClientId} ${CONFIG_FILE}
     replace_text_in_file "arn:aws:cognito-idp:us-west-2:xxxxx:userpool/us-west-2_xxxxxx" ${cognitoUserPoolArn} ${CONFIG_FILE}
     replace_text_in_file "your-user-pool" ${cognitoUserPoolDomain} ${CONFIG_FILE}
  else
    # Download Non Cognito file and update it to use for nodegroup roles
     replace_text_in_file "- eksctl-kubeflow-aws-nodegroup-ng-a2-NodeInstanceRole-xxxxxxx" "#- eksctl-kubeflow-aws-nodegroup-ng-a2-NodeInstanceRole-xxxxxxx" ${CONFIG_FILE}     
  fi
  # Update EKS Cluster details and Region in Config File
  replace_text_in_file 'kubeflow-aws' ${AWS_CLUSTER_NAME} ${CONFIG_FILE}
  replace_text_in_file "us-west-2" ${AWS_REGION} ${CONFIG_FILE}
  replace_text_in_file "roles:" "enablePodIamPolicy: true #roles:" ${CONFIG_FILE}
  
  if "${USE_RDS}"; then
    # Update RDS Security group to allow access from EKS nodes
    DB_SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --query 'SecurityGroups[*].GroupId' --filters "Name=tag-key,Values=DBClusterName" "Name=tag-value,Values=${DBName}" --output text --region ${AWS_REGION})
    INSTANCE_IDS=$(aws ec2 describe-instances --query 'Reservations[*].Instances[*].InstanceId' --filters "Name=tag-key,Values=eks:cluster-name" "Name=tag-value,Values=$AWS_CLUSTER_NAME" --output text --region ${AWS_REGION})
    for i in ${INSTANCE_IDS[@]}
    do
      security_group=$(aws ec2 describe-instances --instance-ids $i --region ${AWS_REGION} | jq -r '.Reservations[].Instances[].SecurityGroups[].GroupId')
      for group in ${security_group[@]}
      do
          aws ec2 authorize-security-group-ingress --group-id ${DB_SECURITY_GROUP_ID} --protocol tcp --port $RDSPort --source-group $group --region ${AWS_REGION}
          if [[ $? -ne 0 ]]; then
            echo "--------------------------------------------------------------------------------"
            echo "Error With Security Group addition to RDS Security Group: Either it already exists or not enough permissions"
            echo "DB Security Group:" ${DB_SECURITY_GROUP_ID} "Instance Security Group:" $group
            echo "--------------------------------------------------------------------------------"
          else
            echo 0
          fi
      done
    done  
    
    # Update Config File to use external mysql instead of local DB
    replace_text_in_file "db" "external-mysql" ${CONFIG_FILE}
    yq d -i ${CONFIG_FILE} spec.applications[name==mysql]
    yq w -i ${CONFIG_FILE} spec.applications[name==api-service].kustomizeConfig.overlays[+] external-mysql

    # KFCTL Build to download all kubeflow file to be updated for customizations. 
    kfctl build -V -f ${CONFIG_FILE}

    # Update Params.env and secrets.env with RDS mysql details for api-service and metadata
    echo "mysqlHost=${RDSEndpoint}" > ${KF_DIR}/kustomize/api-service/overlays/external-mysql/params.env
    echo "mysqlUser=${DBUsername}" >> ${KF_DIR}/kustomize/api-service/overlays/external-mysql/params.env
    echo "mysqlPassword=${DBPassword}" >> ${KF_DIR}/kustomize/api-service/overlays/external-mysql/params.env
    echo "MYSQL_HOST=${RDSEndpoint}" > ${KF_DIR}/kustomize/metadata/overlays/external-mysql/params.env
    echo "MYSQL_DATABASE=${DBName}" >> ${KF_DIR}/kustomize/metadata/overlays/external-mysql/params.env
    echo "MYSQL_PORT=${RDSPort}" >> ${KF_DIR}/kustomize/metadata/overlays/external-mysql/params.env
    echo "MYSQL_ALLOW_EMPTY_PASSWORD=true" >> ${KF_DIR}/kustomize/metadata/overlays/external-mysql/params.env
    echo "MYSQL_USERNAME=${DBUsername}" > ${KF_DIR}/kustomize/metadata/overlays/external-mysql/secrets.env
    echo "MYSQL_PASSWORD=${DBPassword}" >> ${KF_DIR}/kustomize/metadata/overlays/external-mysql/secrets.env

    # *‘db’ overlay in metadata ISSUE:*
    # ‘db’ overlay is created in ‘metadata’ Kustomize template anyway even if deleted in the step above. (Notified internal teams of that). For now, the fix is to delete it manually before applying the config
    rm -r ${KF_DIR}/kustomize/metadata/overlays/db

    # Move Katib to RDS

    # Update External MySql Details to be used by katib db manager
    yq w -i ${KF_DIR}/kustomize/katib-controller/base/katib-db-manager-deployment.yaml spec.template.spec.containers[name==katib-db-manager].env[+].name DB_USER
    yq w -i ${KF_DIR}/kustomize/katib-controller/base/katib-db-manager-deployment.yaml spec.template.spec.containers[name==katib-db-manager].env[name==DB_USER].value ${DBUsername}
    yq w -i ${KF_DIR}/kustomize/katib-controller/base/katib-db-manager-deployment.yaml spec.template.spec.containers[name==katib-db-manager].env[+].name KATIB_MYSQL_DB_HOST
    yq w -i ${KF_DIR}/kustomize/katib-controller/base/katib-db-manager-deployment.yaml spec.template.spec.containers[name==katib-db-manager].env[name==KATIB_MYSQL_DB_HOST].value ${RDSEndpoint}
    yq w -i ${KF_DIR}/kustomize/katib-controller/base/katib-db-manager-deployment.yaml spec.template.spec.containers[name==katib-db-manager].env[+].name KATIB_MYSQL_DB_DATABASE
    yq w -i ${KF_DIR}/kustomize/katib-controller/base/katib-db-manager-deployment.yaml spec.template.spec.containers[name==katib-db-manager].env[name==KATIB_MYSQL_DB_DATABASE].value katib
    yq d -i ${KF_DIR}/kustomize/katib-controller/base/katib-db-manager-deployment.yaml spec.template.spec.containers[name==katib-db-manager].env[name==DB_PASSWORD].valueFrom
    yq w -i ${KF_DIR}/kustomize/katib-controller/base/katib-db-manager-deployment.yaml spec.template.spec.containers[name==katib-db-manager].env[name==DB_PASSWORD].value ${DBPassword}

    # Remove Internal DB entries from kustomization
    replace_text_in_file "- katib-mysql-deployment.yaml" "#- katib-mysql-deployment.yaml" ${KF_DIR}/kustomize/katib-controller/base/kustomization.yaml
    replace_text_in_file "- katib-mysql-pvc.yaml" "#- katib-mysql-pvc.yaml" ${KF_DIR}/kustomize/katib-controller/base/kustomization.yaml
    replace_text_in_file "- katib-mysql-secret.yaml" "#- katib-mysql-secret.yaml" ${KF_DIR}/kustomize/katib-controller/base/kustomization.yaml
    replace_text_in_file "- katib-mysql-service.yaml" "#- katib-mysql-service.yaml" ${KF_DIR}/kustomize/katib-controller/base/kustomization.yaml
    rm ${KF_DIR}/kustomize/katib-controller/base/katib-mysql-deployment.yaml
    rm ${KF_DIR}/kustomize/katib-controller/base/katib-mysql-pvc.yaml
    rm ${KF_DIR}/kustomize/katib-controller/base/katib-mysql-secret.yaml
    rm ${KF_DIR}/kustomize/katib-controller/base/katib-mysql-service.yaml

    # create katib DB in external RDS. If DB. is not created Katib DB Manager POD will not come up
    kubectl run -it --rm --image=mysql:5.7 --restart=Never mysql-client -- mysql -h $RDSEndpoint -u $DBUsername -p$DBPassword -e "CREATE DATABASE katib;"

  fi

  # Move Minio server to EFS
  if "${USE_EFS_CONTROL_PLANE}"; then
    # Update security group for nodes to be able to access EFS 
    EFS_TARGET_MOUNT_IDS=$(aws efs describe-mount-targets --file-system-id ${CONTROL_PLANE_EFS_ID} --region ${AWS_REGION} --query MountTargets[*].MountTargetId --output text)
    for etm in ${EFS_TARGET_MOUNT_IDS}
    do
      security_group_efs=$(aws efs describe-mount-target-security-groups --mount-target-id ${etm} --region ${AWS_REGION} --query SecurityGroups[*] --output text)
      INSTANCE_IDS=$(aws ec2 describe-instances --query 'Reservations[*].Instances[*].InstanceId' --filters "Name=tag-key,Values=eks:cluster-name" "Name=tag-value,Values=$AWS_CLUSTER_NAME" --output text --region ${AWS_REGION})
      for i in ${INSTANCE_IDS[@]}
      do
        security_group=$(aws ec2 describe-instances --instance-ids $i --region ${AWS_REGION} | jq -r '.Reservations[].Instances[].SecurityGroups[].GroupId')
        for group in ${security_group[@]}
        do
          aws ec2 authorize-security-group-ingress --group-id ${security_group_efs} --protocol tcp --port 2049 --source-group $group --region ${AWS_REGION}
          if [[ $? -ne 0 ]]; then
            echo "--------------------------------------------------------------------------------"
            echo "Error With Security Group addition to EFS Security Group: Either it already exists or not enough permissions"
            echo "EFS Security Group:" ${security_group_efs} "Instance Security Group:" $group
            echo "--------------------------------------------------------------------------------"
          else
            echo 0
          fi
        done
      done
    done

    # Download kfctl files if not already done in previous steps. 
    if [[ ! -d ${KF_DIR}/kustomize ]]; then
      kfctl build -V -f ${CONFIG_FILE}
    fi
    # Clear any existing manifests and download latest 
    rm -rf manifests
    git clone https://github.com/kubeflow/manifests
    # Verify if kubeflow name space exists, if not then create it. 
    ns=`kubectl get namespace kubeflow --no-headers --output=go-template={{.metadata.name}}`
    if [[ $ns != "kubeflow" ]]; then
      echo "Namespace kubeflow not found, creating"
      kubectl create namespace kubeflow
    else
      echo "Namespace exists"
    fi

    # Install EFS Drives in EKS
    kubectl apply -k manifests/aws/aws-efs-csi-driver/base
    # Create Storage class for EFS
    kubectl apply -f $CODEBUILD_SRC_DIR\/EFS/efs-sc.yaml
    yq w -i $CODEBUILD_SRC_DIR\/EFS/efs-control-plane-pv.yaml spec.csi.volumeHandle ${CONTROL_PLANE_EFS_ID}
    kubectl apply -f $CODEBUILD_SRC_DIR\/EFS/efs-control-plane-pv.yaml
    # Check if minio PVC already exists and bound. This will be used for upgrade/reinstall scenarios
    minio_pvc_exists=`kubectl get pvc minio-pv-claim -n kubeflow -o yaml | yq r - status.phase`
    if [[ ! -z $minio_pvc_exists ]]; then 
      echo "Minio PVC Already Exists. Can not change it since it is immutable"
      kubectl delete deployment minio -n kubeflow 
      kubectl delete pvc minio-pv-claim --grace-period=0 --force -n kubeflow 
      kubectl delete pv efs-control-plane-pv
    fi
    yq w -i ${KF_DIR}/kustomize/minio/base/persistent-volume-claim.yaml spec.storageClassName "efs-sc"
    yq w -i ${KF_DIR}/kustomize/minio/base/persistent-volume-claim.yaml spec.volumeName efs-control-plane-pv
    yq d -i ${KF_DIR}/kustomize/minio/base/persistent-volume-claim.yaml spec.accessModes
    yq w -i ${KF_DIR}/kustomize/minio/base/persistent-volume-claim.yaml spec.accessModes[+] ReadWriteOnce
    yq w -i ${KF_DIR}/kustomize/minio/base/persistent-volume-claim.yaml spec.resources.requests.storage 20Gi 
    replace_text_in_file "minioPvName=.*" "minioPvName=efs-control-plane-pv" ${KF_DIR}/kustomize/minio/overlays/minioPd/params.env
  fi

 # Removing cert manager as it is not needed anymore.
  yq d -i ${CONFIG_FILE} spec.applications[name==cert-manager]
  kfctl apply -V -f ${CONFIG_FILE}

  # Create LB service for kubeflow access, It assumes that subnets are already properly tagged. 
  # Public subnet(if used)
  # Key                      Value
  # kubernetes.io/role/elb  1
  # 
  # Private Subnet
  # Key                              Value
  # kubernetes.io/role/internal-elb 1


  if "${USE_COGNITO}"; then
    # EKS Access to ALB Policy and service account
    ALBPolicyArn=$(aws iam create-policy --policy-name ${AWS_CLUSTER_NAME}-ALBIngressControllerIAMPolicy --policy-document ${ALBPolicyDocument} | jq -r '.Policy.Arn')

    # Create ALB service account
    eksctl create iamserviceaccount \
      --region ${AWS_REGION} \
      --name alb-ingress-controller \
      --namespace kubeflow \
      --cluster ${AWS_CLUSTER_NAME} \
      --attach-policy-arn ${ALBPolicyArn} \
      --override-existing-serviceaccounts \
      --approve

    # Update Ingress Gateway on kubeflow to use internal ALB instead of public facing. 
    kubectl get ingress -n istio-system istio-ingress -o=yaml > ingress.yaml
    yq w -i ingress.yaml metadata.annotations[alb.ingress.kubernetes.io/scheme] internal
    kubectl apply -f ingress.yaml
    ingress_pod_name=`kubectl get pods -n istio-system | grep -i ingressgateway | awk '{print $1}'`
    kubectl delete pods $ingress_pod_name -n istio-system
    rm ingress.yaml
    echo "Waiting for ALB to be created"
    sleep 300
    # Update Route 53 with the newly created ALB Details. 
    # Currently only CNAMES are updated. Existing A record for root domain needs to be updated manually. 
    LB_URL=$(kubectl get ingress istio-ingress -n istio-system -o yaml | yq r - status.loadBalancer.ingress | awk -F: '{print $2}')
    if [[ ! -z ${LB_URL} ]]; then
      #aws route53 change-resource-record-sets --hosted-zone-id ${HostedZoneId}  --change-batch '{ "Comment": "Creating RecordSet", "Changes": [ { "Action": "UPSERT", "ResourceRecordSet": { "Name": "'${Route53DomainName}'", "Type": "A", "ResourceRecords": [ { "Value": "'"$LB_URL"'" } ] } } ] }'
      #aws route53 change-resource-record-sets --hosted-zone-id ${HostedZoneId}  --change-batch '{ "Comment": "Creating RecordSet", "Changes": [ { "Action": "UPSERT", "ResourceRecordSet": { "Name": "*.'${Route53DomainName}'", "Type": "CNAME", "TTL": 300, "ResourceRecords": [ { "Value": "'"$LB_URL"'" } ] } } ] }'
      #aws route53 change-resource-record-sets --hosted-zone-id ${HostedZoneId}  --change-batch '{ "Comment": "Creating RecordSet", "Changes": [ { "Action": "UPSERT", "ResourceRecordSet": { "Name": "*.default.'${Route53DomainName}'", "Type": "CNAME", "TTL": 300, "ResourceRecords": [ { "Value": "'"$LB_URL"'" } ] } } ] }'
      AlbHostedZoneId=$(aws elbv2 describe-load-balancers --region ${AWS_REGION} | jq ".LoadBalancers[] | select(.DNSName==\"$LB_URL\") | .CanonicalHostedZoneId"|awk -F\" {'print $2'})
      aws route53 change-resource-record-sets --hosted-zone-id ${HostedZoneId}  --change-batch '{ "Comment": "Creating RecordSet", "Changes": [ { "Action": "UPSERT", "ResourceRecordSet": { "Name": "'${Route53DomainName}'", "Type": "A", "AliasTarget": { "DNSName": "'"$LB_URL"'", "HostedZoneId": "'"$AlbHostedZoneId"'", "EvaluateTargetHealth": false }  } } ] }'
      aws route53 change-resource-record-sets --hosted-zone-id ${HostedZoneId}  --change-batch '{ "Comment": "Creating RecordSet", "Changes": [ { "Action": "UPSERT", "ResourceRecordSet": { "Name": "\\052.'${Route53DomainName}'", "Type": "A", "AliasTarget": { "DNSName": "'"$LB_URL"'", "HostedZoneId": "'"$AlbHostedZoneId"'", "EvaluateTargetHealth": false }  } } ] }'
      aws route53 change-resource-record-sets --hosted-zone-id ${HostedZoneId}  --change-batch '{ "Comment": "Creating RecordSet", "Changes": [ { "Action": "UPSERT", "ResourceRecordSet": { "Name": "\\052.default.'${Route53DomainName}'", "Type": "A", "AliasTarget": { "DNSName": "'"$LB_URL"'", "HostedZoneId": "'"$AlbHostedZoneId"'", "EvaluateTargetHealth": false }  } } ] }'
    fi
  else
    # Annotate to create internal ELB in case Cognito is not used. This option will be with out authtication and should only be used for internal testing. 
    kubectl annotate service --overwrite -n istio-system istio-ingressgateway service.beta.kubernetes.io/aws-load-balancer-internal=true
    kubectl patch service -n istio-system istio-ingressgateway -p '{"spec": {"type": "LoadBalancer"}}'
  fi

  # Place holder for S3 config once it is released in upstream Kubeflow. 
  if "${USE_S3}"; then
    # AWS S3 Access Service Account 
    eksctl create iamserviceaccount \
                  --name ${AWS_CLUSTER_NAME}-S3\
                  --namespace default \
                  --cluster $AWS_CLUSTER_NAME \
                  --attach-policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess \
                  --approve \
                  --region ${AWS_REGION}
  fi

  # AWS EFS Setup on Kubeflow cluster, similar setup to control plane EFS, however this will be used by application teams. 
  if "${USE_EFS}"; then
    EFS_TARGET_MOUNT_IDS=$(aws efs describe-mount-targets --file-system-id ${EFS_ID} --region ${AWS_REGION} --query MountTargets[*].MountTargetId --output text)
    for etm in ${EFS_TARGET_MOUNT_IDS}
    do
      security_group_efs=$(aws efs describe-mount-target-security-groups --mount-target-id ${etm} --region ${AWS_REGION} --query SecurityGroups[*] --output text)
      INSTANCE_IDS=$(aws ec2 describe-instances --query 'Reservations[*].Instances[*].InstanceId' --filters "Name=tag-key,Values=eks:cluster-name" "Name=tag-value,Values=$AWS_CLUSTER_NAME" --output text --region ${AWS_REGION})
      for i in ${INSTANCE_IDS[@]}
      do
        security_group=$(aws ec2 describe-instances --instance-ids $i --region ${AWS_REGION} | jq -r '.Reservations[].Instances[].SecurityGroups[].GroupId')
        for group in ${security_group[@]}
        do
          aws ec2 authorize-security-group-ingress --group-id ${security_group_efs} --protocol tcp --port 2049 --source-group $group --region ${AWS_REGION}
          if [[ $? -ne 0 ]]; then
            echo "--------------------------------------------------------------------------------"
            echo "Error With Security Group addition to EFS Security Group: Either it already exists or not enough permissions"
            echo "EFS Security Group:" ${security_group_efs} "Instance Security Group:" $group
            echo "--------------------------------------------------------------------------------"
          else
            echo 0
          fi
        done
      done
    done
    rm -rf manifests
    git clone https://github.com/kubeflow/manifests
    kubectl apply -k manifests/aws/aws-efs-csi-driver/base
    kubectl apply -f $CODEBUILD_SRC_DIR\/EFS/efs-sc.yaml
    yq w -i $CODEBUILD_SRC_DIR\/EFS/efs-pv.yaml spec.csi.volumeHandle ${EFS_ID}
    kubectl apply -f $CODEBUILD_SRC_DIR\/EFS/efs-pv.yaml
  fi
}


################################ EKS Cluster Logging ################################
install_fluentd_cloudwatch() {
  # Install Fluentd-Cloudwatch Kubernetes agents.
  cp kubeflow/fluentd-cloudwatch.yaml-master kubeflow/fluentd-cloudwatch.yaml
  replace_text_in_file "{{region_name}}" ${AWS_REGION} kubeflow/fluentd-cloudwatch.yaml
  replace_text_in_file "{{cluster_name}}" ${AWS_CLUSTER_NAME} kubeflow/fluentd-cloudwatch.yaml
  kubectl apply -f kubeflow/fluentd-cloudwatch.yaml

}

################################ EKS Cluster Update Utils ################################

replace_text_in_file() {
  local FIND_TEXT=$1
  local REPLACE_TEXT=$2
  local SRC_FILE=$3

  sed -i.bak "s@${FIND_TEXT}@${REPLACE_TEXT}@" ${SRC_FILE}
  rm $SRC_FILE.bak
}


################################ IAM Updates ################################

apply_aws_policies() {

  n=0
  until [ "$n" -ge 5 ]
  do
    AWS_NODEGROUP_ROLE_NAMES=$(aws iam list-roles \
      | jq -r ".Roles[] \
      | select(.RoleName \
      | startswith(\"eksctl-${AWS_CLUSTER_NAME}\") and contains(\"NodeInstanceRole\")) \
      .RoleName")
    AWS_NODEGROUP_ROLE_NAMES=$(echo ${AWS_NODEGROUP_ROLE_NAMES} | sed -e 's/ /,/g')

    if [[ -z "$AWS_NODEGROUP_ROLE_NAMES" ]]; then
      echo "AWS_NODEGROUP_ROLE_NAMES cannot be empty. Error list roles from new created cluster"
      echo "Retry $n after 5 secs"
      n=$((n+1)) 
    else
      break
    fi  
    sleep 5
  done
  
  attach_inline_policy iam_alb_ingress_policy ${KF_DIR}/aws_config/iam_alb_ingress_policy.json
  attach_inline_policy iam_cloudwatch_policy ${KF_DIR}/aws_config/iam_cloudwatch_policy.json
}

attach_inline_policy() {
  declare -r POLICY_NAME="$1" POLICY_DOCUMENT="$2"

  for IAM_ROLE in ${AWS_NODEGROUP_ROLE_NAMES//,/ }
  do
    echo "Attach inline policy $POLICY_NAME for iam role $IAM_ROLE"
    if ! aws iam put-role-policy --role-name $IAM_ROLE --policy-name $POLICY_NAME --policy-document file://${POLICY_DOCUMENT}; then
        echo "Unable to attach iam inline policy $POLICY_NAME to role $IAM_ROLE" >&2
        return 1
    fi
  done

  return 0
}

################################ arguments and setup validation ################################

check_aws_cli() {
  if ! which "aws" &>/dev/null && ! type -a "aws" &>/dev/null ; then
    echo "You don't have awscli installed. Please install aws cli. https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-install.html"
    exit 1
  fi
}

check_eksctl_cli() {
  # eskctl is recommended to create EKS clusters now. This will be replaced by awscli eventually.
  if ! which "eksctl" &>/dev/null && ! type -a "eksctl" &>/dev/null ; then
    echo "You don't have eksctl installed. Please install eksctl cli. https://eksctl.io/"
    exit 1
  fi
}

check_aws_iam_authenticator() {
  if ! which "aws-iam-authenticator" &>/dev/null && ! type -a "aws-iam-authenticator" &>/dev/null ; then
    echo "You don't have aws-iam-authenticator installed. Please install aws-iam-authenticator. https://docs.aws.amazon.com/eks/latest/userguide/install-aws-iam-authenticator.html"
    exit 1
  fi
}

check_jq() {
  if ! which "jq" &>/dev/null && ! type -a "jq" &>/dev/null ; then
    echo "You don't have jq installed. Please install jq. https://stedolan.github.io/jq/download/"
    exit 1
  fi
}

check_aws_credential() {
  if ! aws sts get-caller-identity >/dev/null ; then
    echo "aws get caller identity failed. Please check the aws credentials provided and try again."
    exit 1
  fi
}

check_kfctl() {
  if ! which "kfctl" &>/dev/null && ! type -a "kfctl" &>/dev/null ; then
    echo "You don't have kfctl installed. Please install kfctl. https://www.kubeflow.org/docs/aws/deploy/install-kubeflow/."
    exit 1
  fi
}


# Verify all packages need for script are installed. 
check_aws_setups() {
  check_aws_cli
  check_eksctl_cli
  check_jq
  check_aws_iam_authenticator
  check_aws_credential
  check_kfctl
}


# Call Functions
check_aws_setups
kubeflow_config_update
apply_aws_policies
install_fluentd_cloudwatch

#Cleanup
rm -Rf ${BASE_DIR}/tmp.kfctl-${KFCTL_VERSION} 


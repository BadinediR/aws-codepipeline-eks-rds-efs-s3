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

################################ KubeFlow Uninstall ################################

source $CODEBUILD_SRC_DIR\/kubeflow/kubeflow-params.sh

kubeflow_config_update(){

  mkdir -p $KF_DIR
  curl -L -o ${CONFIG_FILE} $CONFIG_URI 
  #replace_text_in_file "region: us-west-2" "region: us-west-2$/\n      enablePodIamPolicy: true" ${CONFIG_FILE}
  replace_text_in_file "- eksctl-kubeflow-aws-nodegroup-ng-a2-NodeInstanceRole-xxxxx" "#- eksctl-kubeflow-aws-nodegroup-ng-a2-NodeInstanceRole-xxxxx" ${CONFIG_FILE}
  replace_text_in_file 'kubeflow-aws' ${AWS_CLUSTER_NAME} ${CONFIG_FILE}
  replace_text_in_file "us-west-2" ${AWS_REGION} ${CONFIG_FILE}
  replace_text_in_file "roles:" "enablePodIamPolicy: true #roles:" ${CONFIG_FILE}

  if "${USE_COGNITO}"; then
     replace_text_in_file "- eksctl-kubeflow-aws-nodegroup-ng-a2-NodeInstanceRole-xxxxx" "#- eksctl-kubeflow-aws-nodegroup-ng-a2-NodeInstanceRole-xxxxx" ${CONFIG_FILE}
     replace_text_in_file "arn:aws:acm:us-west-2:xxxxx:certificate/xxxxxxxxxxxxx-xxxx" ${CERTARN} ${CONFIG_FILE}
     replace_text_in_file "xxxxxbxxxxxx" ${cognitoAppClientId} ${CONFIG_FILE}
     replace_text_in_file "arn:aws:cognito-idp:us-west-2:xxxxx:userpool/us-west-2_xxxxxx" ${cognitoUserPoolArn} ${CONFIG_FILE}
     replace_text_in_file "your-user-pool" ${cognitoUserPoolDomain} ${CONFIG_FILE}
  else
     replace_text_in_file "- eksctl-kubeflow-aws-nodegroup-ng-a2-NodeInstanceRole-xxxxxxx" "#- eksctl-kubeflow-aws-nodegroup-ng-a2-NodeInstanceRole-xxxxxxx" ${CONFIG_FILE}     
  fi
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
          out=("aws ec2 revoke-security-group-ingress --group-id ${DB_SECURITY_GROUP_ID} --protocol tcp --port $RDSPort --source-group $group --region ${AWS_REGION}")
          if "${myCmd[@]}"; then
          echo ok
          else
            #err="$(cat error.file)"
            echo "Security Group already removed of inbound "
      # do domething with $err
          fi
      done
    done  
    
    # Update Config File to use external mysql instead of local DB
    replace_text_in_file "db" "external-mysql" ${CONFIG_FILE}
    yq d -i ${CONFIG_FILE} spec.applications[name==mysql]
    yq w -i ${CONFIG_FILE} spec.applications[name==api-service].kustomizeConfig.overlays[+] external-mysql

    kfctl build -V -f ${CONFIG_FILE}

    # Update Params.env and secrets.env with RDS mysql details
    echo "mysqlHost=${RDSEndpoint}" > ${KF_DIR}/kustomize/api-service/overlays/external-mysql/params.env
    echo "mysqlUser=${DBUsername}" >> ${KF_DIR}/kustomize/api-service/overlays/external-mysql/params.env
    echo "mysqlPassword=${DBPassword}" >> ${KF_DIR}/kustomize/api-service/overlays/external-mysql/params.env
    echo "MYSQL_HOST=external_host" > ${KF_DIR}/kustomize/metadata/overlays/external-mysql/params.env
    echo "MYSQL_DATABASE=${RDSEndpoint}" >> ${KF_DIR}/kustomize/metadata/overlays/external-mysql/params.env
    echo "MYSQL_PORT=${RDSPort}" >> ${KF_DIR}/kustomize/metadata/overlays/external-mysql/params.env
    echo "MYSQL_ALLOW_EMPTY_PASSWORD=true" >> ${KF_DIR}/kustomize/metadata/overlays/external-mysql/params.env
    echo "MYSQL_USERNAME=${DBUsername}" > ${KF_DIR}/kustomize/metadata/overlays/external-mysql/secrets.env
    echo "MYSQ_PASSWORD=${DBPassword}" >> ${KF_DIR}/kustomize/metadata/overlays/external-mysql/secrets.env

    # *‘db’ overlay in metadata ISSUE:*
    # ‘db’ overlay is created in ‘metadata’ Kustomize template anyway even if deleted in the step above. (Notified internal teams of that). For now, the fix is to delete it manually before applying the config
    rm -r ${KF_DIR}/kustomize/metadata/overlays/db

    # Move Katib to RDS
    rm ${KF_DIR}/kustomize/katib-controller/base/katib-mysql-deployment.yaml
    rm ${KF_DIR}/kustomize/katib-controller/base/katib-mysql-pvc.yaml
    rm ${KF_DIR}/kustomize/katib-controller/base/katib-mysql-secret.yaml
    rm ${KF_DIR}/kustomize/katib-controller/base/katib-mysql-service.yaml

    yq w -i ${KF_DIR}/kustomize/katib-controller/base/katib-db-manager-deployment.yaml spec.template.spec.containers[name==katib-db-manager].env[+].name DB_USER
    yq w -i ${KF_DIR}/kustomize/katib-controller/base/katib-db-manager-deployment.yaml spec.template.spec.containers[name==katib-db-manager].env[name==DB_USER].value ${DBUsername}

    yq w -i ${KF_DIR}/kustomize/katib-controller/base/katib-db-manager-deployment.yaml spec.template.spec.containers[name==katib-db-manager].env[+].name KATIB_MYSQL_DB_HOST
    yq w -i ${KF_DIR}/kustomize/katib-controller/base/katib-db-manager-deployment.yaml spec.template.spec.containers[name==katib-db-manager].env[name==KATIB_MYSQL_DB_HOST].value ${RDSEndpoint}

    yq w -i ${KF_DIR}/kustomize/katib-controller/base/katib-db-manager-deployment.yaml spec.template.spec.containers[name==katib-db-manager].env[+].name KATIB_MYSQL_DB_DATABASE
    yq w -i ${KF_DIR}/kustomize/katib-controller/base/katib-db-manager-deployment.yaml spec.template.spec.containers[name==katib-db-manager].env[name==KATIB_MYSQL_DB_DATABASE].value katib

    yq d -i ${KF_DIR}/kustomize/katib-controller/base/katib-db-manager-deployment.yaml spec.template.spec.containers[name==katib-db-manager].env[name==DB_PASSWORD].valueFrom
    yq w -i ${KF_DIR}/kustomize/katib-controller/base/katib-db-manager-deployment.yaml spec.template.spec.containers[name==katib-db-manager].env[name==DB_PASSWORD].value ${DBPassword}

    replace_text_in_file "- katib-mysql-deployment.yaml" "#- katib-mysql-deployment.yaml" ${KF_DIR}/kustomize/katib-controller/base/kustomization.yaml
    replace_text_in_file "- katib-mysql-pvc.yaml" "#- katib-mysql-pvc.yaml" ${KF_DIR}/kustomize/katib-controller/base/kustomization.yaml
    replace_text_in_file "- katib-mysql-secret.yaml" "#- katib-mysql-secret.yaml" ${KF_DIR}/kustomize/katib-controller/base/kustomization.yaml
    replace_text_in_file "- katib-mysql-service.yaml" "#- katib-mysql-service.yaml" ${KF_DIR}/kustomize/katib-controller/base/kustomization.yaml

  fi

  if "${USE_EFS_CONTROL_PLANE}"; then
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
          out=("aws ec2 revoke-security-group-ingress --group-id ${security_group_efs} --protocol tcp --port 2049 --source-group $group --region ${AWS_REGION}")
          if "${myCmd[@]}"; then
            echo ok
          else
            echo "Security Group already removed"
          fi
        done
      done
    done    

    if [[ ! -d ${KF_DIR}/kustomize ]]; then
      kfctl build -V -f ${CONFIG_FILE}
    fi
    rm -rf manifests
    git clone https://github.com/kubeflow/manifests

    yq w -i efs/efs-control-plane-pv.yaml spec.csi.volumeHandle ${CONTROL_PLANE_EFS_ID}
    #kubectl delete -f efs/efs-control-plane-pv.yaml
    kubectl delete -k manifests/aws/aws-efs-csi-driver/base
    kubectl delete -f efs/efs-sc.yaml
    yq w -i ${KF_DIR}/kustomize/minio/overlays/minioPd/persistent-volume-claim.yaml spec.volumeName efs-control-plane-pv
    yq w -i ${KF_DIR}/kustomize/minio/overlays/minioPd/persistent-volume-claim.yaml spec.storageClassName "efs-sc"
    yq w -i ${KF_DIR}/kustomize/minio/base/persistent-volume-claim.yaml spec.storageClassName "efs-sc"
    yq w -i ${KF_DIR}/kustomize/minio/base/persistent-volume-claim.yaml spec.volumeName efs-control-plane-pv
    yq w -i ${KF_DIR}/kustomize/minio/base/persistent-volume-claim.yaml spec.accessModes[+] ReadWriteOnce
    yq w -i ${KF_DIR}/kustomize/minio/base/persistent-volume-claim.yaml spec.resources.requests.storage 20Gi

    replace_text_in_file "minioPvName=.*" "minioPvName=efs-control-plane-pv" ${KF_DIR}/kustomize/minio/overlays/minioPd/params.env

  fi

  yq d -i ${CONFIG_FILE} spec.applications[name==cert-manager]
  kfctl delete -V -f ${CONFIG_FILE}

  # Create LB service for kubeflow access, It assumes that subnets are already properly tagged. 
  # Public subnet
  # Key                      Value
  # kubernetes.io/role/elb  1
  # 
  # Private Subnet
  # Key                              Value
  # kubernetes.io/role/internal-elb 1
  #kubectl annotate service --overwrite -n istio-system istio-ingressgateway service.beta.kubernetes.io/aws-load-balancer-internal=true
  #kubectl patch service -n istio-system istio-ingressgateway -p '{"spec": {"type": "LoadBalancer"}}'
  
  if "${USE_COGNITO}"; then

    LB_URL=$(kubectl get ingress istio-ingress -n istio-system -o yaml | yq r - status.loadBalancer.ingress | awk -F: '{print $2}')
    if [[ -z ${LB_URL} ]]; then
      AlbHostedZoneId=$(aws elbv2 describe-load-balancers --region ${AWS_REGION} | jq ".LoadBalancers[] | select(.DNSName==\"$LB_URL\") | .CanonicalHostedZoneId"|awk -F\" {'print $2'})
      aws route53 change-resource-record-sets --hosted-zone-id ${HostedZoneId}  --change-batch '{ "Comment": "Creating RecordSet", "Changes": [ { "Action": "DELETE", "ResourceRecordSet": { "Name": "\\052.default.'${Route53DomainName}'", "Type": "A", "AliasTarget": { "DNSName": "'"$LB_URL"'", "HostedZoneId": "'"$AlbHostedZoneId"'", "EvaluateTargetHealth": false }  } } ] }'
      aws route53 change-resource-record-sets --hosted-zone-id ${HostedZoneId}  --change-batch '{ "Comment": "Creating RecordSet", "Changes": [ { "Action": "DELETE", "ResourceRecordSet": { "Name": "\\052.'${Route53DomainName}'", "Type": "A", "AliasTarget": { "DNSName": "'"$LB_URL"'", "HostedZoneId": "'"$AlbHostedZoneId"'", "EvaluateTargetHealth": false }  } } ] }'
      aws route53 change-resource-record-sets --hosted-zone-id ${HostedZoneId}  --change-batch '{ "Comment": "Creating RecordSet", "Changes": [ { "Action": "UPSERT", "ResourceRecordSet": { "Name": "'${Route53DomainName}'", "Type": "A", "TTL": 300, "ResourceRecords": [ { "Value": "127.0.0.1" } ] } } ] }'

    fi

    eksctl delete iamserviceaccount --name alb-ingress-controller --namespace kubeflow --cluster ${AWS_CLUSTER_NAME} --region ${AWS_REGION}
    sleep 10
    AccountId=$(aws sts get-caller-identity --query 'Account' --output text)
    out=(aws iam delete-policy --policy-arn arn:aws:iam::${AccountId}:policy/ALBIngressControllerIAMPolicy-${AWS_CLUSTER_NAME})

    kubectl get ingress -n istio-system istio-ingress -o=yaml > ingress.yaml
    yq w -i ingress.yaml metadata.annotations[alb.ingress.kubernetes.io/scheme] internal
    kubectl delete -f ingress.yaml

  else
    kubectl annotate service --overwrite -n istio-system istio-ingressgateway service.beta.kubernetes.io/aws-load-balancer-internal=false
    kubectl patch service -n istio-system istio-ingressgateway -p '{"spec": {"type": "LoadBalancer"}}'
  fi

  if "${USE_S3}" = "True"; then
    # AWS S3 Access Service Account 
    eksctl delete iamserviceaccount \
                  --name ${AWS_CLUSTER_NAME}-s3\
                  --namespace default \
                  --cluster $AWS_CLUSTER_NAME \
                  --region ${AWS_REGION}
  fi

  if "${USE_EFS}"; then
    # AWS EFS Setup on Kubeflow cluster
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
          out=("aws ec2 revoke-security-group-ingress --group-id ${security_group_efs} --protocol tcp --port 2049 --source-group $group --region ${AWS_REGION}")
          if "${myCmd[@]}"; then
            echo ok
          else
            echo "Security Group already removed"
          fi
        done
      done
    done    
    rm -rf manifests
    git clone https://github.com/kubeflow/manifests
    kubectl delete -k manifests/aws/aws-efs-csi-driver/base
    kubectl delete -f efs/efs-sc.yaml
    yq w -i efs/efs-pv.yaml spec.csi.volumeHandle ${EFS_ID}
    kubectl delete -f efs/efs-pv.yaml
  fi

  if "${USE_RDS}"; then
    # Update Params.env and secrets.env with RDS mysql details
    echo "MYSQL_HOST=external_host" > ${KF_DIR}/kustomize/metadata/overlays/external-mysql/params.env
    echo "MYSQL_DATABASE=${RDSEndpoint}" >> ${KF_DIR}/kustomize/metadata/overlays/external-mysql/params.env
    echo "MYSQL_PORT=${RDSPort}" >> ${KF_DIR}/kustomize/metadata/overlays/external-mysql/params.env
    echo "MYSQL_ALLOW_EMPTY_PASSWORD=true" >> ${KF_DIR}/kustomize/metadata/overlays/external-mysql/params.env
    echo "MYSQL_USERNAME=${DBUsername}" > ${KF_DIR}/kustomize/metadata/overlays/external-mysql/secrets.env
    echo "MYSQ_PASSWORD=${DBPassword}" >> ${KF_DIR}/kustomize/metadata/overlays/external-mysql/secrets.env
    kfctl delete -V -f ${CONFIG_FILE} --force-deletion
    kubectl -n istio-system delete all --all
    kubectl -n auth delete all --all
    kubectl -n cert-manager delete all --all
    kubectl -n knative-serving delete all --all
    #kubectl delete namespace istio-system
    #kubectl delete namespace knative-serving
  fi
}


################################ EKS Cluster Logging ################################
uninstall_fluentd_cloudwatch() {
  # Install Fluentd-Cloudwatch Kubernetes agents.

  replace_text_in_file "{{region_name}}" ${AWS_REGION} kubeflow/fluentd-cloudwatch.yaml
  replace_text_in_file "{{cluster_name}}" ${AWS_CLUSTER_NAME} kubeflow/fluentd-cloudwatch.yaml
  if ! kubectl delete -f kubeflow/fluentd-cloudwatch.yaml; then
     echo "Unable to delete Fluentd" >&2
  fi
}

################################ EKS Cluster Update Utils ################################

wait_cluster_update() {
  local update_id=$1
  until [ $(aws eks describe-update --name ${AWS_CLUSTER_NAME} --region ${AWS_REGION} --update-id ${update_id} | jq -r '.update.status') = 'Successful' ]; do
    echo "eks is updating cluster configuraion, wait for 15s..."
    sleep 15
  done
}

replace_text_in_file() {
  local FIND_TEXT=$1
  local REPLACE_TEXT=$2
  local SRC_FILE=$3

  sed -i.bak "s@${FIND_TEXT}@${REPLACE_TEXT}@" ${SRC_FILE}
  rm $SRC_FILE.bak
}


################################ IAM Updates ################################

remove_aws_policies() {

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
  
  remove_inline_policy iam_alb_ingress_policy ${KF_DIR}/aws_config/iam_alb_ingress_policy.json
  remove_inline_policy iam_cloudwatch_policy ${KF_DIR}/aws_config/iam_cloudwatch_policy.json
}

remove_inline_policy() {
  declare -r POLICY_NAME="$1" POLICY_DOCUMENT="$2"

  for IAM_ROLE in ${AWS_NODEGROUP_ROLE_NAMES//,/ }
  do
    echo "Remove inline policy $POLICY_NAME for iam role $IAM_ROLE"
    if ! aws iam delete-role-policy --role-name $IAM_ROLE --policy-name $POLICY_NAME; then
        echo "Unable to remove iam inline policy $POLICY_NAME to role $IAM_ROLE" >&2
        #return 1
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

check_aws_setups() {
  check_aws_cli
  check_eksctl_cli
  check_jq
  check_aws_iam_authenticator
  check_aws_credential
}


# Call Functions
check_aws_setups
remove_aws_policies
uninstall_fluentd_cloudwatch
kubeflow_config_update

#Cleanup
rm -Rf ${BASE_DIR}/tmp.kfctl-${KFCTL_VERSION} 
rm -rf ${KF_DIR}

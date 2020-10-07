#!/bin/bash
#Manage EKS CLuster and Node
# Help
#
#. Mandatory Options for script -r for AWS REGION -c for Cluster Name -f For CLuster Config file -v for kubernetes Version -o output path to use for kubeconfig
#. ./eks-manage.sh -c <cluster-name> -r <region> -f <config-file> -v 1.15 -o <output-file>
#
while getopts r:c:f:v:o: option
do
case "${option}"
in
r) REGION=${OPTARG};;
c) CLUSTER=${OPTARG};;
f) CONFIG_FILE=${OPTARG};;
v) VERSION=${OPTARG};;
o) KUBECONFIG_FILE=${OPTARG};;
*) 
esac
done

# Get Current EKS Version
echo "Getting current EKS version"
eks_current_version=($(eksctl get cluster --region "$REGION" --name "$CLUSTER" | grep ACTIVE | awk '{print $2}'))

echo "EKS Version: $eks_current_version"

if [ $eks_current_version ]
then
	# Re-generate Kubeconfig file
	aws eks --region "$REGION" update-kubeconfig --name "$CLUSTER"
    cp /root/.kube/config build/kubeconfig
	
	if (( $(echo "$eks_current_version < $VERSION" | bc -l) ));
	then

		echo "Updating Cluster"

		eksctl update cluster \
		--config-file "$CONFIG_FILE" \
		--approve 
	
		#EKS Update utils
	    eksctl utils update-kube-proxy \
	    --cluster "$CLUSTER" \
	    --approve --region "$REGION"
	
		eksctl utils update-aws-node \
		--cluster "$CLUSTER" \
		--approve --region "$REGION"
	
		eksctl utils update-coredns \
		--cluster "$CLUSTER" \
		--approve --region "$REGION"
	fi
	
	AWS_NODEGROUP_ROLE_NAMES=$(aws iam list-roles --region $REGION \
      | jq -r ".Roles[] \
      | select(.RoleName \
      | startswith(\"eksctl-${CLUSTER}\") and contains(\"NodeInstanceRole\")) \
      .RoleName")
    AWS_NODEGROUP_ROLE_NAMES=$(echo ${AWS_NODEGROUP_ROLE_NAMES} | sed -e 's/ /,/g')
	
	# Create new Nodegroups
	eksctl create nodegroup --config-file "$CONFIG_FILE"
	
	# Delete Old Nodegroups
	PDBToUpdate="cluster-local-gateway istio-egressgateway istio-galley istio-ingressgateway istio-pilot istio-policy istio-telemetry"

	echo 'Deletting and saving istio pod disruption budgets for upgrade.'
	for PDB in ${PDBToUpdate}
	do
		echo "Deleting ${PDB} PDB"
		kubectl delete pdb $PDB -n istio-system
	done

	if [[ "$AWS_NODEGROUP_ROLE_NAMES" ]]; then
		for IAM_ROLE in ${AWS_NODEGROUP_ROLE_NAMES//,/ }
		do
			echo "Remove inline policy iam_cloudwatch_policy for iam role $IAM_ROLE"
			if ! aws iam delete-role-policy --role-name $IAM_ROLE --policy-name iam_cloudwatch_policy; then
				echo "Unable to remove iam inline policy iam_cloudwatch_policy to role $IAM_ROLE" >&2
				#return 1
			fi

			echo "Remove inline policy iam_alb_ingress_policy for iam role $IAM_ROLE"
			if ! aws iam delete-role-policy --role-name $IAM_ROLE --policy-name iam_alb_ingress_policy; then
				echo "Unable to remove iam inline policy iam_alb_ingress_policy to role $IAM_ROLE" >&2
				#return 1
			fi
		done
    fi  

	eksctl delete nodegroup --config-file "$CONFIG_FILE" --only-missing --approve

else

	echo "Creating New Cluster"
	eksctl create cluster --config-file "$CONFIG_FILE"

fi

echo "Configure Cluster Autoscailer" 
curl --silent -o cluster-autoscaler-autodiscover.yaml --location wget https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml

sed -e "s/<YOUR CLUSTER NAME>/$CLUSTER/" -i cluster-autoscaler-autodiscover.yaml

kubectl apply -f cluster-autoscaler-autodiscover.yaml

export CONFIG_YAML=$CODEBUILD_SRC_DIR\/config.yaml
export ROLE_ARN=$(yq r $CONFIG_YAML 'EKS.DebugRoleArn')

if [ $ROLE_ARN ]; then
	eksctl create iamidentitymapping --cluster "$CLUSTER" --arn $ROLE_ARN --group system:masters --username debugAdmin
fi
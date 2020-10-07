# KubeFlow

## Files: 

1. kubeflow-params.sh - Contains all the params which will be utilized for kubeflow installation. In case of using codepipeline we can forward param value as part of the pipeline step and ignore this file. 
2. kubeflow-install.sh - Installation script for installing kfctl, kubeflow, fluentd, cloudwatch, ALB
3. fluentd-cloudwatch.yaml-master - Config file to install cloudwatch and fluentd as daemon set and logs are pushed to cloud watch. Container insights are also configured as part of the install to get better graphical respresentation of system. 
4. buildspec.yaml - Codebuild buildspec for pipeline install
5. kubeflow-uninstall.sh Uninstallation script for kubeflow. 

## Install Steps:

1. Update config.yaml at root of the repo.
2. Run below command:
    ./kubeflow-install.sh -c <cluster_name> -r <region>

## Uninstall Steps:

1. Update config.yaml at root of the repo.
2. Run below command:
    ./kubeflow-uninstall.sh -c <cluster_name> -r <region>

## Assumptions:
    Install script assumes that kubectl,eksctl,aws cli,check_aws_iam_authenticator,jq packages are preinstalled on the system where the script is executed from.
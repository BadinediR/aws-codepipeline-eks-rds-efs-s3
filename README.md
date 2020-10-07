# Kubeflow on EKS

## Architecture Design

The purpose of this project is to build a pipeline that can deploy EKS, all of its dependencies,
and then to install and configure Kubeflow on top of the resulting cluster. The deployment is broken
into 3 distinct phases, that can be modularized depending on the cluster requirements. For example, in
the first step we create the network infrastructure, however this step can be skipped if you are
connecting to an existing VPC. All of this can be configured in a central configuration file found in the
root of the repository. This project allows you to

use a single shell script that launches a CodePipeline using CloudFormation. The initial deployment
only sets up the deployment pipeline. Then the individual deployment of Kubeflow is pulled from code
commit which allows for separate versioning of individual cluster changes. This also allows for cluster
upgrades to be handled with a single git commit.

<div align="center">
    <img src="/doc/sample_infra_architecture.png" width="400px"</img> 
</div>

## CodePipeline Flow
	
<div align="center">
    <img src="/doc/sample_flow_diagram.png" width="400px"</img> 
</div>

### Infra Assumptions and manual configuration:

 1. Shared VPC is already setup. If not update config.yaml at root to create a new `VPC/Subnet` setup. 
 2. Cognito Setup is already completed. Steps to configure base Cognito is at `doc/CognitoSetup.md`.
 3. Hosted Zone for Route53 Setup is completed. 
 4. If using existing VPC, ensure private subnet has tag as below.

    Public subnet(if used)
    Key                      Value
    kubernetes.io/role/elb  1 
    
    Private Subnet
    Key                              Value
    kubernetes.io/role/internal-elb 1

## Install Instructions

1. Update `config.yaml` at root of the repo with all the params which needs to be changed.
2. Update `eks/sample-eksctl-cluster.yaml` for cluster details.
3. Make sure the code resides in codecommit repo in the account where you are deploying and `config.yaml` is pointing to it. 
3. Run `./install-kubeflow.sh` deploy

## Folders & Files

1. `/EFS`: Contains Deployment CFN for EFS.
2. `/eks`: Contains configurations for deployment of the EKS cluster.
3. `/infrastructure`: Contains configurations for deployment the VPC and all infrastructure elements that will be used by EKS.
4. `/kubeflow`: Contains scripts and Yaml files for kubeflow install along with customizations to kubeflow.
5. `/pipeline`: Contains the pipeline to build out the EKS cluster and Infrastructure.
6. `/pipeline/scripts`: Scripts to use the CloudFormation script that sets up the pipeline.
7. `/RDS`: Contains the pipeline to build out RDS cluster and Infrastructure.
8. `/S3`: Contains configurations for deployment of S3 bucket.
9. `config.yaml`: Centralized location for all custom parameters to be used by different pieces of pipeline. 
10. `install-kubeflow.sh` : Main script to start installation. 
11. `SECURITY.md`: Documentation for all access needed by the cluster 

## Install Options:

**Deploy complete pipeline:**
```Bash
Deploy complete pipeline: ./install-kubeflow.sh deploy
```

**Delete pipeline:**
```Bash
./install-kubeflow.sh delete
```

**Reinstall pipeline:**
```Bash
./install-kubeflow.sh redeploy
```

## Future Updates:

1. Currently S3 support is not fully baked into kubeflow install. Current setup as part of the project only takes care of S3 bucket creation. Once upstream Kubeflow supports S3, it can be included as part of the project. 

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.
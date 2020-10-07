# Sample Kubeflow Deployment Security

## Downloaded Packages

### Executables

`eksctl`: https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz

`awscli`: https://pypi.org/project/awscli/

`kubectl`: https://amazon-eks.s3-us-west-2.amazonaws.com/1.14.6/2019-08-22/bin/linux/amd64/kubectl

`aws-iam-authenticator`: https://amazon-eks.s3-us-west-2.amazonaws.com/1.10.3/2018-07-26/bin/linux/amd64/aws-iam-authenticator

`yq`: https://github.com/mikefarah/yq/releases/tag/3.3.0

`jq`: https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64

Kubeflow Manifest: https://raw.githubusercontent.com/kubeflow/manifests/v1.0-branch/kfdef/kfctl_aws.v1.0.2.yaml

`kfctl`: https://github.com/kubeflow/kfctl/releases/download/v$KFCTL_VERSION/${KFCTL_TAR_FILE} 

### Docker Registires

`ECR`: The internal ECR Repository setup for the EKS cluster.

`gcr.io`: Google Cloud's docker registry

`docker.io`: Centralized docker registry for downloading different docker images used by Kubeflow

`quay.io` : Redhat docker registry for downloading different docker images used by Kubeflow

### Docker Images

Note: If domain name is not set then defaults to docker.io

- quay.io/jetstack/cert-manager-controller:v0.11.0
- quay.io/jetstack/cert-manager-cainjector:v0.11.0
- quay.io/jetstack/cert-manager-webhook:v0.11.0
- amazon/cloudwatch-∏gent:1.231221.0
- amazon/cloudwatch-agent:1.231221.0
- busybox
- fluent/fluentd-kubernetes-daemonset:v1.7.3-debian-cloudwatch-1.0
- busybox:latest
- docker.io/istio/proxyv2:1.1.6
- istio/proxyv2:1.1.6
- grafana/grafana:6.0.2
- docker.io/istio/citadel:1.1.6
- istio/citadel:1.1.6
- docker.io/istio/kubectl:1.1.6
- istio/kubectl:1.1.6
- docker.io/istio/galley:1.1.6
- istio/galley:1.1.6
- docker.io/istio/pilot:1.1.6
- istio/pilot:1.1.6
- docker.io/istio/mixer:1.1.6
- istio/mixer:1.1.6
- docker.io/istio/sidecar_injector:1.1.6
- istio/sidecar_injector:1.1.6
- docker.io/jaegertracing/all-in-one:1.9
- jaegertracing/all-in-one:1.9
- docker.io/kiali/kiali:v0.16
- kiali/kiali:v0.16
- docker.io/prom/prometheus:v2.3.1
- prom/prometheus:v2.3.1
- docker.io/istio/proxy_init:1.1.6
- gcr.io/knative-releases/knative.dev/serving/cmd/activator@sha256:8e606671215cc029683e8cd633ec5de9eabeaa6e9a4392ff289883304be1f418
- istio/proxy_init:1.1.6
- gcr.io/knative-releases/knative.dev/serving/cmd/autoscaler@sha256:ef1f01b5fb3886d4c488a219687aac72d28e72f808691132f658259e4e02bb27
- gcr.io/knative-releases/knative.dev/serving/cmd/autoscaler-hpa@sha256:5e0fadf574e66fb1c893806b5c5e5f19139cc476ebf1dff9860789fe4ac5f545
- gcr.io/knative-releases/knative.dev/serving/cmd/controller@sha256:5ca13e5b3ce5e2819c4567b75c0984650a57272ece44bc1dabf930f9fe1e19a1
- gcr.io/knative-releases/knative.dev/serving/cmd/networking/istio@sha256:727a623ccb17676fae8058cb1691207a9658a8d71bc7603d701e23b1a6037e6c
- gcr.io/knative-releases/knative.dev/serving/cmd/webhook@sha256:1ef3328282f31704b5802c1136bd117e8598fd9f437df8209ca87366c5ce9fcb
- 602401143452.dkr.ecr.us-east-1.amazonaws.com/amazon-k8s-cni:v1.5.7
- 602401143452.dkr.ecr.us-east-1.amazonaws.com/eks/coredns:v1.6.6
- 602401143452.dkr.ecr.us-east-1.amazonaws.com/eks/kube-proxy:v1.15.11
- gcr.io/kubeflow-images-public/ingress-setup:latest
- gcr.io/kubeflow-images-public/admission-webhook:v1.0.0-gaf96e4e3
- docker.io/amazon/aws-alb-ingress-controller:v1.1.5
- amazon/aws-alb-ingress-controller:v1.1.5
- gcr.io/kubeflow-images-public/kubernetes-sigs/application:1.0-beta
- argoproj/argoui:v2.3.0
- gcr.io/kubeflow-images-public/centraldashboard:v1.0.0-g3ec0de71
- gcr.io/kubeflow-images-public/jupyter-web-app:v1.0.0-g2bd63238
- gcr.io/kubeflow-images-public/katib/v1alpha3/katib-controller:v0.8.0
- gcr.io/kubeflow-images-public/katib/v1alpha3/katib-db-manager:v0.8.0
- mysql:8
- gcr.io/kubeflow-images-public/katib/v1alpha3/katib-ui:v0.8.0
- gcr.io/kubebuilder/kube-rbac-proxy:v0.4.0
- gcr.io/kfserving/kfserving-controller:0.2.2
- metacontroller/metacontroller:v0.3.0
- mysql:8.0.3
- gcr.io/kubeflow-images-public/metadata:v0.1.11
- gcr.io/ml-pipeline/envoy:metadata-grpc
- gcr.io/tfx-oss-public/ml_metadata_store_server:v0.21.1
- gcr.io/kubeflow-images-public/metadata-frontend:v0.1.8
- minio/minio:RELEASE.2018-02-09T22-40-05Z
- gcr.io/ml-pipeline/api-server:0.2.5
- gcr.io/ml-pipeline/visualization-server:0.2.5
- gcr.io/ml-pipeline/persistenceagent:0.2.5
- gcr.io/ml-pipeline/scheduledworkflow:0.2.5
- gcr.io/ml-pipeline/frontend:0.2.5
- gcr.io/ml-pipeline/viewer-crd-controller:0.2.5
- mpioperator/mpi-operator:0.1.0
- mysql:5.6
- gcr.io/kubeflow-images-public/notebook-controller:v1.0.0-gcd65ce25
- nvidia/k8s-device-plugin:1.0.0-beta4
- gcr.io/kubeflow-images-public/profile-controller:v1.0.0-ge50a8531
- gcr.io/kubeflow-images-public/kfam:v1.0.0-gf3e09203
- gcr.io/kubeflow-images-public/pytorch-operator:v1.0.0-g047cf0f
- seldonio/seldon-core-operator:1.0.1
- docker.io/seldonio/seldon-core-operator:1.0.1
- gcr.io/spark-operator/spark-operator:v1beta2-1.0.0-2.4.4
- gcr.io/google_containers/spartakus-amd64:v1.1.0
- tensorflow/tensorflow:1.8.0
- gcr.io/kubeflow-images-public/tf_operator:v1.0.0-g92389064
- argoproj/workflow-controller:v2.3.0
- argoproj/workflow-controller:v2.3.0a483e7ad3172:kubeflow

## Outbount Access

### Network

**Ports:** `80`, and `443`

**Egress:** Nat Gateway

## Inbound Access

All resources not defined below will not be publicly accesible. 

### NAT Gateway

No inbound access will be allowed, only traffic that origonated within the VPC.

### Jump Host

Will allows access to the VPC through port forwarding, and ssh access.

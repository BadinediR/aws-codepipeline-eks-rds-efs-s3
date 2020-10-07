Assumptions:
1. Domain is hosted in the route 53 which is controlled by user configuring
2. Using Amazon Certificate 

Route 53 Config:
In order to make Coginito to use custom domain name, A record is required to resolve domain.com as root domain, which can be a Route53 Alias to the ALB as well. We can use abitrary ip here now, once we have ALB created, we will update the value.
Create A record for domain with value 127.0.0.1 (This is temporary, will be changing it to ALB once it is created)

Certificate Manager:
Create two certificates in Certificate Manager for *.domain.com, one in N.Virginia and one in the region where EKS cluster is running. That is because Cognito requires a certificate in N.Virginia in order to have a custom domain for a user pool. The second is required by the ingress-gateway in case the platform does not run in N.Virginia. For the validation of both certificates, you will be asked to create one record in the hosted zone in previous step.

Cognito Setup:
1. Create a user pool in Cognito. Type a pool name and choose Review defaults and Create pool.
2. Create some users in Users and groups, these are the users who will login to the central dashboard. Config can be changes if using another provider.
3. Add an App client with any name and the default options.
	In the App client settings select Authorization code grant flow and email, openid, aws.cognito.signin.user.admin and profile scopes.
	Use https://kubeflow.domain.com/oauth2/idpresponse in the Callback URL(s).
4. In the Domain name choose Use your domain, type auth.domain.com and select the *.domain.com AWS managed certificate you’ve created in N.Virginia. Creating domain takes up to 15 mins.
5. When domain is created, it will return the Alias target cloudfront address for which you need to create a CNAME Record auth.domain.com in the hosted zone.
6. Take note of the following values:

    The ARN of the certificate from the Certificate Manager of N.Virginia.
    The Pool ARN of the user pool found in Cognito general settings.
    The App client id, found in Cognito App clients.  
    The auth.domain.com as the domain.

Kubeflow Setup:
	Now run kube flow codepipeline to setup Kubeflow. Once setup is completed, it will generated internal ALB.

Route 53 Update:
At this point you will also have an ALB, it takes around 3 minutes to be ready. When ready, copy the DNS name of that load balancer and create 2 CNAME entries to it in Route53:

    *.domain.com
    *.default.domain.com

Also remember to update A record for domain.com using ALB DNS name.

The central dashboard should now be available at https://kubeflow.domain.com the first time will redirect to Cognito for login.
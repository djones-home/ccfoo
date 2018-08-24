% DelegateManagementofMFA_policydocument_060115.json.erb

# AWS MFA Policy Document

This ERB template is used for creating a custom managed IAM policy document
for Multi-Factor-Authentication (MFA). It is pretty much taken as-is from the AWS [How-To-MFA] document, 
with a few lines of embedded ruby to make it work from either the gov or commercial partitions.
Provided you run it an environment that can list your IAM user details with the aws-cli, 
it will use your IAM-user ARN to determine partition and account.

 - Allows individual IAM users to setup and manage MFA 
 - Forces use of MFA

Usage: 

````
 templateJsonDate $CIDATA path/to/this/template-file > /tmp/policy.json
 aws iam create-policy --policy-name $policyName --policy-document file://tmp/policy.json
````

Also see: 

 - [How-To-MFA](https://aws.amazon.com/blogs/security/how-to-delegate-management-of-multi-factor-authentication-to-aws-iam-users/)
 - templateJson function in [ciStack.sh](https://svn.nps.edu/repos/metocgis/infrastructure/trunk/tools/ciStack.sh)

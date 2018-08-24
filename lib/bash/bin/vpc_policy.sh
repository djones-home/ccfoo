#!/bin/bash
#md+ bashDoc transforms this to markdown doc.
# [AWS VPC Lockdown policy]: https://aws.amazon.com/premiumsupport/knowledge-center/iam-policy-restrict-vpc/

# This file contains shell functions for setup of IAM polcy to secure entities with their associated VPCs of a CI project.
# Based on the CIDATA,  the create_vpc_policy function will make the needed policy, roles, and profiles
# for a new VPC. This must be ran after the VPC-ID is known, as these polices use this ID in thier conditions.
# Refer to [AWS VPC Lockdown policy] for technical details and examples implimentations.
# 
# Document version:
#
#       $Id: vpc_policy.sh 69874 2018-04-07 21:29:49Z dljones@nps.edu $
#       $HeadURL: https://svn.nps.edu/repos/metocgis/infrastructure/trunk/tools/vpc_policy.sh $
  
# # Functions

###
# Create a managed policy for each VPC, which can be given to entities that manage the VPC.
# This makes an instance profile: CI-vpc-NAME for the management instances, and 
# CI-vpc-NAME-ro for non-admin instances (most instances having "*-ro" IAM-role).
# In addition to attaching the manged policy, create inline policy (as needed for this and that).
#
#  - inline policy for s3 read access to a few buckets
#  - inline policy for s3 write access to a few buckets if on Bastion.
#  - inline policy to allow createTags for the launch of an instance.
#  - inline eip_policy (not limited by the vpc) to allow association of an EIP to an instance.
#  - inline policy to allow describe and read of ssm:parameter/NAME/* values
#
# - Environment: 
#     * Parameter __CIDATA__ - must hold path to project-settings JSON file.
#     * jq -  Command-line JSON processor (v1.3 or greater)
#     * aws-cli - AWS Command Line Interface (v1.10.1, Python, botocore).
#
#
#
create_vpc_policy() {
     local q role json vpcId policyName desc arn policy cmd n
     role=$(vpc_ec2_roles) || return 1
     policy=$WORKSPACE/$role.policy.json
     vpcId=$(getVpcId) || return 1
     policyName=CI-$vpcId
     q='.Policies[] | select(.PolicyName==$n)'
     json=$(aws iam list-policies | jq -r --arg n "${policyName}" "$q" ) 
     # Name the managed policy (lockdown) to that of the vpc-id.
     [ X${policyName} != X$(echo "$json" | jq -r .PolicyName) ] && {
         template_vpc_lockdown_policy > $policy
         desc="Managed policy to attach to the IAM entities that control $vpcId, allowing: stop, start, launch, terminate, ..." 
         jq . $policy >/dev/null || return 1
         echo "${FUNCNAME[0]}: aws iam create-policy  --policy-name $policyName  --policy-document file://$policy --description $desc" >&2
         json=$(aws iam create-policy  --policy-name $policyName  --policy-document file://$policy --description "$desc") || return 1
         json=$(aws iam list-policies | jq -r --arg n "${policyName}" "$q" ) 
     }
     arn=$(echo "$json" | jq -r .Arn); [ OK != "${arn/arn:aws*policy*/OK}" ] && return 1
     q='.AttachedPolicies[] | select(.PolicyArn==$arn)'
     # Provide the managed policy to users  via a group named CI-vpc-NAME
     json=$(aws iam list-groups | jq -r --arg n $role '.Groups[]|select(.GroupName == $n)')
     [ -z "$json" ] && { json=$(aws iam create-group --group-name $role) && json=$(echo $json | jq .Group); }
     json=$(aws iam list-attached-group-policies --group-name $role | jq --arg arn $arn "$q")
     [ -z "$json" ] && { 
         echo "aws iam attach-group-policy --group-name $role --policy-arn $arn" >&2
         aws iam attach-group-policy --group-name $role --policy-arn $arn >&2 || return 1
     }
     # Provide the managed policy (lockdown) to the contoller (Bastion)  instance-profile via role-name of CI-vpc-NAME
     json=$(aws iam list-attached-role-policies --role-name $role | jq --arg arn $arn "$q")
     [ -z "$json" ] && { 
         echo "aws iam attach-role-policy --role-name $role --policy-arn $arn" >&2
         aws iam attach-role-policy --role-name $role --policy-arn $arn >&2 || return 1
     }
     # Make the instance profile-names with the same name as the attached role-name/a.
     for n in ${role}-$(lockdown_role_suffix) ${role}; do
         q='.InstanceProfiles[] | select(.InstanceProfileName==$n)'
         json=$(aws iam list-instance-profiles | jq --arg n $n "$q")
         [ -z "$json" ] && { 
             cmd="aws iam create-instance-profile --instance-profile-name $n"
             echo "$cmd"; $cmd  || return 1
             aws iam add-role-to-instance-profile --instance-profile-name $n  --role-name $n || return 1
             aws iam put-role-policy --policy-name read_s3access --role-name $n --policy-document "$(read_bucket_policy)"
         } || {
            q='.Roles[] | select(.RoleName==$n)'; json=$(echo "$json" | jq --arg n $n "$q")
            [ -z "$json" ] && { 
             aws iam add-role-to-instance-profile --instance-profile-name $n  --role-name $n || return 1
            }
            ! aws iam get-role-policy --role-name $n --policy-name read_s3access > /dev/null 2>&1 && 
               aws iam put-role-policy --policy-name read_s3access --role-name $n --policy-document "$(read_bucket_policy)"
            ! aws iam get-role-policy --role-name $n --policy-name read_parameter > /dev/null 2>&1 && 
               aws iam put-role-policy --policy-name read_parameter --role-name $n --policy-document "$(read_parameter_policy)"
         }
     done
     # add inline polices to role and group of the same name (CI-vpc-NAME)
     for n in role group; do
         ! aws iam get-${n}-policy --${n}-name $role --policy-name write_s3access >/dev/null 2>&1 &&
            aws iam put-${n}-policy --policy-name write_s3access --${n}-name $role --policy-document "$(write_bucket_policy)"
         ! aws iam get-${n}-policy --${n}-name $role --policy-name create_tags > /dev/null 2>&1 && 
            aws iam put-${n}-policy --policy-name create_tags --${n}-name $role --policy-document "$(create_tags_policy)"
         ! aws iam get-${n}-policy --${n}-name $role --policy-name eip_policy > /dev/null 2>&1 && 
            aws iam put-${n}-policy --policy-name eip_policy --${n}-name $role --policy-document "$(eip_policy)"
         ! aws iam get-${n}-policy --${n}-name $role --policy-name read_s3access > /dev/null 2>&1 && 
            aws iam put-${n}-policy --policy-name read_s3access --${n}-name $role --policy-document "$(read_bucket_policy)"
         ! aws iam get-${n}-policy --${n}-name $role --policy-name read_parameter > /dev/null 2>&1 && 
            aws iam put-${n}-policy --policy-name read_parameter --${n}-name $role --policy-document "$(read_parameter_policy)"
     done
     echo $policyName
     return 0
}
###
# vpc_ec2_roles creates instance IAM roles, two, for use in instance-profiles.
# These IAM role, for each VPC in an aws-account,  are used for VPC-lockdown and s3access on the instances.
vpc_ec2_roles() {
   local name json q n ; local -i rv=0
   name=CI-vpc-$(jq -r .VpcName $CIDATA) || return 1
   q='.Roles[] | select(.RoleName==$n).RoleName'
   json=$(aws iam list-roles)  || return 1
   for n in ${name}-$(lockdown_role_suffix) ${name}; do
      [ X != X$(echo "$json" | jq --arg n "$n"  "$q") ] && continue
      echo "${FUNCNAME[0]}: Creating missing role-name $n" >&2
      echo aws iam create-role --role-name $n --assume-role-policy-document "$(ec2_role_type_policy)" >&2 
      aws iam create-role --role-name $n --assume-role-policy-document "$(ec2_role_type_policy)" >&2 || let rv++
   done
   echo $name
   return $rv
}

###
# Return a JSON string for use to in create-role w/assume-role-policy-documnet
ec2_role_type_policy() {
   echo '{ "Version": "2012-10-17", "Statement": { "Effect": "Allow", "Principal": {"Service": "ec2.amazonaws.com"}, "Action": "sts:AssumeRole" } }'
}
###
# This implimentation uses two IAM-roles, one for the controller, one for the controlee.
# For example: CI-vpc-CJMTK, and CI-vpc-CJMTK-ro. By local convension, 
# the names diff by the added suffix, "-ro" in this case.

#  This funciton Simply returns that added suffix,  "-ro" or whatever, from one source.
lockdown_role_suffix() { echo 'ro';}

###
# Create a policy document, using a template derrived from [AWS VPC Lockdown policy].
#
template_vpc_lockdown_policy() {
     local acct role region vpcId suffix='-ro' projectName
     local myPartition=$(aws iam get-user | jq -r .User.Arn | cut -d: -f2)
     role=$(vpc_ec2_roles) || return 1
     vpcId=$(getVpcId) || return 1
     projectName=$(jq -r .VpcName $CIDATA) || return 1
     acct=$(aws iam  get-user | jq -r .User.Arn | cut -d: -f 5) || return 1
     region=$(aws configure get region) || return 1
     sed -e "s/ACCOUNTNUMBER/$acct/g" \
         -e "s/ROLENAME/${role}-$(lockdown_role_suffix)/g" \
         -e "s/REGION/$region/g" \
         -e "s/VPC-ID/$vpcId/g" \
         -e "s/arn:aws:/arn:${myPartition}:/g" \
         -e "s/PROJECTNAME/${projectName}/g" \
          $WORKSPACE/ciData/templates/lockdownPolicy.json
}


###
# Helper function to generate the policy documents for s3 read access.
#
read_bucket_policy() {
   local pdoc readPolicy writePolicy arnList n v delim="" 
   local myPartition=$(aws iam get-user | jq -r .User.Arn | cut -d: -f2)
   delim=""; arnList='[ '; for n in s3Store s3ProjectStore s3SysStore; do 
    # additional for loop allows a project to quote a space-deliniated list in one of the s3*Store params.
    for v in $(jq -r .$n $CIDATA); do  
     [ OK != "${v/s3:\/\/*/OK}" ] && { [ -n "$v" ] && echo "${FUNCNAME[0]}: ERROR No bucket in CIDATA for $n" >&2 ; continue; }
     v=${v##s3://}; 
     arnList+="$delim "'"arn:'${myPartition}':s3:::'$v'"'; 
     delim=","
     arnList+="$delim "'"arn:'${myPartition}':s3:::'$v'/*"'
    done
   done; arnList+=' ]'
   readPolicy='{"Version":"2012-10-17","Statement":['
   readPolicy+='{ "Effect": "Allow", "Action": [ "s3:GetBucketLocation", "s3:ListAllMyBuckets" ], "Resource": "arn:'${myPartition}':s3:::*" },'
   readPolicy+='{"Effect":"Allow","Action":["s3:Get*","s3:List*"],"Resource": . }]}'
   echo "$arnList" | jq "$readPolicy"
}
###
# Helper function to generate the policy documents for s3 write access.
#
write_bucket_policy() {
   local pdoc readPolicy writePolicy arnList n v delim="" 
   local myPartition=$(aws iam get-user | jq -r .User.Arn | cut -d: -f2)
   delim=""; arnList='[ '; 
   for v in $(jq -r .s3Store $CIDATA); do
    [ OK == "${v/s3:\/\/*/OK}" ] && {
        v=${v##s3://}; 
        arnList+="$delim "'"arn:'${myPartition}':s3:::'$v/$(jq -r .Project $CIDATA)'/*"'; delim=","
        [ "$(jq -r .Project $CIDATA)" != "$(jq -r .VpcName $CIDATA)" ] && 
          arnList+="$delim "'"arn:'${myPartition}':s3:::'$v/$(jq -r .VpcName $CIDATA)'/*"'; delim=","
    }
   done
   for n in s3ProjectStore s3SysStore; do for v in $(jq -r .$n $CIDATA); do
       [ OK != "${v/s3:\/\/*/OK}" ] &&  continue
       v=${v##s3://}; 
       arnList+="$delim "'"arn:'${myPartition}':s3:::'$v'/*"'
   done; done; arnList+=' ]'
   writePolicy='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:*"],"Resource": . }]}'
   echo "$arnList" | jq "$writePolicy"
}

###
# Helper function to generate the policy documents to allow ec2:CreateTags action
#
create_tags_policy() { echo '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["ec2:CreateTags"],"Resource": "*" }]}'; }
### 
## I could not find a condition to limit the EIP association - beware.
# Helper function to generate the policy documents to allow EIP association
# 
eip_policy() { echo '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["ec2:AssociateAddress"],"Resource": "*" }]}'; }

###
# Create IAM user for Jenkins agent, add it to the group of name: CI-vpc-{Project name}
# 
create_vpc_agent_user() {
     local json groupName cmd n userName
     userName=CI-$(jq -r .Project $CIDATA)
     groupName=CI-vpc-$(jq -r .Project $CIDATA); 
     json=$(aws iam list-users | jq  --arg u $userName '.Users[] | select(.UserName == $u)')
     [ -z "$json" ] && {
         for cmd in "aws iam create-user --user-name $userName" \
              "aws iam add-user-to-group --user-name $userName --group-name $groupName" 
         do echo $cmd; $cmd > /dev/null  || return 1; done
     }
     json=$(aws iam create-access-key --user-name $userName) || return 1
     setup_agent_profile ${JOB_NAME:-$userName} "$json"
}

###
# Make the aws configuration profile entries for a build server agent to use for this CI-project or JOB_NAME
# Note: These keys are not needed for build servers in AWS which can use an instance-profile.
setup_agent_profile() {
   local profile=$1 json="$2"
          aws configure --profile $profile set region ${AWS_REGION:-us-gov-west-1}
          aws configure --profile $profile set aws_access_key_id $(echo $json | jq -r '.AccessKey.AccessKeyId')
          aws configure --profile $profile set aws_secret_access_key $(echo $json | jq -r '.AccessKey.SecretAccessKey')
          aws configure --profile $profile set output json
          aws configure set profile.$profile.description "Jenkins agent profile"
}
###
# Add AWS-managed policies appropriate for the CI VPC instance roles, with names like CI-vpc-NAME-ro.
# These effective allow Linux instance to broker AWS credentials for a process.
# 
# - Allow function like showInst (ciStack show) need this to query EC2 service.
# - Allow function to reading system artifacts from S3.
# 
Add_policy_to_CI-vpc-ro() {
  local pname json arn policies cmd; 
  json=$(aws iam list-policies  --scope AWS) || return 1
  for pname in AmazonEC2ReadOnlyAccess
  do
     arn=$(echo $json | jq -r --arg n $pname '.Policies[]| select(.PolicyName == $n).Arn')
     for role in $(aws iam list-roles | jq -r '.Roles[] | .RoleName'| grep -e 'CI-vpc.*-ro'); do
       #[ -n "$(aws iam list-attached-role-policies --role-name $role | jq --arg n $pname '.AttachedPolicies[] | select(.PolicyName == $n)')" ] && continue;
       policies="$(aws iam list-attached-role-policies --role-name $role)"
       echo "${FUNCNAME[0]} Role: $role, Current attached policies: $(echo $policies | jq -r '.AttachedPolicies[].PolicyName')"
       [ -n "$(echo $policies | jq --arg n $pname 'select(.AttachedPolicies[].PolicyName == $n)')" ] && continue
       cmd="aws iam attach-role-policy --role-name $role --policy-arn $arn"
       echo $cmd >&2
       # $cmd || return 1
     done
  done
}

###
# Generate the SSM Read Parameter policy documanet. Templating:
# 
# - Partition (i.e. aws or aws-us-gov)
# - Account ID
# - Region
# - Project Name
read_parameter_policy() {
    local json acct partition region project
# - Use IAM get-user to find values for account and partition
    json=$(aws iam get-user)
    acct=$(echo $json | jq -r .User.Arn | cut -d: -f5)
    partition=$(echo $json | jq -r .User.Arn | cut -d: -f2)
# - Use aws config for region value
    region=$(aws configure get region)
# - Use $CIDATA for Project value
    [ ! -r "$CIDATA" ] && { echo 'ERROR Cannot read $CIDATA'; return 1; }
    project=$(jq -r .Project $CIDATA)
# - Return templated JSON doc
    for n in  $project common ; do echo  \"arn:${partition}:ssm:${region}:${acct}:parameter/${n}/*\"  ; done |
     jq -s '{ "Version": "2012-10-17", "Statement": [
        { "Effect": "Allow", "Action": [ "ssm:DescribeParameters" ], "Resource": "*" },
        { "Effect": "Allow", "Action": [ "ssm:GetParam*" ], "Resource":  (.) } ] }' 
}

###
# Given the name of an project inline policy, 
# update  the policy in the two project instance roles, and project group.
#
update_vpc_inline_policy() {
   [ $# == 1 ] || { echo ERROR: Usage ${FUNCNAME[0]} policyName; return 1; }
   name=$(vpc_ec2_roles) || return 1
   suffix=$(lockdown_role_suffix)
   aws iam delete-group-policy --group-name $name --policy-name $1 &&
   aws iam delete-role-policy --role-name $name --policy-name $1 &&
   aws iam delete-role-policy --role-name $name-$suffix --policy-name $1 && 
   create_vpc_policy
}

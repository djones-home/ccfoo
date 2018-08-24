#!/bin/bash
#md+ bashDoc transforms this to markdown doc.

#
# Creates a CI instance in an AWS account.
## $HeadURL: https://svn.nps.edu/repos/metocgis/infrastructure/trunk/tools/ciBootStrap.sh $
## $Id: ciBootStrap.sh 68748 2018-03-06 13:07:53Z dljones@nps.edu $
###
# dependencies: aws-cli/1.10.38,  jq-1.3
#

! shopt -q extglob  && shopt -s extglob

# # User Functions

# This library is used in conjunction with __ciStack__ to manage the provisioning of CI projectes.
#
# Document version:
#
#       $Id: ciBootStrap.sh 68748 2018-03-06 13:07:53Z dljones@nps.edu $
#       $HeadURL: https://svn.nps.edu/repos/metocgis/infrastructure/trunk/tools/ciBootStrap.sh $
#

###
# Function create_vpc, creates a multi-tier Virtual Private Cloud. 
#
# - Public and Private subnets, in two Availablility Zones.
# - Searchs for the next available CDIR 10.X.0.0/16, within account.
# - Calls helper functions that setup security groups, gateways, and routes.
# - Requires project settings in JSON file.
# - Environment: 
#     * Parameter __CIDATA__ - must hold path to project-settings JSON file.
#     * jq -  Command-line JSON processor (v1.3 or greater)
#     * aws-cli - AWS Command Line Interface (v1.10, Python, botocore).
#
create_vpc() {
    local az azList n subnetId CDIRS json vpcId
    n=$(jq -r .VpcName ${CIDATA:-/dev/null})
    local vpcName="${1:-${n:-CI_$(date +%s)}}"
    local -i a b=0 c=0 rv=0;
    local sgNames
    local json=$(aws ec2 describe-vpcs)
    ciEnv=${vpcName}
    # find the next available CIDR block
    CDIRS=$(echo $json | jq -r '.[] | map(.CidrBlock) | .[]')
    for a in 10; do 
        while [ $b -lt 250 ]; do
          [ -n "${CDIRS/*${a}.${b}.*.0*/}" ] && break 
          let b+=10
    done; done
    [ b == 250 ] && return 1
    ##
    # 1. Create and tag a new vpc after finding an unused CDIR block, of $a.$b.0.0/16
    #
    echo aws ec2 create-vpc --cidr-block $a.$b.0.0/16 --o json >&2
    json=$(aws ec2 create-vpc --cidr-block $a.$b.0.0/16 --o json) || return 1
    vpcId=$( echo "$json" | jq -r .[].VpcId ) 
    [ OK != ${vpcId/vpc-+([[:xdigit:]])/OK} ] && echo ${FUNCNAME[0]}: ERROR creating vpc invalid vpcId in returned json="$json" >&2 && return 1
    # aws ec2 create-tags --resources $1 --tags Key=ciEnv,Value=$ciEnv >&2
    echo aws ec2 create-tags --resources $vpcId --tags Key=Name,Value="${vpcName}" Key=ciEnv,Value=${ciEnv} >&2
    aws ec2 create-tags --resources $vpcId --tags Key=Name,Value="${vpcName}" Key=ciEnv,Value=${ciEnv} >&2
    add_tags $vpcId >&2
    aws ec2 modify-vpc-attribute --enable-dns-hostnames --vpc-id $vpcId
    msg="CIDATA json which should keeps/commits the VpcId  for the record", 
    [ -f "$CIDATA" ] && {
       # check with jq, but set with sed as 
       [ "$(jq -r .VpcId $CIDATA)" != "$vpcId" ] &&  { 
             echo "${FUNCNAME[0]}: update VpcId in  $msg";
             #sed "s/$(jq -r .VpcId $CIDATA)/$vpcId/" $CIDATA
             data=$(jq . $CIDATA) || return 1
             data+=$(jq -n --arg v $vpcId '{ VpcId : $v }')
             echo $data | jq -s '. | add' > $CIDATA
       }
       [ "$(jq -r .VpcId $CIDATA)" != "$vpcId" ] &&  { echo "${FUNCNAME[0]}: ERROR: Could Not update VpcId in  $msg"; return 1; }
       svn ci -m "$Issue ${FUNCNAME[0]}: update VpcId in CIDATA for $(jq -r .Name  $CIDATA)" $CIDATA 
    }
    ###
    # 2. Create subnets in multiple AZs, for Web (public), App (private), and DB (private).
    # 3. Setup Security Groups, InBound rules, Routes, ...
    #  - by convension, a default set of SG names were made, but it honors names in the .Secuirty.inBound object too.
    #   Make more Names, i.e. SG "db", "db1", "db2", as needed when rule limits are reached.
    azList=$(aws ec2 describe-availability-zones | jq -r -c '.[] |map(.ZoneName) |.[:2] | .[] ') || return 1
    unset netCIDR netAZ; declare -A netCIDR netAZ
    sgNames=$(cat $CIDATA | jq -r '.Security.SGinBound | to_entries | .[].key')
    for n in web app db compute; do 
       # only make subnets that can be associated with sgNames.
       echo "$sgNames" | grep -q -e "^$n\d*\$" || { 
               echo Warning: No Security.SGinBound.$n, in \$CIDATA. No $n Subnets, nor SG-$n will not be made.; continue; }
       for az in ${azList}; do 
            netCIDR[$n-${az##*-?}]=$a.$b.$c.0/24; let c+=10; 
            netAZ[$n-${az##*-?}]=$az;
        done
    done
    for n in ${!netCIDR[@]}; do  
        echo aws ec2 create-subnet --vpc-id  $vpcId --cidr-block ${netCIDR[$n]} --availability-zone ${netAZ[$n]}  >&2
        json=$(aws ec2 create-subnet --vpc-id  $vpcId --cidr-block ${netCIDR[$n]} --o json --availability-zone ${netAZ[$n]}) 
        subnetId=$(echo "$json" | jq -r ' .[].SubnetId')
        [ OK != ${subnetId/subnet-+([[:xdigit:]])/OK} ] && echo ERROR creating subnet invalid subnetId returned json="$json" >&2 && return 1
        echo aws ec2 create-tags --resources $subnetId --tags Key=Name,Value=$n Key=ciEnv,Value=${ciEnv} >&2
        aws ec2 create-tags --resources $subnetId --tags Key=Name,Value=$n Key=ciEnv,Value=${ciEnv} >&2
        ## only the web is public,  MapPublicOnLaunch if web, and associate with a custom route table
        [ -z "${n/*web*/}" ] && make_subnet_public $subnetId $vpcId || let rv++
    done
    #add_sg $vpcId bastion web app db nat || { echo ERROR ${FUNCNAME[0]}: Could not complete Security Group setup. >&2; return 1; }
    add_sg $vpcId $sgNames bastion nat || { echo ERROR ${FUNCNAME[0]}: Could not complete Security Group setup. >&2; return 1; }
    ###
    # Launch a NAT instance , route outgoing private subnets traffic to NAT instance
    #
   launch_NAT $vpcId || return 1
   json=$(aws ec2 describe-instances --f Name=tag:Name,Values=NAT Name=vpc-id,Values=$vpcId   --o json)
   natId="$(echo ${json} | jq -r '.[] | .[].Instances[].InstanceId')"
   [ OK != ${natId/i-+([[:xdigit:]])/OK} ] && echo ERROR launching NAT instgance >&2 && return 1
    # route outgoing internet traffic from the private networks (the main route-table) to NAT for internet 
   rtb=$(aws ec2 describe-route-tables --f Name=association.main,Values=true Name=vpc-id,Values=$vpcId \
        --q 'RouteTables[0].RouteTableId' --o text)
   [ OK != ${rtb/rtb-+([[:xdigit:]])/OK} ] && echo ${FUNCNAME[0]}: ERROR finding main rtb for $vpcId >&2 && return 1
    echo  aws ec2 create-route --route-table-id $rtb --destination-cidr-block 0.0.0.0/0 --instance-id $natId >&2
    json=$(aws ec2 create-route --route-table-id $rtb --destination-cidr-block 0.0.0.0/0 --instance-id $natId) 
    [ true != "$(echo $json | jq '.Return')" ] && { echo ${FUNCNAME[0]} ERROR json="$json"; return 1; }
    echo $vpcId
}

###
# Function to delete a vpc, and associated resources.
#
delete_vpc() {
  [ -z "$1" ] && echo "Usage: ${FUNCNAME[0]} Name|VpdId" >&2 && return 1
  local vpc="$1" subnet json igw sg n res vpcId
  local -i rv=0
  unset dJ; declare -A dJ
  #n=vpcs; dJ[$n]=$(aws ec2 describe-vpcs --f Name=tag:Name,Values=$vpc) || return 1
  n=vpcs; dJ[$n]=$(awsGetVpc $vpc) || return 1
  [ 1 != $(echo ${dJ[$n]} | jq '.Vpcs | length') ] && { echo "ERROR  options must select ONE vpc" >&2 ; return 1; }
  vpcId=$(echo ${dJ[$n]} | jq -r '.[] | .[0].VpcId')
  [ "null" == $vpcId ] && return 1
  # n=vpcs; dJ[$n]=$(aws ec2 describe-$n --vpc-ids $vpcId --o json) || return 1
  # Find and delete any instances, in vpc
  n=instances; json=$(aws ec2 describe-$n --filters  "Name=vpc-id,Values=$vpcId" --o json) || return 1
  n="$(echo ${json} | jq -r '.[] | .[].Instances[].InstanceId')"
  [ -n "$n" ] && {
     echo Cannot delete vpc with until: aws ec2 terminate-instances --instance-ids $n
     return 1
  }
  # Find and delete  SGs in VPC
  n=security-groups; dJ[$n]=$(aws ec2 describe-$n --f Name=vpc-id,Values=$vpcId --o json)
  #n=security-groups; dJ[$n]=$(aws ec2 describe-$n --f Name=group-name,Values=NAT Name=vpc-id,Values=$vpcId)
  for sg in  $(echo ${dJ[$n]} | jq -r '.[] | .[].GroupId'); do 
     revoke_vpc_sg_inBound_rules $vpcId $sg "${dJ[security-groups]}"
  done
  for sg in $(echo ${dJ[$n]} | jq -r '.[] | .[] | select(.GroupName!="default") |.GroupId'); do
     echo aws ec2 delete-security-group --group-id $sg >&2
     aws ec2 delete-security-group --group-id $sg 
  done
  # Find and delete any subnets in VPC
  n=subnets; dJ[$n]=$(aws ec2 describe-$n --filters  "Name=vpc-id,Values=$vpcId" --o json) || return 1
  echo "aws ec2 describe-$n --filters  Name=vpc-id,Values=$vpcId --o json" >&2
  for subnet in $(echo "${dJ[subnets]}" | jq -r '.[]| map(.SubnetId) | .[]'); do
      echo aws ec2 delete-subnet --subnet-id $subnet >&2
      aws ec2 delete-subnet --subnet-id $subnet || let rv++
  done
  # Find and delete any igw in VPC
  n=internet-gateways; dJ[$n]=$(aws ec2 describe-$n --f Name=attachment.vpc-id,Values=$vpcId)
  for igw in $(echo ${dJ[$n]} | jq -r '.[] | .[].InternetGatewayId')
  do 
     echo "aws ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $vpcId" >&2
     aws ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $vpcId >&2 || let rv++
     echo "aws ec2 delete-internet-gateway --internet-gateway-id $igw" >&2
     aws ec2 delete-internet-gateway --internet-gateway-id $igw >&2 || let rv++
  done
  # Delete route-tables, 
  # Delete Main route-table ,  Associations with Main:true. 
  #for n in $(aws ec2 describe-route-tables --f  Name=vpc-id,Values=$vpcId | jq -r '.[] | .[].RouteTableId '); do
  #   echo aws ec2 delete-route-table --route-table-id $n
  #   aws ec2 delete-route-table --route-table-id $n
  #done
  # This is only testing for associations length, may need to test for Main!=true.
  n=route-tables; dJ[$n]=$(aws ec2 describe-$n --f Name=vpc-id,Values=$vpcId)
  for res in $(echo ${dJ[$n]} | jq -r '.[]| .[] | select((.Associations|length) == 0) | .RouteTableId'); do
     echo "aws ec2 delete-route-table --route-table-id $res" >&2 
     aws ec2 delete-route-table --route-table-id $res
  done
  #for n in vpc-endpoints vpc-peering-connections; do
  for n in vpc-endpoints ; do
      dJ[$n]=$(aws ec2 describe-$n --f Name=vpc-id,Values=$vpcId)
      for id in $(echo ${dJ[$n]} | jq -r '.[] | (.[].VpcEndpointId // .[].VpcPeeringConnectionId)'); do
         echo aws ec2 delete-$n --${n%s}-id $id
         aws ec2 delete-$n --${n%s}-id $id
      done
  done
  # Skipping the Delete tags with the vpc, appearently not needed.
  # # aws ec2 delete-tags --resources $vpcId >&2 
  # Delete VPC.
  echo "aws ec2 delete-vpc --vpc-id $vpcId" >&2 
  aws ec2 delete-vpc --vpc-id $vpcId >&2 || let rv++
  return $rv
}

###
# Add  my public IP to the inBound SSH rules of a bastion instance's security group

letMeIn() {
   local iId=$1 port=${2:-22} cidr="$3"
   [ OK != "${iId/i-+([[:xdigit:]])/OK}" ] && { echo Usage: ${FUNCNAME[0]} instanceId; return 1; }
   #local cidr=$(wget http://ipinfo.io/ip -qO -)/32
   [ -z "$cidr" ] && cidr=$(curl http://ipinfo.io 2>/dev/null | jq -r .ip )/32
   local json=$(aws ec2 describe-instances --instance-ids $iId)
   groupId=$(echo $json | jq -r '.Reservations[].Instances[].SecurityGroups[0].GroupId'); 
   json=$(aws ec2 describe-security-groups --group-ids $groupId)
   q='.SecurityGroups[] | [ .GroupName, (.IpPermissions[].UserIdGroupPairs[] | [ .IpProtocol, .ToPort,  .IpRanges[].CidrIp ] ) ]'
q='.SecurityGroups[] | [ .GroupName, (.IpPermissions[] |  [ .IpProtocol, .ToPort,  .IpRanges[].CidrIp ] ) ]'
   echo $json | jq -c "$q"
   echo aws ec2 authorize-security-group-ingress --group-id ${groupId} --protocol tcp --port $port --cidr $cidr 
   aws ec2 authorize-security-group-ingress --group-id ${groupId} --protocol tcp --port $port --cidr $cidr 
   json=$(aws ec2 describe-security-groups --group-ids $groupId)
   echo $json | jq -c "$q"
}
#
# -----
#
# # Internal Functions
#
###
# Launch a NAT instance on the web network,   
# 
#      Usage: launch_Nat {vpc-id} {ami} [key [subnet {web}]]
# 
launch_NAT() {
    local vpcId ami key  subnet sgId json n rId iId
    local Usage="${FUNCNAME[0]} vpcId [AWS_ami [AWS_SSH_key]]"
    [ -z "$1" ] && echo $Usage && return 1
    vpcId=${1}
    # Get NAT ImageId (ami) from parameters, or environment, or CIDATA, or old-stale-wired-ami-for-a-few-regions: 
    for ami in $2 ${AWS_NAT_AMI} $(jq -r .AWS_NAT_AMI $CIDATA); do [ -n "$ami" ] && break; done
    [ -z "${ami/null/}" ] && case $(aws configure get region) in 
       us-west-2 ) ami=ami-8bfce8f2 ;;
       us-east-1 ) ami=ami-293a183f;;
       us-gov-west-1 ) ami=ami-e511ae84 ;;
       us-east-2 ) ami=ami-07fdd962 ;;
       * )  echo ERROR: ${FUNCNAME[0]} CIDATA must have  AWS_NAT_AMI for this region >&2; return 1 ;;
    esac
    n=$(jq -r .Profiles.default.KeyName $CIDATA); AWS_SSH_KEYNAME=${n/null/}
    key=${3:-${AWS_SSH_KEYNAME:-JONES.DANIEL.L.1265422345}}
    json=$(aws ec2 describe-subnets --f Name=tag:Name,Values=${4:-web-*} Name=vpc-id,Values=$vpcId )
    subnet=$(echo "$json" | jq -r '.Subnets[0].SubnetId')
    [ subnet-OK != "${subnet/-+([[:xdigit:]])/-OK}" ] && echo ${FUNCNAME[0]}: ERROR finding subnet >&2 && return 1
    #json=$(aws ec2 create-security-group --group-name NAT --description "NAT security $BUILD_TAG" --vpc-id $vpcId | jq -r .GroupId)
    json=$(aws ec2 describe-security-groups  --f Name=vpc-id,Values=$vpcId )
    sgId=$(echo "$json" | jq -r --arg n nat '.[] |.[] | select(.GroupName==$n).GroupId')
    [ OK != "${sgId/sg-+([[:xdigit:]])/OK}" ] && echo ${FUNCNAME[0]}: ERROR finding sgId >&2 && return 1
    cmd="aws ec2 run-instances --image-id $ami --count 1 --instance-type t2.micro --key-name $key --security-group-ids $sgId --subnet-id $subnet"
    echo $cmd >&2
    json=$( $cmd ) || return 1 
    # wait for instance to become ready, to get a  resourceId required for tag
    rId=$(echo $json | jq -r .ReservationId)
    [ OK != "${rId/r-+([[:xdigit:]])/OK}" ] && echo ${FUNCNAME[0]}: ERROR getting ReservationId >&2 && return 1
    local -i i=0; while [ $i -lt 10 ] ; do
       i+=1
       json=$(aws ec2 describe-instances --f Name=reservation-id,Values=$rId --o json)
       echo "$json" | grep pending && {
             sleep 10; continue
       }
        iId=$(echo $json | jq -r '.[] | .[].Instances[].InstanceId')
        [ OK == "${iId/i-+([[:xdigit:]])/OK}" ] && break
        echo wait for InstanceId...>&2
        sleep 10
    done
    [ OK != "${iId/i-+([[:xdigit:]])/OK}" ] && echo ${FUNCNAME[0]}: ERROR getting InstanceId >&2 && return 1
    echo aws ec2 create-tags --resources $iId --tags Key=Name,Value=NAT >&2
    aws ec2 create-tags --resources $iId --tags Key=Name,Value=NAT 
    echo aws ec2 modify-instance-attribute --no-source-dest-check --instance-id  $iId >&2
    aws ec2 modify-instance-attribute --no-source-dest-check --instance-id  $iId
    return 0
}

###
# Change a given subnet to public, by assciateing a custom route table, igw, and public IP on launch.
#
make_subnet_public() {
    local subnetId=$1 vpcId=$2 igw rtb n
    local -i rv=0
    n=modify-subnet-attribute; echo aws ec2 $n --map-public-ip-on-launch --subnet-id $subnetId >&2
    aws ec2 $n --map-public-ip-on-launch --subnet-id $subnetId >&2
    # add igw if needed to the vpc
    igw=$(aws ec2 describe-internet-gateways --f Name=attachment.vpc-id,Values=$vpcId | jq -r '.[]|.[].InternetGatewayId')
    [ OK != "${igw/igw-+([[:xdigit:]])/OK}" ] && { 
       echo "aws ec2 create-internet-gateway" >&2
       json=$(aws ec2 create-internet-gateway); igw=$(echo $json | jq -r '.[].InternetGatewayId')
       [ OK != "${igw/igw-+([[:xdigit:]])/OK}" ] && { echo ${FUNCNAME[0]}: ERROR create-internet-gateway json="$json"; return 1; }
       echo aws ec2 attach-internet-gateway --internet-gateway-id $igw --vpc-id $vpcId >&2 
       json=$(aws ec2 attach-internet-gateway --internet-gateway-id $igw --vpc-id $vpcId ) ||  let rv++
       # [ true != $(echo $json | jq '.Return') ] && { echo ${FUNCNAME[0]} ERROR json="$json"; return 1; }
       # add custom route table 
       echo "aws ec2 create-route-table --vpc-id $vpcId " >&2
       json=$(aws ec2 create-route-table --vpc-id $vpcId ); rtb=$(echo $json | jq -r '.[].RouteTableId' )
       [ OK != "${rtb/rtb-+([[:xdigit:]])/OK}" ] && { echo ${FUNCNAME[0]}: ERROR create-route-table returned json="$json" >&2 ; return 1; }
       echo "aws ec2 create-route --route-table-id $rtb --destination-cidr-block 0.0.0.0/0 --gateway-id $igw" >&2
       json=$(aws ec2 create-route --route-table-id $rtb --destination-cidr-block 0.0.0.0/0 --gateway-id $igw)
       [ true != $(echo $json | jq '.Return') ] && { echo ${FUNCNAME[0]} ERROR json="$json"; return 1; }
       echo "aws ec2 create-tags --resources $rtb --tags Key=Name,Value=public" >&2
       json=$(aws ec2 create-tags --resources $rtb --tags Key=Name,Value=public) 
       #[ true != $(echo $json | jq '.Return') ] && { echo ${FUNCNAME[0]} ERROR json="$json"; return 1; }
    }
    # associate custom route table with public subnet
    [ -z "$rtb" ] &&  {
         rtb=$(aws ec2 describe-route-tables --f Name=route.gateway-id,Values=$igw Name=vpc-id,Values=$vpcId |
             jq -r '.[]|.[].RouteTableId')
         [ OK != "${rtb/rtb-+([[:xdigit:]])/OK}" ] && { echo ${FUNCNAME[0]}: ERROR describe-route-table returned json="$json" >&2 ; return 1; }
    }
    echo "aws ec2 associate-route-table  --subnet-id $subnetId --route-table-id $rtb" >&2
    json=$(aws ec2 associate-route-table  --subnet-id $subnetId --route-table-id $rtb) || let rv++
    rtb=$(echo $json | jq -r .AssociationId)
    [ OK != "${rtb/rtbassoc-+([[:xdigit:]])/OK}" ] && { echo ${FUNCNAME[0]}: ERROR $n returned json="$json" >&2 ; return 1; }
    return $rv
}


###
# helper function for revoke rules
#
get_vpc_sg_inBound_rules() {
  local vpcId="$1" sg="$2" json="$3" qA qB qC qD
  # [ -z "$vpcId" -o -z "$sg" ] && { echo "Usage: ${FUNCNAME[0]} VPCID SG OPTIONALJSON" >&2;  return 1; }
  [ -z "$vpcId"  ] && { echo "Usage: ${FUNCNAME[0]} VPCID [SG [JSON]]" >&2;  return 1; }
  [ -z "$json" ] && { json=$(aws ec2 describe-security-groups --f Name=vpc-id,Values=$vpcId) || return 1; }
  # filter SG-json into one array of objects (dictionaries), that can be used for each source-group operation
  #  =>  [ {GroupId, port, protocol, sourceSg}, ... ]
  qA=".SecurityGroups[] | select(.VpcId==\"$vpcId\")"
  qB='{GroupId, in: (.IpPermissions[] | {IpProtocol, ToPort, "gid": [ ( .UserIdGroupPairs[] |.GroupId )] } ) }'
  qC='{GroupId, port: (.in.ToPort), protocol: (.in.IpProtocol), sourceSg: (.in.gid[] )}' 
  qD='"\(.GroupId) \(.protocol) \(.port) \(.sourceSg)"'
  [ -n "$sg" ] && qD="select(.GroupId==\"$sg\") | $qD"
  echo $json | jq -r  "$qA | $qB | $qC | $qD"  
}


###
# revoke ingress from other security groups
# 
revoke_vpc_sg_inBound_rules() {
  local vpcId="$1" sg="$2" json="$3" line  
  local -i rv=0
  get_vpc_sg_inBound_rules "$vpcId" "$sg" "$json" | while read line; do
     set -- $line; 
     [ $4 == $1 ] && continue
     cmd="aws ec2 revoke-security-group-ingress --group-id $1 --protocol $2  --source-group $4 "
     [ $3 != null ] && cmd+=" --port $3"
     echo $cmd
     $cmd || let rv++
  done
  return $rv
}


export TAG_ENV=evaluation
export TAG_STATE=build
# use BUILD_TAG (Not TAG_BUILD); BUILD_TAG is provided by Jenkins CI, i.e. BUILD_TAG=jenkins-ciStack-123
#export TAG_BUILD=foobar.1234
export TAG_USER="$USER"

###
# WIP to Add a common set of tags.
#
add_tags() {
   BUILD_TAG=${BUILD_TAG:-$(jq -r '.VpcName // .Project'  $CIDATA)}
   echo ${FUNCNAME[0]} YTBD: move VPC tags values into CIDATA or job >&2
   aws ec2 create-tags --resources $1 --tags Key=environment,Value=$TAG_ENV Key=created_by,Value=$TAG_USER \
    Key=state,Value=setup Key=modtime,Value=$(date +%s) Key=Build,Value=${BUILD_TAG}
}

shopt -s extglob

###
# 
awsGetVpc() {
  #local profile=${AWS_PROFILE:-default} usage="${FUNCNAME[0]} [vpc-id|Name]"
  local usage="${FUNCNAME[0]} [vpc-id|Name]"
   # This works but vim syntax editor is annoyed by the POSIX character class .
   #vpc-+([[:xdigit:]]) ) json=$(aws ec2 describe-vpcs --o json --vpc-ids $1) || return 2 ;;
  case  $1 in 
   vpc-* ) aws ec2 describe-vpcs --o json --vpc-ids $1  ;;
   * ) aws ec2 describe-vpcs --f Name=tag:Name,Values=$1 --o json  ;;
  esac
}

###
# WIP ... graphics YTBD 
showVpc() {
  echo This function is not complete, wip... >&2
  local region=$(aws configure get region)  || { echo ERROR check aws configuration >&2; return 1; }
  #local usage="${FUNCNAME[0]} [vpc-id|Name]" && [ -z "$1" ] && { echo Usage $usage; return 1; }
  local usage="${FUNCNAME[0]} [vpc-id|Name]" 
  local vpc="" vpcId json subnets instances igw sgJSON sg
  json=$(aws ec2 describe-vpcs --o json --vpc-ids ${1:-$(getVpcId)} --region $region) || return 2 
  [ 1 == $(echo $json | jq '.Vpcs | length') ] || { echo No Vpc found, usng region: $region; return 1; }
  vpcId=$(echo "$json" | jq -r '.Vpcs[0].VpcId')  || return 1
  subnets=$(aws ec2 describe-subnets --filters  "Name=vpc-id,Values=$vpcId" --o json --region $region )
  showSubnets "$subnets"
  q='.[][0]| "\(.InternetGatewayId) \(.Attachments[0].State) "'
  echo Gateway: $(aws ec2 describe-internet-gateways --f Name=attachment.vpc-id,Values=$vpcId --o json --region $region | jq "$q")
  #instances=$(aws ec2 describe-instances  --f Name=vpc-id,Values=$vpcId --o json --region $region)
  echo Instances: $(echo "$instances" | jq '.[][].Instances[].InstanceId ' | wc -l)
  showInst "$instances"
  # security Groups
  #sgJSON=$(aws ec2 describe-security-groups  --f Name=vpc-id,Values=$vpcId --o json --region $region)
  showSGrules $vpcId
# echo "$sgJSON"
  # Elastic IPs
# aws ec2 describe-addresses --filters "Name=domain,Values=vpc"
  # Route Tables 
   #aws ec2 describe-route-tables --f Name=association.main,Values=false Name=vpc-id,Values=$vpcId
#echo Routes YTDB
   #aws ec2 describe-route-tables --f  Name=vpc-id,Values=$vpcId
  # Endpoints
  # Peering
  # network ACLs
  # Customer Gateways
  # VPN Connections
  # DNS Options Sets
}


 # list the ciData SG Names:
 # sgNames=$(cat $CIDATA | jq -r '.Security.SGinBound | to_entries | .[].key')
###
# Function add_sg creates security groups for given names in given vpcId.
# Given names must have known rule sets in the ciData Security.SGinBound
add_sg() {
   local vpcId=$1 name json SG_all sgtype  n sgId ; local -i rv=0
   BUILD_TAG=${BUILD_TAG:-$(jq -r '.VpcName // .Project'  $CIDATA)}
   # YTBD change to use rule sets from ciData 
   local Usage="Usage: ${FUNCNAME[0]} Vpc sg-name1 [sg-name2 ...]\n"
   shift || {  echo "$Usage" ;  return 1; }
   # get all the SGs in this VPC
   SG_all=$(aws ec2 describe-security-groups  --f Name=vpc-id,Values=$vpcId ) || return 1
   declare -A a
   for name ; do a[$name]=1 ; done  # uniq the remaining parameters, to prevent duplicate errors
   for name in ${!a[@]} ; do
        a[$name]=xxx
       # Check if sg exits, there should already be a default
       sgId=$(echo $SG_all | jq -r --arg n $name '.[]|.[] | select(.GroupName==$n).GroupId') || return 1
       [ OK == "${sgId/sg-+([[:xdigit:]])/OK}" ] && { echo ${FUNCNAME[0]}: $name already exists: $sgId $vpcId >&2 ; continue; }
       # Create SG with given name, if none. 
       echo aws ec2 create-security-group --group-name $name --description "$name security ${BUILD_TAG}" --vpc-id $vpcId --o json >&2
       json=$(aws ec2 create-security-group --group-name $name --description "$name security ${BUILD_TAG}" --vpc-id $vpcId --o json)
       sgId=$(echo $json | jq -r .GroupId)
       [ OK != "${sgId/sg-+([[:xdigit:]])/OK}" ] && echo "${FUNCNAME[0]}: ERROR returned json=$json" >&2 && return 1
   done
   for name in ${!a[@]} ; do add_sg_rules $vpcId $name ingress || let rv++ ; done
   return $rv
}


###
# Function add_sg_rules applies inBound rules defined in Project JSON Security.SGinBound, to a given VPC
#
add_sg_rules() {
 local n vpcId=$1 name=$2 protocol pp io=${3:-ingress} ruleList src port q sg SGs n rule proto dq
 [ -z "$name" ] && { echo Usage ${FUNCNAME[0]} vpcId groupName  >&2; return 1; }
 SGs=$(aws ec2 describe-security-groups  --f Name=vpc-id,Values=$vpcId ) || return 1
 [ -z "$SGs" ] && return 1
 sg=$(echo $SGs | jq -r --arg n $name '.[]|.[] | select(.GroupName==$n)')
 [ -z "$sg" ] && { echo "${FUNCNAME[0]}: WARNING: SG not found \"$name\""; return 1; }
 unset A; declare -A A
 for n in OwnerId GroupId ; do A[$n]=$(echo $sg | jq -r ".$n"); done
 # add local self to access ruleList
 ruleList="-1:sg-$name "
 #echo aws ec2 authorize-security-group-ingress --source-group ${A[GroupId]} --group-owner ${A[OwnerId]} --group-id ${A[GroupId]} --protocol -1
 #aws ec2 authorize-security-group-ingress --source-group ${A[GroupId]} --group-owner ${A[OwnerId]} --group-id ${A[GroupId]} --protocol -1
 # add rules 
 ruleList+=$(jq -r .Security.SGinBound.$name $CIDATA)
 [ -z "${ruleList/*null/}" ] && { echo ERROR: No Security.SGinBound.$name CIDATA; return 1; }
 for rule in ${ruleList}; do
    rule=${rule//,/ }; # comma2space spearated elements, i.e. new rule="22 443:myIP nps fnmoc nmci0 nrl"
    for port in ${rule%:*}; do for src in ${rule#*:}; do
      proto=tcp; [ -z "${port#*/*}" ] && proto=${port#*/}; port=${port%/*};
      [ $port == -1 ] && proto=-1
      # build the query
      #q='.IpPermissionsEgress[] | select(.IpProtocol==$proto )'; # outBound not today
      q='.IpPermissions[] | select(.IpProtocol==$proto)'; # inBound
      [ ${port} -gt 0 ] && q+='| select(.ToPort == ($port | tonumber))'

      case $src in 
          sg-*) groupId=$(echo $SGs | jq -r --arg n ${src#sg-} '.[]|.[] | select(.GroupName==$n).GroupId') || continue;
                [ -z "$groupId" ] && { echo ${FUNCNAME[0]} WARNING: SG: $name, $io rule source SG not found: $src >&2 ; continue; }
                q+='| .UserIdGroupPairs[] |select(.GroupId==$gid)'
                q+='| select(.UserId==$uid)'
                [ -n "$(echo $sg | jq --arg gid "$groupId" --arg uid "${A[OwnerId]}" --arg port $port --arg proto $proto "$q")" ] &&
                    echo ${FUNCNAME[0]}: No Change to SG: $name, $io rule: $proto $port $src && continue
                if [ $port == -1 ]; then 
                    echo aws ec2 authorize-security-group-ingress --source-group "${groupId}" --group-owner ${A[OwnerId]} --group-id ${A[GroupId]} --protocol  $proto
                    aws ec2 authorize-security-group-ingress --source-group "${groupId}" --group-owner ${A[OwnerId]} --group-id ${A[GroupId]} --protocol $proto 
                else
                    echo aws ec2 authorize-security-group-ingress --source-group ${groupId} --group-owner ${A[OwnerId]} --group-id ${A[GroupId]} --protocol $proto --port $port
                    aws ec2 authorize-security-group-ingress --source-group ${groupId} --group-owner ${A[OwnerId]} --group-id ${A[GroupId]} --protocol $proto --port $port
                fi
         ;;
         # Using this .[]?, will result in a compile error with jq version <  1.4
         # The point of this test was to allow the value to be either a string or  json-array.
         #    q="(.Security.SrcCidr.$src // empty) | (.[]? // .)"
         # This effectively does the same in jq 1.3:
         #    q="(.Security.SrcCidr.$src // empty)"'| if (type) == "array" then .[]  else .  end'
         #
         * ) dq="(.Security.SrcCidr.$src // empty)"'| if (type) == "array" then .[]  else .  end'
             #q='.IpPermissions[] | select(.IpProtocol==$proto)'; # inBound
             q='.IpPermissions[] | select(.IpProtocol==$proto)| select(.ToPort==($port|tonumber)) '; # inBound
             q+='| .IpRanges[] |select(.CidrIp==$cidr).CidrIp'
             for cidr in $(jq -r "$dq" $CIDATA); do
                  [ $src == myIP ] && cidr=$(wget http://ipinfo.io/ip -qO -)/32
                  [ -z "$cidr" ] && { echo ERROR No .Security.SrcCidr.$src in CIDATA; continue; }
                  [ -n "$( echo $sg | jq --arg cidr $cidr --arg uid ${A[OwnerId]} --arg port $port --arg proto $proto "$q" )" ] &&
                    echo ${FUNCNAME[0]}: No Change to SG: $name, $io rule: $proto $port $cidr && continue
                  echo   aws ec2 authorize-security-group-ingress --group-id ${A[GroupId]} --protocol $proto --port $port --cidr $cidr 
                  aws ec2 authorize-security-group-ingress --group-id ${A[GroupId]} --protocol $proto --port $port --cidr $cidr 
                done
         ;;
       esac
    done; done
 done
}

#!/bin/bash
#md+ bashDoc transforms this to markdown doc.
####
# # VPC Peering functions
#

###
# Format report of VPC tag-names from JSON
# 
# >$ aws ec2 describe-vpcs | j2VpcNames 
# >vpc-69da220c CLIMO 
j2VpcNames() { local q='.Vpcs[]| .VpcId +$d+ ('"$qTagName"')'; jq -r --arg d " " "$q"; }

lsVpcNames() { 
    [ -z "$1" ] && {  aws ec2 describe-vpcs | j2VpcNames; } || {
       [ '--' ==  "$1" ] && { j2VpcNames ; } || echo "$1" | j2VpcNames; } 
}

#### 
# Given the value of the Tags Name, this shell function uses a JQ filter, to return the vpcId from json input
# Example use:
#    > vj=$(aws ec2 decribe-vpcs)
#    > hubId=$( echo  $vj |  VpcName2Id ciBootStrap)
#    > spokeId=$( echo  $vj |  VpcName2Id N39_IDD)
#    > PeerVpc2Hub $spokeId $hubId 
#    or
#    > PeerVpc2Hub N39_IDD ciBootStrap
VpcName2Id() { [ -z "$1" ] && return 1; local q='.Vpcs[]| select( ('"$qTagName"') == $n ) | .VpcId'; jq -r --arg n $1 "$q"; }
VpcName2Json() { [ -z "$1" ] && return 1; local q='.Vpcs[]| select( ('"$qTagName"') == $n ) '; jq -r --arg n $1 "$q"; }
VpcId2Json() { [ -z "$1" ] && return 1; local q='.Vpcs[]| select( .VpcId == $n ) '; jq -r --arg n $1 "$q"; }
showPcx() {
  local q='.[]|.VpcPeeringConnectionId +$d+ .Status.Code +$d+ (.RequesterVpcInfo | .CidrBlock +$d+ .VpcId)'
  q+='+$D+(.AccepterVpcInfo | .CidrBlock +$d+ .VpcId)'
  q+='+$d+('"$qTagName"')'
  jq -r --arg d "${1:- }" --arg D "${1:- <=> }" "$q"
}

###
# Peer VPCs owned by this account, given vcpId/s or tag Name
#    > PeerVpc2Hub $spoke $hub 
#    > PeerAndRouteEndpoint $spoke $hub  $endpoint
# 
PeerVpc2Hub() {
  [ $# != 2 ] && { echo Usage: ${FUNCNAME[0]} spoke-vpc hub-vpc >&2; return 1; }
  local vj rj pcx pj vj sj delay line q spoke="$1" hub="$2"
  vj=$(aws ec2 describe-vpcs) || return 1
# - If given a Name, find the VpcId with that tag Name
  [ -n "${spoke/vpc-*/}" ] && { spoke=$(echo $vj | VpcName2Id $spoke) || return 1; }
  [ -n "${hub/vpc-*/}" ] && { hub=$(echo $vj | VpcName2Id $hub) || return 1; }
  [ -z "${hub}" -o -z "${spoke}" ] && { echo ERROR ${FUNCNAME[0]}: could not find VPC-ID for given Name  >&2 || return 1; }
  [ -z "${spoke}" ] && { echo ERROR ${FUNCNAME[0]}: could not find VPC-ID for given Name \""$spoke"\" >&2 || return 1; }
  [ -z "${hub}" ] && { echo ERROR ${FUNCNAME[0]}: could not find VPC-ID for given Name \""$hub"\" >&2 || return 1; }
  [ $hub == $spoke ] && { echo ERROR ${FUNCNAME[0]}: Cannot peer VPC to itself; return 1; }
  pj=$(aws ec2 describe-vpc-peering-connections) || return 1
# - If an existing pcx status is active, show it and return
  sj=$(echo $pj | filterJson_pcx_status $spoke $hub active) || return 1
  [ -n "$sj" ] && { echo "[$sj]" | showPcx >&2; echo $sj | jq -r .VpcPeeringConnectionId; return 0; }
# - Make a new request for pcx (ASSUMES the same owner of hub and spoke)
  echo aws ec2 create-vpc-peering-connection --vpc-id $spoke --peer-vpc-id $hub >&2
  rj=$(aws ec2 create-vpc-peering-connection --vpc-id $spoke --peer-vpc-id $hub)
  pcx=$(echo $rj | jq -r .VpcPeeringConnection.VpcPeeringConnectionId)
  echo $rj  | jq '[.VpcPeeringConnection]' | showPcx >&2
# - Wait for the request status code has pending-accept
  local -i delay=10
  while :; do
      line=$(aws ec2 describe-vpc-peering-connections --vpc-peering-connection-ids $pcx | jq '.VpcPeeringConnections'|showPcx)
      echo "$line" | grep " active " >&2  && return 0
      echo "$line" | grep " pending-accept" >&2 && break
      [ $delay -gt 5000 ] && { echo ERROR ${FUNCNAME[0]} Timeout waiting for pending-acceptance status for $pcx >&2 ; return 1; }
      sleep $delay
      let delay+=$delay
  done
# - complete by accepting the  pending request
  echo "aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id  $pcx" >&2
  sj=$(aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id  $pcx) || return 1
# - Show the final  request status code 
## Do we need to delay/wait for it to go to active status?
  echo "$sj" | showPcx >&2
  # echo pcx to stdout, if all is well
  echo $pcx
  # routes ytbd
}

###
# Given two VpcIds, return any description, of an active peering
#
getPcxJson() {
  local pj rj
  pj=$(aws ec2 describe-vpc-peering-connections) || return 1
  rj=$(echo $pj | filterJson_pcx_status $1 $2 active) || return 1
  [ -z "$rj" ] && { rj=$(echo $pj | filterJson_pcx_status $2 $1 active) || return 1; }
  echo $rj | jq . 
}
###
# Route to and from Spoke/hub peered VPCs, given two VpcIds.
#
PeerVpcRoutes() {
  [ $# != 2 ] && { echo Usage: ${FUNCNAME[0]} spoke-vpc hub-vpc >&2; return 1; }
  local vj rj pcx pj vj sj delay line q info spoke="$1" hub="$2"
  local -i rv=0
  vj=$(aws ec2 describe-vpcs) || return 1
# - If given a Name, find the VpcId with that tag Name
  [ -n "${spoke/vpc-*/}" ] && { spoke=$(echo $vj | VpcName2Id $spoke) || return 1; }
  [ -n "${hub/vpc-*/}" ] && { hub=$(echo $vj | VpcName2Id $hub) || return 1; }
  [ -z "${hub}" -o -z "${spoke}" ] && { echo ERROR ${FUNCNAME[0]}: could not find VPC-ID for given Name >&2 || return 1; }
  [ -z "${spoke}" ] && { echo ERROR ${FUNCNAME[0]}: could not find VPC-ID for given Name "$spoke" >&2 || return 1; }
  [ -z "${hub}" ] &&   { echo ERROR ${FUNCNAME[0]}: could not find VPC-ID for given Name "$hub"   >&2 || return 1; }
  [ $hub == $spoke ] && { echo ERROR ${FUNCNAME[0]}: No routes needed for VPC to itself; return 1; }
# - Find an existing peering with status of active
  pj=$(getPcxJson $spoke $hub) || return 1
  [ -z "$pj" ] && { echo "ERROR ${FUNCNAME[0]}: Could not find pcx-ID for $spoke <=> $hub " ; return 1; }
  echo "[$pj]"  | showPcx >&2
# - Find pcx between given VpcIds
  pcx=$(echo $pj | jq -r .VpcPeeringConnectionId)
# - Create routes between peer destinations in each route table used in each given VPCs.
  accepter=$(echo $pj | jq .AccepterVpcInfo)
  requester=$(echo $pj | jq .requesterVpcInfo)
  rj=$(aws ec2 describe-route-tables) || return 1
  q='.RouteTables[] | select( .RouteTableId == $t).Routes[]|select(.VpcPeeringConnectionId == $pcx).DestinationCidrBlock'
  vpcId=$(echo  $pj | jq -r .AccepterVpcInfo.VpcId)
  cidr=$(echo  $pj | jq -r .RequesterVpcInfo.CidrBlock)
  for rt in $(echo $rj | jq -r --arg v $vpcId '.RouteTables[] | select( .VpcId == $v) | .RouteTableId'); do
    echo $rj | jq -r --arg t $rt --arg pcx $pcx "$q" | grep -q $cidr && {
       echo $vpcId $rt $cidr via $pcx entry exists >&2; continue
    }
    cmd="aws ec2 create-route --route-table-id $rt --vpc-peering-connection-id $pcx --destination-cidr-block $cidr"
    echo $cmd;
    [ "$($cmd | jq .Return)" == true ] &&  continue
  done
  vpcId=$(echo  $pj | jq -r .RequesterVpcInfo.VpcId)
  cidr=$(echo  $pj | jq -r .AccepterVpcInfo.CidrBlock)
  for rt in $(echo $rj | jq -r --arg v $vpcId '.RouteTables[] | select( .VpcId == $v) | .RouteTableId'); do
    echo $rj | jq -r --arg t $rt --arg pcx $pcx "$q" | grep -q $cidr && {
       echo $vpcId $rt $cidr via $pcx entry exists >&2; continue
    }
     cmd="aws ec2 create-route --route-table-id $rt --vpc-peering-connection-id $pcx --destination-cidr-block $cidr"
     echo $cmd; 
     [ "$($cmd | jq .Return)" != true ] &&  { let rv++; echo ERROR ${FUNCNAME[0]}:$cmd; }
  done
# - This does not put SG rules into the project settings (CIDATA) must also have Security objects to allow traffic.
  return  $rv
}

###
# Filter for peering existing connecions
#
# For example:
# 
# ````bash
# vj=$(aws ec2 describe-vpcs)
# spoke=$(echo $vj | VpcName2Id N39_IDD)
# hub=$(echo $vj | VpcName2Id ciBootStrap)
# pj=$(aws ec2 describe-vpc-peering-connections)
# echo $pj | filterJson_pcx_status $spoke $hub active
# ````

filterJson_pcx_status() {
    [ $# != 3 ] && { echo Usage: "${FUNCNAME[0]} {spoke|Requestor-vpc} {hub|Acceptor-vpc} {status}" >&2 ; return 1; }
    local q
    q='.VpcPeeringConnections[]'; q+='| select(.Status.Code == $s)';
    q+='| select(.AccepterVpcInfo.VpcId == $a)'; q+='| select(.RequesterVpcInfo.VpcId == $r)'
    jq --arg r $1 --arg a $2 --arg s $3 "$q"
}

###
# Given VpcId, delete any vpc-peering-connections and associated routes
#

delete_vpc_peering() {
   local pj rj q rq vpcId="$1"
   # "q" is the jq filter for getting the pcx-id 
   q='.VpcPeeringConnections[]| select( .AccepterVpcInfo.VpcId == $v ) // select(.RequesterVpcInfo.VpcId == $v)'
   q+='|.VpcPeeringConnectionId'
   # "rq" is the jq filter for building an aws-cli command to delete routes using a  pcx-id 
   rq='.RouteTables[]| {RouteTableId, "Routes": (.Routes[] | select(.VpcPeeringConnectionId == $pcx))}'
   rq+='| "aws ec2 delete-route --route-table-id " + .RouteTableId + " --destination-cidr-block " + (.Routes.DestinationCidrBlock)'
   pj=$(aws ec2 describe-vpc-peering-connections) || return 1
   rj=$(aws ec2 describe-route-tables)
   for pcx in $(echo $pj | jq -r --arg v $vpcId "$q" ); do 
             echo $rj | jq -r --arg pcx $pcx "$rq"; 
             echo aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id $pcx
   done | sh -x
}

###
# Show terse one line display of Vpc-Peering connections
#
showPeering() {
# -  Optionally given JSON as the first arguement.
  local pj="$1"
  [ -z "$pj" ] && { pj=$(aws ec2 describe-vpc-peering-connections) || return 1; }
  echo $pj  | jq '[.VpcPeeringConnections[]]' | showPcx >&2
}


###
# Add ingress SG rules from peer hub-type VPCs  to this project vpc, given security group name.
# For example, Allow https-gateway (having "web" SG-name in hub) to connect to project server with "app" SG-name.
# 
#     add_hub_sg_ingress web app 80
#     add_hub_sg_ingress web app 8080
# 
add_hub_sg_ingress() {
  local usage="Usage: ${FUNCNAME[0]} hubVpc_src_GroupName myVpc_destination_GroupName port "
  [ $# -lt 3 ] && echo $usage && return 1
  local hVpc vpcId srcGN=$1  dstGN=$2 port=$3 proto=${4:-tcp} srcSG destSG hub q hVpc cmd
  vpcId=$(getVpcId)
  json=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values=$vpcId)
  q='.SecurityGroups[]| select( .GroupName == $n )';
  dstSG=$(echo $json | jq -r --arg n ${dstGN} "$q|.GroupId")
  for  hub in $(aws ec2 describe-vpcs --f "Name=tag:VpcType,Values=hub" | jq -r '.Vpcs[]| .VpcId + ":" + '"${qTagName}"); do
     hVpc=${hub/:*/}
     [ "${hVpc/vpc-*/OK}" != "${vpcId/vpc-*/OK}" ] && echo vpcIDs are NOT OK && return 1
     [ $hVpc == $vpcId ] && continue
     json=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values=$hVpc)
     srcSG=$(echo $json | jq -r --arg n ${srcGN} "$q|.GroupId")
     [ "${srcSG/sg-*/OK}" != "${dstSG/sg-*/OK}" ] && echo sg-IDs are NOT OK && return 1
     cmd="aws ec2 authorize-security-group-ingress"
     cmd+=" --source-group $srcSG"
     cmd+=" --group-owner $(aws iam get-user | jq -r .User.Arn | cut -d: -f5)" || { echo ERROR getting owner; return 1; }
     cmd+=" --group-id $dstSG --protocol $proto --port $port"
     echo \# add ingress from $hVpc $srcGN
     echo $cmd
     $cmd
  done
}



#!/bin/bash
#md+ bashDoc transforms this to markdown doc.

# # User Functions
#
###
# The _ciStack_  function is the main driver for this shell library. 
# Together with templates, it is used to manage a project resource stack, from providers such as AWS EC2 service.
# The rational for ciStack is to provide a facade interface, to reduced risk without productivity loss.
# Risk is lowered by using IAM policies and roles that implement technical controls. Productivity is not impacted, prossbly improved
# by the automation and reusability it provides.
#
# The CIDATA environment variable holds the path to the project settings, encoded in JSON.
#
# ciStack sub-commands render ciData into CLI or SDK operations, based on the provider.
# Using the aws-cli:
#
#  - "launch" - creates VM instances for a CI environment in an AWS VPC named by CIDATA.
#  - "stop" will request instances of a CI environment in an AWS VPC named by CIDATA, to be stopped.
#  - "start"  will request instances of a CI environment in an AWS VPC named by CIDATA, to run.
#  - "terminate" - destroys instances of a CI environment in an AWS VPC named by CIDATA.
#  - "show" describes instances or resources of a CI environment in an AWS VPC named by CIDATA.
#  - "help" describes all functions of this module, using the bashDoc function.
#
# Command completion is supported for Bash, interactively, by sourcing the library.
#
# Use ciStack to focus on a project-VPC. Run it on an administration node (Bastion), which can assume 
# the IAM-role for that VPC,  to manage AWS resources. 
#
# Environment: CIDATA is set when given an optional third argument, for examle:
# 
#  "ciStack show AWS_WASP.json" not only describes instances in project VPC, it also sets CIDATA to AWS_WASP.json.
# 
# Two IAM Instance Roles are provided by the create_vpc_policy function. If attached to instances, it provides
# VPC lock-down of allowed operations. Attach the VPC-{vpcName} profile to your Bastion instance, and the VPC-{vpcName}-ro
# to instances that Bastion users (or applications) should control.  Limit logins to administrators, or operators for the project,
# on any instance that you assign it the VPC-{vpcName} role.
#
#
# Dependencies: 
#
#  - aws-cli 1.10.38 or greater
#  - jq 1.3 or greater 
#  - Shell-libs: ciBootStrap.sh, ciData.sh, 
#  - For cookbooks: git, chefdk  
#
# Document version:
#
#       $Id: ciStack.sh 72369 2018-07-14 21:19:16Z dljones@nps.edu $
#       $HeadURL: https://svn.nps.edu/repos/metocgis/infrastructure/trunk/tools/ciStack.sh $
#

## [ -z "${SHELLOPTS/*posix*/}" ] && echo ERROR MUST Use '#!/bin/bash' in posix mode && return 1
! shopt -q extglob  && shopt -s extglob

##
##  Functions: source additional bash shell functions from same folder as self.
##
for shellLib in \
   $(dirname ${BASH_SOURCE[0]})/ciData.sh \
   $(dirname ${BASH_SOURCE[0]})/ciBootStrap.sh \
   $(dirname ${BASH_SOURCE[0]})/vpc_policy.sh \
    ;
do
   . ${shellLib} && continue
   echo ERROR in shellLib: ${shellLib}, waiting 600 seconds before exit, for you to read this...  >&2
   sleep 600; exit 1
done

export  SCHEMA_CIDATA=20170226

###
# Migrate ciData JSON to a new schema
#
# A json document is output, from converting $CIDATA to the newest Schema.
# Missing objects are taken from the schema template, or an attempt is made to convert existing objects in $CIDATA.
# The user should manually verify the resulting JSON, before committing it as $CIDATA.
#
migrateSchema() {
   # add ChangeLog
   local usage="${FUNCNAME[0]} > new.json"
   local -i ct=0
   local tmp json template
   template=${CIDATA%/*}/templates/Schema_${SCHEMA_CIDATA}.json
   json=$(changeLog $CIDATA ${FUNCNAME[0]}: to version ${SCHEMA_CIDATA} )
   # change .Name to .Project in CIDATA files.
   [ "$(echo $json | jq -r .Project)" == null ] && {
       tmp=$(echo $json | jq '{ "Project": (.Name)}') 
       json=$(echo $json $tmp | jq -s 'add | del(.Name)')
       let ct++
   }
   n=Schema
   [ $(echo $json | jq .$n) == null ] && {
      tmp=$(jq -n --arg x ${SCHEMA_CIDATA} '{"Schema": $x }')
      json=$(echo $tmp $json | jq -s add)
      let ct++
      echo Adding Schema to $CIDATA >&2
   }
   n=Profiles
   [ "$(echo $json | jq .$n)" == null ] && {
      tmp=$(jq {$n} $template)
      json=$(echo $tmp $json | jq -s add)
      let ct++
      echo Adding Profiles to $CIDATA >&2
   }
   n=InstanceRoles
   [ "$(echo $json | jq .$n)" == null ] && {
      [ $(echo $json | jq .Instances) != null ] && {
        tmp=$(jq .$n $template)
        tmp+=$(echo $json | jq -c '.Instances[] | { (.Name) : (.|del(.Name)|del(.Roles)) }')
        tmp=$(echo $tmp | jq -s 'add|{"'$n'": .}')
        json=$(echo $tmp $json | jq -s 'add|del(.Instances)')
        echo Migrating Instances object to $n >&2
      } || { 
        tmp=$(jq {$n} $template) 
        json=$(echo $tmp $json | jq -s add)
      }
      let ct++
      echo Adding $n to $CIDATA >&2
   }
   [ $ct -gt 0 ] && {
       cp -p $CIDATA $CIDATA.$(date +%s)
       echo $json | jq . >$CIDATA
       echo ${FUNCNAME[0]} Writing migrated $CIDATA >&2; $cmd
   }
   return $ct
}

###
# This is the driver function of the library. Usage of this function requires one subcommand, 
# and optional project settings.
#
# Use tab completion, first to see available subcommands, and after that the optional project settings.
#
#      $ awsLoad; # or module load aws, for one-time setup of your shell
#      $ ciStack <tab><tab>
#      create_vpc   generate_ciData  help     run       security    start   tag
#      delete_vpc   generate_ciJob   launch   s3Store   show        stop    terminate
#      $ ciStack show <tab><tab>
#      AWS_ACAF.json   AWS_CJMTK.json  AWS_WASP.json   motes.json      witchy.json
#      AWS_CJG.json    AWS_FGISV.json  AWS_OPT.json    ciStack.json    nites.json      
#
# Subcommands may prompt (or read CI Job Parameters) for additional requirements, for example:
# 
#      $ ciStack laun<tab><Enter>
#      1) bastion	  3) gitlab	   5) logger	    7) openldap	     9) proxy
#      2) djones	  4) jenkins	   6) nexus	    8) openproject  10) ALL
#      Select > 7<Enter>
#      launching openldap in vpc-cd1ad7a8
#      update_s3Store: checking store: aws s3 ls s3://cibootstrap
#      update_s3Store: checking cookbook
#      update_s3Store: aws s3 sync  bucket/ciStack s3://cibootstrap/ciStack
#      aws ec2 run-instances  --user-data file:///path/to/userData/openldap-2.148 --cli-input-json  {
#      .... output edited for brevity ...
#      openldap-2  i-0ed3c2c87 running  t2.mediu us-gov-west-1a vpc-cd1ad7a8 CI-vpc-ciBootS 10.0.20.57 
#

export CIDATA CIDATA_SOURCE
ciStack() {
   _ciStack_dependencies >/dev/null || return 1
   local usage="Usage: ${FUNCNAME[0]} {show|help|launch|stop|start|terminate|...}  ciData.json"
   local n  myVpc subCmd=$1 idList  mask cmd name
   local -i rv=0
   # Ensure use of WORKSPACE/ciData
   CIDATA=$WORKSPACE/ciData/${2:-${CIDATA##*/}}
   # mask subcommands that  cannot be used w/o CIDATA folder.
   [ ! -d $WORKSPACE/ciData ] && { echo Warning: No WORKSPACE/ciData >&2; mask=get_ciData; }
   # mask subcommands that require ciData.json file:
   [ -z "$mask" ] && [ ! -f "$CIDATA" ] && mask=X 
   ciStack_schema_test || return 1
   # mask subcommands that cannot be used before the VPC is created.
   [ -z "$mask" ] && { mask=XX; check_vpc >/dev/null  && myVpc=$(getVpcId) && mask=""; }
   check_aws_credentials || { echo credential check error; return 1; }

   case ${mask}${subCmd} in 
     *help ) bashDoc ${BASH_SOURCE[0]} | grep -v -- '-- images/.* --' |  more ;;
     launch )
        for name in  $(getInstanceNames ${INSTANCE_NAMES:-selectRole}); do
            echo launching ${name} in $myVpc  >&2
            launch_instance ${name} || { echo Failed to launch ${name}; rv+=1; }
        done 
        [ -n "$JOB_NAME" ] && [ "$rv" == 0 ] && {
          for n in  $(getInstanceNames inVpc); do
            [ X != X${n/${name}-*/} ] && continue
            echo ::::::::::::::::::::::: getConsole $n :::::::::::::::::::::::::::::::::
            getConsole $n
          done
        }
        showInst "$(aws ec2 describe-instances  --f Name=vpc-id,Values=$myVpc)"
        ;;
     stop | start | run )
        subCmd=${subCmd/run/start}
        unset S; declare -A S; S[start]=stopped; S[stop]=running
        json=$(get_instances $(getInstanceNames ${INSTANCE_NAMES:-Select}))
        showInst "$json"
        idList=$(echo $json| jq -r --arg s ${S[$subCmd]} '.Reservations[].Instances[] |  select(.State.Name==$s)| .InstanceId')
        [ -n "$idList" ] && {
            echo aws ec2 ${subCmd}-instances --instance-ids $idList >&2
            aws ec2 ${subCmd}-instances --instance-ids $idList
            showInst "$json"
        }
       ;;
     show )
        q='.Vpcs[0] | {VpcId, CidrBlock'
        q+=', "Name": (.Tags[] | select(.Key=="Name").Value )'
        q+=', "Env": (.Tags[] | select(.Key=="environment").Value )'
        q+='} | "VPC: \(.Name) \(.VpcId) \(.CidrBlock) \(.Env)"'
        echo "$CHECK_VPC_JSON" | jq -c -r "$q"
        json=$(aws ec2 describe-instances  --f Name=vpc-id,Values=$myVpc)
        showInst "$json"
        showVol "$json"
        # YTBD show the networks, gateways, route tables, security groups, inBound and outBound rules, ... 
       rv=0
       ;;
     tag )
        json=$(get_instances $(getInstanceNames ${INSTANCE_NAMES:-Select}))
         echo deprecated this function, Sorry.
        # tagInstances "$json" $id $3 $4
       ;;
     terminate )
       json=$(get_instances $(getInstanceNames ${INSTANCE_NAMES:-Select}))
       showInst "$json"
       idList=$(echo $json| jq -r '.Reservations[].Instances[].InstanceId')
       [ -n "$idList" ] && { 
              [ "${OK_TO_TERMINATE^^}" != TRUE ] && { echo Select OK_TO_TERMINATE, or export OK_TO_TERMINATE=True ; return 1; }
              echo aws ec2 terminate-instances --instance-ids $idList >&2
              aws ec2 terminate-instances --instance-ids $idList || return 1
        } 
        showInst "$(aws ec2 describe-instances  --f Name=vpc-id,Values=$myVpc)"
       ;;
     XXcreate_vpc )
           rv=0
           vpcName=$(jq -r .VpcName ${CIDATA:-/dev/null})
           echo create_vpc $vpcName >&2 
           [ -z "$vpcName" ] && { echo No CIDATA or VpcName.; return 1; }
           create_vpc $vpcName >&2  ||   let rv++; 
           create_vpc_policy >&2 || let rv++
           # json=$(aws ec2 describe-vpcs --f "Name=tag:Name,Values=${vpcName}")
           check_vpc >/dev/null || let rv++
           generate_buckets || let rv++
           [ "${AGENT_PROFILE^^}" == TRUE ] && { create_vpc_agent_user || let rv++ ; }
       ;;
     peer_vpc )
         .  $(dirname ${BASH_SOURCE[0]})/vpcpeering.sh
         vpcName=$(jq -r .VpcName ${CIDATA:-/dev/null})
         vpcId=$(aws ec2 describe-vpcs --f "Name=tag:Name,Values=$vpcName" | jq -r '.Vpcs[].VpcId' )
         [ -z "$vpcId" ] && { echo "ERROR No VPC Name=$vpcName in $(aws config get region)" >&2; return 1; }
         [ $(echo "$vpc-id" | wc -l ) != 1 ] && {
               echo "ERROR Check for more than one VPCs Name=$vpcName in $(aws config get region)" >&2; return 1; }
         # look for all VPCs that are tagged as VpcType=hub , by an admin, for example:
         # aws ec2 create-tags --resource vpc-cd1ad7a8 --tags Key=VpcType,Value=hub
         for  hub in $(aws ec2 describe-vpcs --f "Name=tag:VpcType,Values=hub" | jq -r '.Vpcs[]| .VpcId + ":" + '"${qTagName}"); do
            echo "Peering VPC $vpcName <=> $hub w/Tag:VpcType==hub" >&2
            pcxId=$(PeerVpc2Hub $vpcName  ${hub/:*/}) || continue
            # set  Project tags to the CIDATA Project
            aws ec2 create-tags --resources ${pcxId} --tags Key=Project,Value="$(jq -r .Project $CIDATA)"
            aws ec2 create-tags --resources ${pcxId} --tags Key=Name,Value="$(jq -r .Project $CIDATA).${hub/*:/}"
            echo "Installing Routes to Peer VPC $vpcName <=> $hub" >&2
            # peerVpcRoute ${pcxId} ; # YTBD this would be a simpler implimentation, since we have the pcx-id
            PeerVpcRoutes $vpcName  ${hub/:*/}
         done
         for port in 80 8080 8009 8443 ; do add_hub_sg_ingress web app $port; done
       ;;
     delete_vpc )
        # vpcName=$(jq -r .VpcName ${CIDATA:-/dev/null})
        # vpcId=$(aws ec2 describe-vpcs --f "Name=tag:Name,Values=$vpcName" | jq -r '.Vpcs[].VpcId' )
        [ "${OK_TO_DELETE_VPC^^}" != TRUE ] && { echo VPC remains, Select OK_TO_DELETE_VPC, or export as true; return 0; }
        local q='.Reservations[].Instances[] | { "Id": .InstanceId, "Name": .Tags[] | select(.Key=="Name").Value}'
        json=$(aws ec2 describe-instances --f Name=vpc-id,Values=$(getVpcId)) ; showInst "$json"
        json=$(echo $json | jq "$q") 
        [ $(echo $json | jq  'select(.Name!="NAT")' | jq -s length) -gt 0 ] && {
              echo Not deleting VPC due to  un-terminated instances >&2;
              return 1;
        }
        delete_vpc_peering $myVpc || return 1
        echo terminating NAT and delete_vpc $myVpc >&2
        [ $(echo $json | jq  'select(.Name=="NAT")' | jq -s length) -gt 0 ] && { terminate_instance NAT;  sleep 5; }
        delete_vpc $myVpc  || { echo Waiting, before retry; sleep 20; delete_vpc $myVpc  || let rv++; }
        ;;
     *generate_ciData )  generate_ciData ${CIDATA##*/}
        ;;
     *generate_ciJob ) 
            generate_ciJob
        ;;
     security | security_revoke )
           local qSgName2Id json n cmd vpcId; vpcId=$(getVpcId) 
           # revoke old rules that allowed ingress from other SGs
           json=$(aws ec2 describe-security-groups --f Name=vpc-id,Values=$vpcId)
           qSgName2Id='.SecurityGroups[] | select(.GroupName==$n) | .GroupId'
           [ ${subCmd##*_} == revoke ] && for n in $(jq -r '.Security.SGinBound | to_entries | .[].key' $CIDATA); do 
              sgId=$(echo $json | jq -r --arg n $n "$qSgName2Id")
              cmd="revoke_vpc_sg_inBound_rules $vpcId $sgId"
              echo "$cmd ; # ($n)" 
              $cmd "$json" || let rv++
           done
           # add new or re-add old SG rules
           #for n in $(jq -r '.Security.SGinBound | to_entries | .[].key' $CIDATA); do 
           #   cmd="add_sg_rules $vpcId $n" 
           #   $cmd || let rv++
           #done
           add_sg $vpcId $(jq -r '.Security.SGinBound | to_entries | .[].key' $CIDATA) || rv++
           # Cannot update_vpc_policy without more privileges, queue the task via changeRequest().
            
          ;;
## Deprecate the get_ciData, this should be done external to ciStack.
##     *get_ciData )
##         local dir url
##         dir=$WORKSPACE/ciData
##         [ -n "${2}" ] && CIDATA_SOURCE="${2%/}"
##         CIDATA_SOURCE=${CIDATA_SOURCE:-https://svn.nps.edu/repos/metocgis/infrastructure/branches/djones/ciData}
##         [ OK != "${CIDATA_SOURCE/*ciData/OK}" ] && { echo ${FUNCNAME[0]} CIDATA_SOURCE is not OK; return 1; }
##         [ -d $dir ] && { 
##               url=$(cd $dir && svn info | grep ^URL: ) && {
##                   url=${url/URL: /}
##                   [ "$url" != "$CIDATA_SOURCE" ] && { mv $dir $dir.$(date +%s); url=""; }
##               }
##               # Do an update of the same source 
##               [ -n "$url" ] && { 
##                    echo   Updating CIDATA from ${url} >&2
##                   (cd $dir; svn update) ; 
##                   return $?;
##               }
##         }
##         echo  svn co ${CIDATA_SOURCE} >&2
##         (cd "$WORKSPACE" && svn co ${CIDATA_SOURCE} ) || return 1
##      ;;
     s3Store ) 
         update_s3Store || echo Warning failed to update bucket.
      ;;
     *  )  
          echo $usage >&2; # echo help YTBD.... ; 
          [ X = "$mask" ] && printf  "$CIDATA is missing.\n Use: generate_ciDAta ${CIDATA##*/}\n" >&2
          [ XX = "$mask" ] && printf "VPC is required.\n Use:  create_vpc\n" >&2
          [ -n "$mask" ] && echo mask=\"$mask\"
          return 1
         ;;
    esac
    [ $rv != 0 ] && [ -n "$JOB_NAME" ] && { echo "aws configure list"; echo "$(aws configure list)"; }
    return $rv
}

###
# Show VM Instances in a project VPC. By default, only those in the VPC in CIDATA (project.json).
#
showInst() {
   local hdr json="$1" q format cols 
   [ ${#json} -lt 40 ] && json=$(get_instances all)
   format="%-11.11s %-20.20s %-8.8s %-8.8s %14.14s %-12.12s %-14.14s %-12.16s %s %s"
   hdr="#Name InstanceId State InstanceType Placement-AZ VpcId IAM-Profile PrivateIP PublicIP Project"
   # query Tags for a Name
   q='.Reservations[].Instances[] | '
   [ "$1" ==  "?" ] && { echo $json | jq -r '.Reservations[0].Instances[0]|keys'; return 0; }
   [ $# -gt 1 ] && {
     hdr="#Name InstanceId Project "
     q+="[ ${qTagName}, .InstanceId, ${qTagProject} "
     format="%-11.11s %-20.20s %-8.8s" 
     while shift; do  [ -z "$1" ] && continue; hdr+=" $1"; q+=", .$1"; format+=" %s" ; done
     q+=" ]"
   } || {
     format="%-11.11s %-20.20s %-8.8s %-8.8s %14.14s %-12.12s %-14.14s %-12.16s %s %s"
     hdr="#Name InstanceId State InstanceType Placement-AZ VpcId IAM-Profile PrivateIP PublicIP Project"
     q+="[ ${qTagName}, .InstanceId, .State.Name, .InstanceType, .Placement.AvailabilityZone, .VpcId, .IamInstanceProfile.Arn, .PrivateIpAddress, .PublicIpAddress, ${qTagProject} ]"
   }
   printf "$format" $hdr; echo
   echo $json | jq  -c -r "$q" | sed -e 's/^\[//' -e 's/]$//' -e 's/,/\t/g' -e 's/"//g' -e 's/arn\:.*instance-profile.//' | \
    while read line; do printf "$format" $line; echo; done
}
complete -F _lsvm showInst 

#
showVol() { 
      local vols json format input hdr xq q msg; json="$1" 
      vols=$(aws ec2 describe-volumes)
      [ ${#json} == 0 ] && json=$(get_instances all)
      # Json transforms
      #   -add  .att and .volName elements, to that of describe-volumes output
      xvols=$(echo $vols | jq ".Volumes[] | . + {  att : .Attachments[], volName : (${qTagName}), Project : (${qTagProject}) }" | jq -s . )
      # Transform describe-instances json into a map from instanceId to instance Name, the "names" object.
      names=$(echo $json | jq ".Reservations[].Instances[] | { (.InstanceId) : (${qTagName}) }" | jq -s . | jq add)
      # combine the content of the "xvols" and "names" shell variables, to construct one json stream as follows:
      # {"vols" : [ ... ], "names": { "i-94a2c9b0": "aws_acaf1", "i-e2a3c8c6": "Bastion }}
      # The expression '.name as $names | ...' is a jq-style variable assignment of "$name", used down the pipe to add instName to each vol object.
      q='.names as $names | .vols[] | . + { instName : $names[(.att.InstanceId)] }'
      input=$(echo "{ \"vols\" : $xvols , \"names\" : $names }" | jq "$q")
      q='"\(.instName) \(.VolumeId) \(.att.Device) \(.Size)G \(.VolumeType) \(.State) \(.Iops)-Iops \(.Project) \(.volName)"' 
      [ X$DEBUG == Xinput ] && {
        xq='.names as $names | .vols[] | {VolumeId, Instance : .att.InstanceId, Name : $names[(.att.InstanceId)]}'
        echo $input | jq -c "$xq" ; 
        echo instances: $(echo $json | jq '.Reservations[].Instances[].InstanceId' | wc -l)
        echo volumes: $(echo $vols | jq '.Volumes[].VolumeId' | wc -l)
        echo Attached Volumes  $(echo $xvols | jq '.[].VolumeId' | wc -l)
        echo instances with Name  $(echo $names | jq '.[]' | wc -l)
        echo $input | jq -r "$q" 
      }
      format="%-10.10s %-20.22s %-14.14s %8.8s %-8.8s %6.6s %10.10s %s %s\n"
      hdr="#VM Vol Device Size-GB Type State IOPS Project volName"
      printf "$format" $hdr
      # Show volumes that are attached to a VM instance
      echo $input | jq -r "select(.instName) | $q" | while read line; do printf "$format" $line; done 
      msg=$(echo $input | jq  'select(.instName) | .Size' | jq -s -r '"# Total: \(add)G, in \(length) attached volumes."')
      msg+=$(echo $vols | jq -r '[.Volumes[].Size] | ", Account Summary: \(length) Volumes, \(add) G"')
      echo "$msg"
      # Show volumes that are not attached.
      q='.Volumes[] | select((.Attachments | length) == 0) '
      [ $(echo $vols | jq "$q | .Size" | jq -s length) == 0 ] && return 0
      msg=$(echo $vols | jq "$q | .Size" | jq -s -r '"# Total: \(add)G, in \(length) unattached volumes."')
      q+='| "UnAttached \(.VolumeId) None \(.Size)G \(.VolumeType) \(.State) \(.Iops)-Iops \('${qTagProject}') \('${qTagName}')"' 
      printf "$format" $hdr; echo $vols | jq -r "$q" | while read line; do printf "$format" $line; done 
      echo "$msg"
}

###
# show all the type of resources (vm, vol, hosts, bastions) under an account, for all projects VPCs.
#
lsvm() { showInst "$(aws ec2 describe-instances)" $@; }
lsvol() { showVol "$(aws ec2 describe-instances)"; }
lshosts() { echo '#START_AWS_ALL'; getHostsEnt "$(aws ec2 describe-instances)"; echo '#END_AWS_ALL'; }
lsbastions() { lshosts | grep xbas | sed 's/xbas.*\.//'; }

### 
# Command completion function for lsvm.
#
_lsvm() {
  local cur prev cache=$HOME/.cache/aws ; local keys=$cache/instance_keys
  [ ! -d $cache ] && { mkdir -p $cache; }
  [ ! -f $keys ] && { aws ec2 describe-instances | jq -r '.Reservations[].Instances[]|keys|.[]'| sort -u > $keys; }
  cur=${COMP_WORDS[COMP_CWORD]}
  prev=${COMP_WORDS[COMP_CWORD-1]}
  [ -z "$WORKSPACE" ] && echo ERROR WORKSPACE must be set, for example: export WORKSPACE=\$HOME/ws
  case ${COMP_CWORD} in
    # nolonger any help, just keys
    # 1) COMPREPLY=( $(compgen -W "help $(cat $keys)"  -- $cur) ) ;;
    *) COMPREPLY=( $(compgen -W "$(cat $keys)" -- $cur) ) ;;
  esac
  return 0
}
complete -F _lsvm lsvm 

### 
# Command completion helper function for various ec2 describe-RESOURCEs.
#
alias foo="_ec2Res vpc"
_ec2Res() {
  local res=${1}
  local cur prev cache=$HOME/.cache/aws ; local keys=$cache/${res}_keys
  [ ! -d $cache ] && { mkdir -p $cache; }
  [ ! -f $keys ] && { aws ec2 describe-instances | jq -r '.Reservations[].Instances[]|keys|.[]'| sort -u > $keys; }
  cur=${COMP_WORDS[COMP_CWORD]}
  prev=${COMP_WORDS[COMP_CWORD-1]}
  [ -z "$WORKSPACE" ] && echo ERROR WORKSPACE must be set, for example: export WORKSPACE=\$HOME/ws
  case ${COMP_CWORD} in
    # nolonger any help, just keys
    # 1) COMPREPLY=( $(compgen -W "help $(cat $keys)"  -- $cur) ) ;;
    *) COMPREPLY=( $(compgen -W "$(cat $keys)" -- $cur) ) ;;
  esac
  return 0
}

###
#  Helper function for policy management.
get_vpc_policy() {
     local q role json vpcId policyName desc arn policy cmd n
     role=$(vpc_ec2_roles) || return 1
     policy=$WORKSPACE/$role.policy.json  
     vpcId=$(getVpcId) || return 1
     policyName=CI-$vpcId
     q='.Policies[] | select(.PolicyName==$n)'
     json=$(aws iam list-policies | jq -r --arg n "${policyName}" "$q" ) 
     arn=$(echo "$json" | jq -r .Arn); [ OK != "${arn/arn:aws*policy*/OK}" ] && return 1
     n=$(echo $json | jq -r .DefaultVersionId)
     aws iam get-policy-version --policy-arn $arn --version-id $n  | jq .
}

### 
# Experiment, for making /etc/hosts-like  entires as follows:
# publicIp  xtagname.proj xtagName xtagN
# privateIp  tagname.proj  tagName  tagN
#
getHostsEnt() {
   local json="$1" Q q 
   [ ${#json} == 0 ] && json=$(get_instances all)
   q='.Reservations[].Instances[] | '
   q+="{ Name : ${qTagName},  Profile : .IamInstanceProfile.Arn, PrivateIpAddress, PublicIpAddress}"
   Q=' select(.PublicIpAddress) | "\(.PublicIpAddress) \(.Name) \(.Profile) \(.Name) \(.Name)"'
   echo $json | jq  -r "$q | $Q " |  sed  -e 's/arn\:.*instance-profile.//' -e 's/CI-vpc-//' -e 's/-ro//' | \
     while read line; do printf "%-16.16s x%s.%4.4s x%s x%4.4s" ${line,,}; echo; done
   Q='  "\(.PrivateIpAddress) \(.Name) \(.Profile) \(.Name) \(.Name)"'
   echo $json | jq  -r "$q | $Q " |  sed  -e 's/arn\:.*instance-profile.//' -e 's/CI-vpc-//' -e 's/-ro//' | \
     while read line; do printf "%-16.16s %s.%4.4s %s %4.4s" ${line,,}; echo; done
}

###
# Resize and aws instance. The instance (if running) will be stopped, resized and started. 
# 1. if needed stop it,  aws ec2 stop-instances --instance-id $1
# 2. run: aws ec2 modify-instance-attribute --instance-id $1 --instance-type Value=$2"
#
reSizeInstance() {
  local usage="Usage ${FUNCNAME[0]} InstanceId InstanceType {optional_json}"
  [ -z "$2" ] && { echo $usage >&2; return 1; }
  local state run=FALSE cmd iId="$1" newType="$2" json="$3"
  [ -z "$json" ] && json=$(aws ec2 describe-instances --instance-ids ${iId}) || return 1;
  json=$(echo $json | jq --arg i ${iId} '.Reservations[].Instances[] | select(.InstanceId == $i)')
  [ "$(echo $json |jq -r .InstanceType)" == "${newType}" ] && return 0
  state=$(echo $json | jq -r '.State.Name')
  [ "$state" ==  running ] && { run=TRUE; 
     cmd="aws ec2 stop-instances --instance-id ${iId}" ; 
     echo $cmd >&2; $cmd || return 1;
  }
  local -i try=0; while [ "$state" !=  stopped ]; do
     let try++; echo waiting $((try *10)) seconds for instance to stop >&2; sleep $((try * 10))
     state=$(aws ec2 describe-instances --instance-ids ${iId} | jq -r '.Reservations[].Instances[].State.Name')
     [ $try -le 5 ] && continue
     echo ${FUNCTION[0]} timeout ERROR waiting for instance ${iId} to stop.; return 1;
  done
  cmd="aws ec2 modify-instance-attribute --instance-id ${iId} --instance-type Value=${newType}"
  echo $cmd >&2; $cmd || return 1
  [ $run ==  TRUE ] && {
     cmd="aws ec2 start-instances --instance-id ${iId}" ; 
     echo $cmd >&2; $cmd || return 1;
   }
}

###
# This is a very simple scheduler, to curtail running idle AWS resources outside non-business hours.
# The "schedule" function should be run by Cron or Jenkins.
# The instances with a Schedule tag are effected. Schedule value of "None", will be ignored.
# e.g.:
# 
#     $ setSchedule i-60046f44 None ; # this node or nodes w/o a Schedule tag are not changed.
#     $ setSchedule i-73a1ca57 6-18:1-5:PST8PDT
#     $ setSchedule i-91a1cab5   "18::PST8PDT"
#     $ showSchedule 
#     #Name       InstanceId  State InstanceTy           Schedule 
#     el6-06      i-91a1cab5  stopped t2.micro          18::PST8PDT ; # stop after 6pm
#     web-el6     i-4d117b69  running c3.2xlarge   6-18:1-5:PST8PDT ; # start at 6AM, stop after 6pm
#     el7-07      i-73a1ca57  stopped t2.micro     6-18:1-5:PST8PDT
#     $ schedule
#     schedule InstanceId i-73a1ca57, is stopped outside the Scheduled time 6-18:1-5:PST8PDT
#     aws ec2 start-instances --instance-id i-73a1ca57
#     ...
# 
setSchedule() { 
  # Schedule value is a  "running" time slot in "{hours}:{days}:{TZ}"
  # hours (start-stop), days (1-7) where 1 is Monday, TZ specifies timezone.
    local usage="example Usage: ${FUNCNAME[0]} \${instanceId} \"6-18:1-5:PST8PDT\" ; # start at 6AM, stop at 1800, M-F";
    [ $# != 2 ] && { 
        echo $usage 1>&2;
        return 1
    };
    aws ec2 create-tags --resources $1 --tags Key=Schedule,Value="$2"
}

###
# This is a helper for simple scheduler experiment. Does what the name says.
#
showSchedule() { 
    local hdr json="$1" q format="%-11.11s %-11.11s %-5.8s %-10.10s %18.18s %-12.12s %-14.14s %-12.16s %s";
    [ ${#json} == 0 ] && json=$(get_instances all);
    q='.Reservations[].Instances[] | ';
    q+="[ ${qTagName}, .InstanceId, .State.Name, .InstanceType, ${qSchedule}, .VpcId, .IamInstanceProfile.Arn, .PrivateIpAddress, .StateTransitionReason]";
    hdr="#Name InstanceId State InstanceType Schedule VpcId IAM-Profile PrivateIP StateTransitionReason";
    printf "$format" $hdr;
    echo;
    echo $json | jq -c -r "$q" | sed -e 's/^\[//' -e 's/]$//' -e 's/,/\t/g' -e 's/"//g' -e 's/arn\:.*instance-profile.//' | while read line; do
        printf "$format" $line;
        echo;
    done
}

###
# The cron function for Simple scheduler experiment.
#
schedule() { 
    local instranceId hours days timezone q running stopped json="$1";
    local -i rv=0;
    [ ${#json} == 0 ] && json=$(get_instances all);
    q='.Reservations[].Instances[] | ';
    q+="{ Name : (${qTagName}), InstanceId, state :(.State.Name), Schedule : (${qSchedule}) }";
    running=$(echo $json | jq "$q" | jq 'select(.state == "running") | select(.Schedule!="None")');
    stopped=$(echo $json | jq "$q" | jq 'select(.state == "stopped") | select(.Schedule!="None")');
    echo $running | jq -r '"\(.InstanceId) \(.Schedule)"' | while read id sched; do
        IFS=:; set -- $sched; unset IFS; hours=$1; days=$2; timezone=$3;
        inRange $(TZ=$timezone date +%u) "$days" && inRange $(TZ=$timezone date +%H) $hours && continue;
        msg="${FUNCNAME[0]} InstanceId $id, is running outside the Scheduled time $sched";
        cmd="aws ec2 stop-instances --instance-id $id";
        echo $msg;
        echo $cmd;
        $cmd || let rv++;
    done;
    echo $stopped | jq -r '"\(.InstanceId) \(.Schedule)"' | while read id sched; do
        IFS=:; set -- $sched; unset IFS; hours=$1; days=$2; timezone=$3;
        [ -n "${hours/*-*/}" ] && continue;
        inRange $(TZ=$timezone date +%u) "$days" && inRange $(TZ=$timezone date +%H) $hours && { 
            msg="${FUNCNAME[0]} InstanceId $id, is stopped outside the Scheduled time $sched";
            cmd="aws ec2 start-instances --instance-id $id";
            echo $msg;
            echo $cmd;
            $cmd || let rv++
        };
    done;
    return $rv
}

###
# Generate newJob.xml file,  for a Jenkins project. 
# - Use templates/job.xml.erb and ${CIDATA}.
# - Writes a new Job.xml file  to stdout.
#
#
generate_ciJob() {
        # use templates/${2}.xml.erb to create job.xml
         #echo "${FUNCNAME[0]} $CIDATA $(dirname ${CIDATA})/templates/job.xml.erb > newJob.xml"
         templateJsonData $CIDATA $(dirname ${CIDATA})/templates/job.xml.erb
}

###
# Generate a new project ciData file 
# - Use templates/schema_${SCHEMA_CIDATA}.json
# - Filter leading AWS_, or trailing .json from JOB_NAME (or $1), to make Project name.
#
generate_ciData() {
  local name=${1:-$JOB_NAME} fileName url vcs
  local usage="Usage ${FUNCNAME[0]} NewProcjectName "
  local fileName=${name%.json}.json; name="${name#AWS_}"; name=${name%.json}
  [ ! -d "${WORKSPACE}"  ] && { ${FUNCNAME[0]} ERROR WORKSPACE is not available.; return 1; }
  export CIDATA=${WORKSPACE}/ciData/$fileName
  [ -f $CIDATA ] && { echo CIDATA already exists: $CIDATA; ciStack_schema_test ; return $? ; }
  [ -z "$name" ] && { echo $usage >&2; return 1; }
  template=${CIDATA%/*}/templates/Schema_${SCHEMA_CIDATA}.json
  [ ! -f $template ] && { echo ERROR ${FUNCNAME[0]} No template found: $template >&2; return 1; }
  jq . $template >/dev/null || { echo ${FUNCNAME[0]} template json ERROR : $template >&2; return 1; }
  new=$(jq -n --arg n "$name" '{ "VpcName": $n, "Project" : $n, "VpcId": "" }')
  # restrictions on bucket names in some regions only allow: lower-case, numbers, dot, and dash
  bname=$(echo "${name,,}" | sed -e 's/^aws_//' -e 's/[^.a-z0-9]/-/g')
  echo "$(cat $template | sed -e "s/VPCNAME/$name/" -e "s/PROJECT/$name/" -e "s/S3PROJ/$bname/") $new" | jq -s '. | add' > $CIDATA

  # profile names
  #ob=.cidata.ec2.associateAddress; 
  ## Is the Version Control System  subversion or git ?
  #url=$(svn info ${CIDATA%/*} | awk '/^URL:/{print $2}') && vcs=svn
  #case $vcs in 
  #  svn )
  #    (cd ${CIDATA%/*} && svn add ${CIDATA##*/} && svn propset svn:keywords "HeadURL ID" ${CIDATA##*/} )
  #    json=$(jq . $CIDATA)
  #    json+=$( jq -n --arg url "$url}" '{ CIDATA_SCM : $url }')
  #    echo $json |  jq -s '.[0] + .[1]' > $CIDATA
  #    ;;
  #  git ) echo ERROR git VCS setup is yet to be done  && return 1 ;;
  #  * ) echo ERROR no Version Control found on CIDATA: $CIDATA && return 1 ;;
  #esac
  # move generate_buckets to the create_vpc stage
  ciStack_schema_test
}

###
# Render JSON data into an ERB template.
#
#      templateJsonData $CIDATA NAME.conf.erb > NAME.conf
#
templateJsonData() {
  [ $# != 2 ] && { echo Usage ${FUNCNAME[0]} dataFile.json templateFile.erb; return 1; }
  ruby -e '
     require "rubygems";
     require "json";
     require "erb";
     data = JSON.parse(File.read(ARGV[0]))
     puts ERB.new(File.read(ARGV[1]), nil, "-").result(binding)
     ' $@
}

#
# --------
#
# # Internal Functions

###
# Run a minimal content check on ciData.
#
ciStack_schema_test() {
   local usage=${FUNCNAME}; # reads file named in $CIDATA
   local name json keys file=${1:-$CIDATA}
   local -i rv=0
   # if no file, that is OK too, assuming the caller goes on to generate it.
   [ ! -f "$file" ] && { return 0; }
   # Ask that user to revert ciData if there is an update conflict, or fails to parse
   jq . $file >/dev/null 2>&1 || { 
           jq . $file 
           printf "${FUNCNAME[0]}: incorrect JSON encoding: ${file}"  
           return 1
    }
    [ "$(jq .Project $file)" == null ] && {
       name=$(jq .Name $file)
       [ $name == null ] && { echo ERROR missing Project name object in file; return 1; }
       json="    \"Project\": $name,"
       let rv++
       printf  "${FUNCNAME[0]}: ERROR:$rv The following is requred in: $file\n   $json\n"
    }
    [ $(jq -r .Schema $file) != "$SCHEMA_CIDATA" ] && {
       let rv++
       printf  "${FUNCNAME[0]}: ERROR:$rv migration to a new .Schema is required of: $file\n"
    }
    local default=$WORKSPACE/ciData/ciStack.json
    # essentially keys=$(jq -r 'keys|.[]' $default)
    keys="CIDATA_SCM CITOOLS_SCM Components Description DevMappingTemplateFile EIPs InstanceRoles MapVolumes Profiles Project ReleaseGroup RuncmdFile SCM_prefix Schema ScmHeadURL ScmId Security UserDataTemplateFile UsersFile Version Volumes VpcId VpcName s3ProjectStore s3Store s3Store_SCM s3SysStore"

    for name in $keys ; do [ "$(jq  .$name $file)" == null ] && {
       let rv++
       printf  "${FUNCNAME[0]}: ERROR:$rv \$file requires $name key, for example:\n"
       [ -f "$default" ] && printf  "$(jq -c {$name} $default)\n"
      }
    done
    return $rv
}

###
# changeLog writes to stdout, adds or appends to a changelog object. The Caller must save to file.
#
changeLog() {
    local usage="${FUNCNAME[0]} path_to_CIDATA followed by any strings you want logged in the entry > CIDATA.new"
    local logFile=$1 ; shift
    local json changeList now=$(date +%s)
    local newEntry='{ "ChangeLog" : [ { "date": $n, "msg": $m } ] }'
    local newEntry='[{ "date": $n, "msg": $m }]'
    [ ! -f "$logFile" ] && { echo ${FUNCNAME[0]} ERROR No such file: \"$log\"; return 1; }
    json=$(jq . "$logFile") || { echo ${FUNCNAME[0]} ERROR in JSON encoding of file: \"$log\"; return 1; }
    changeList=$(echo $json | jq .ChangeLog)
    # innitialize the list, if needed 
    [ "$changeList" == null ] &&  changeList=$(jq -n --arg n $now --arg m Initial  "$newEntry")
    # add the new entry to the list
    changeList=$( (echo "$changeList"; jq -n --arg m "${BUILD_TAG:-$USER} $*" --arg n $now  "$newEntry") | jq -s add)
    # merge the new list into the log file
    ( echo "$json" "{\"ChangeLog\" : $changeList }" | jq -s add )
}

### 
# Command completion function for ciStack.
#
_ciStack() {
  local cur prev files
  cur=${COMP_WORDS[COMP_CWORD]}
  prev=${COMP_WORDS[COMP_CWORD-1]}
  [ -z "$WORKSPACE" ] && echo ERROR WORKSPACE must be set, for example: export WORKSPACE=\$HOME/ws
  case ${COMP_CWORD} in
    1) COMPREPLY=( $(compgen -W "help show launch stop start run terminate delete_vpc create_vpc generate_ciData security generate_ciJob tag s3Store peer_vpc" -- $cur) ) ;;
    2) case $prev in 
          generate_ciData ) files=$(cd $WORKSPACE/ciData/templates && ls *.json.erb) ;;
          generate_ciJob ) files=$(cd $WORKSPACE/ciData/templates && ls *.xml.erb) ;;
          * ) files=$(cd $WORKSPACE/ciData && ls *.json) ;;
        esac
        COMPREPLY=( $(compgen -W "$files" -- $cur) ) ;;
  esac
  return 0
}
complete -F _ciStack ciStack 

##export qTagName='((.Tags // [{Key:"Name", Value: "None"}]) | .[]|select(.Key=="Name").Value)'
export qTagName='(.Tags // [] | .[]|(select(.Key=="Name").Value) ) // "None"';
export qTagProject='(.Tags // [] | .[]|(select(.Key=="Project").Value) ) // "None"';
export qSchedule='(.Tags // [] | .[]|(select(.Key=="Schedule").Value) ) // "None"';

### #
# This function is showing how the jq filter works under different conditions, with instance tags.
#  It is also a reminder of how touchy the qTagName filter is.
#
testqTagName() {
  local  q 
    q='((.Tags // [{Key:"Name", Value: "None1"}]) | .[]|(select(.Key=="Name").Value) // "None2") // "None3"';
    q='((.Tags // [{Key:"Name", Value: "None1"}]) | .[]|(select(.Key=="Name").Value) ) // "None3"';
    q='(.Tags | .[]|(select(.Key=="Name").Value) ) // "None3"';
    # None of the above work in all test cases.
    q='(.Tags // [] | .[]|(select(.Key=="Name").Value) ) // "None"';
  echo  expect myName
  echo '{ "Tags": [ { "Value": "myName", "Key": "Name" } ] }' | jq "${q}"
  echo   no Key==Name, expect None
  echo '{ "Tags": [ { "Value": "noname", "Key": "xxName" } ] }' | jq "${q}"
  echo  empty list check, expect None
  echo '{ "Tags": [] }' | jq "${q}"
  echo  missing list check : expect None
  echo '{ "foo": [] }' | jq "${q}"
  echo  Just myName, testing more than one Key in the list
  echo '{ "Tags": [ { "Value": "myName", "Key": "Name" }, { "Key" : "foo", "Value" : "bar" } ] }' | jq "${q}"
}



###
# Create tags on instances listed in given json, if not given json, all in  project vpc.
#  Example Usage :
#
#      json=$(aws ec2 describe-instance | jq $myfilter)
#      tagProjectInstances key value option_json
#
tagProjectInstances() {
   local json="$3" key=$1 value=$2 iId q
   [ -z "$json" ] && json=$(get_instances all)
   [ -z "$value" ] && { echo Usage: ${FUNCNAME[0]} KeyName Value {optional-Json}; return 1; }
   local -i rv=0
   q='.Reservations[].Instances[] | .InstanceId'
   [ -z "$value" ] && return 1
   for iId in $(echo $json | jq -r "$q"); do
     echo aws ec2 create-tags --resources $iId --tags Key=$key,Value=$value 
     aws ec2 create-tags --resources $iId --tags Key=$key,Value=$value || rv+=1
   done
   return $rv
}

###
# Create tags on volumes attached to instances listed in given json, if not given json, all in project vpc.
#  Example Usage :
#
#      json=$(aws ec2 describe-instance | jq $myfilter)
#      tagProjectVolumes key value option_json
#      
## tagProjectInstances Project $(jq -r .Project $CIDATA)
## tagProjectVolumes Project $(jq -r .Project $CIDATA)
#
tagProjectVolumes() {
   local json="$3" key=$1 value=$2 iId q
   [ -z "$value" ] && { echo Usage: ${FUNCNAME[0]} KeyName Value {optional-Json}; return 1; }
   [ -z "$json" ] && json=$(get_instances all)
   local -i rv=0
   q='.Reservations[].Instances[] | .BlockDeviceMappings[].Ebs.VolumeId'
   [ -z "$value" ] && return 1
   for iId in $(echo $json | jq -r "$q"); do
     echo aws ec2 create-tags --resources $iId --tags Key=$key,Value=$value 
     aws ec2 create-tags --resources $iId --tags Key=$key,Value=$value || rv+=1
   done
   return $rv
}


### 
# Get the project VPC id.
# CIDATA contains the name of the AWS VPC that the project lives in.
#
getVpcId() {
   local vpcId vpcName
   vpcId=$(jq -r .VpcId $CIDATA) 
   [ "$vpcId" == null ]  &&  { echo ERROR: No VpcId in $CIDATA,  >&2 ; sleep 600; return 1; }
   [ vpc-OK != "${vpcId/-+([[:xdigit:]])/-OK}" ] && { echo ERROR Invalid VpcId in $CIDATA. ; return 1; }
   echo $vpcId
}
###
# Check that the VPC named in CIDATA, exists. If needed, update the cached vpcId in CIDATA.
#
export CHECK_VPC_JSON
check_vpc() {
       CHECH_VPC_JSON=""
       [ -z "$CIDATA" ] &&  [ ! -r "$CIDATA" ] && { echo ERROR: No CIDATA \"$CIDATA\" >&2; return 1; }
       local vpcName vpcId
       vpcName=$(jq -r '.VpcName' $CIDATA) || return 1
       [ "$vpcName" == null ] &&  { echo ERROR: No VpcName in $CIDATA >&2 ; return 1; }
       json=$(aws ec2 describe-vpcs --f "Name=tag:Name,Values=${vpcName}") || return 1
       vpcId=$(echo $json | jq -r '.Vpcs[].VpcId')
       [ vpc-OK != "${vpcId/-+([[:xdigit:]])/-OK}" ] && { echo VPC does not exits: $vpcName. >&2; return 1; }
       # Check that the CIDATA is in sync
       [ "$(jq -r .VpcId $CIDATA)" != "$vpcId" ] &&  updateCiDataKeyValue VpcId $vpcId
       [ "$(getVpcId)" != "$vpcId" ] && { 
            echo VpcId in CIDATA is incorrect >&2; 
            echo VpcId should be \"$vpcId\"  in $CIDATA >&2; 
            return 1 
       }
       CHECK_VPC_JSON="$json"
       echo $vpcId
}


###
# Helper function to find instances by CIDATA's vpcId and given list of Name, or a keyword.
# Name could be a keyword: "ALL" or "None"
get_instances() {
   local vpcId name subnet sg json q id foo sep collection ;
   [ ! -r "$CIDATA" ] && { echo ${FUNCNAME[0]} No CIDATA >&2 ; return 1; }
   [ $# == 0 ] && { echo Useage: ${FUNCNAME[0]} NAME >&2 ; return 1; }
   vpcId=$(getVpcId) || return 1
   [ vpc-OK != "${vpcId/-+([[:xdigit:]])/-OK}" ] && { echo bad vpcId >&2; return 1; }
   json=$(aws ec2 describe-instances --f Name=vpc-id,Values=$vpcId) || return 1 ;
   q='.Reservations[].Instances[] | select( .Tags // []| .[] | select(.Key=="Name").Value==$n)'
   sep=""; collection=""
   for name in $@; do
     case ${name^^} in 
        NONE ) jq -n '{ Reservations:[ { Instances: []} ] }' ; return 0 ;;
        ALL  ) echo "$json"; return 0 ;;
        \#  ) break ;;
         * )  
             foo=$(echo $json | jq --arg n $name "$q")
             [ -z "$foo" ] && continue 
             collection+="$sep$foo"; sep=", "
           ;;
     esac  
   done  
   # this is destroying the reservation info 
   echo "[ $collection ]" | jq '{ Reservations:[ { Instances: . } ]}' 
   return 0
}
### 
# Returns valid name or name-list for either instances in the project VPC, or roles from CIDATA.
# Given  a list of names, roles, or a keyword-filter. 
# Names should be represented as InstanceRoles in CIDATA, although this is not enforced.
# Instances must be tagged with a __Name__ key, with the tag value being an enumeration of the instance role name.
# {RoleName}-0 being the first launch. Additional launches of the same role will query the used Names, 
#  and enumerate with a unique number. The default (in the launch function) is to pick the next higher number.
## getInstanceNames all ; # all the roles in ciData
## getInstanceNames roles ; # all the roles in ciData
## getInstanceNames inVpc ; #=> all current instances in the VPC-id given by ciData
## getInstanceNames select; #=> select an instance from the VPC to operate on
## getInstanceNames selectRole;  #=> select a role to launch
## getInstanceNames foobar-01; #=> return given name if it is inVpc
## getInstanceNames foobar;  #=> return given name if it is a Role in CiData
getInstanceNames() {
    local rl="" key n allNames allRoles
    [ $# == 0 ] && { echo Usage: ${FUNCNAME[0]} INSTANCE_NAMES >&2; return 1; }
    allRoles=$(jq -r '.InstanceRoles|keys|.[]' $CIDATA) || return 1
    [ -z "$allRoles" ] && { "${FUNCNAME[0]} ERROR: No InstanceRoles are Named in CIDATA: $CIDATA" >&2; return 1; }
    for key in $@; do
      case ${key} in 
         roles|all|ALL ) rl=${allRoles}; break ;;
         selectRole|SelectRole ) 
                 rl=""; PS3="Select > "; select rl in $allRoles ALL; do [ -n "$rl" ] && break; done
                 [ ALL == "${rl^^}" ] && rl=${allRoles}
                 break ;;
         inVpc ) rl=$(get_instances all | jq -r ".Reservations[].Instances[] | $qTagName"); break ;;
         select|SELECT|Select ) 
                 allNames=$(get_instances all | jq -r ".Reservations[].Instances[] | $qTagName")
                 rl=""; PS3="Select > "; select rl in $allNames ALL; do [ -n "$rl" ] && break; done
                 [ ALL == "${rl^^}" ] && rl=${allNames}
                 break ;;
         NONE|none )  rl=""; break ;;
          '#' )  break ;;
          * )
            [ -z "${key/*-+([[:digit:]])/}" ] && { 
              rl+=" "$(get_instances $key | jq -r ".Reservations[].Instances[] | $qTagName"); 
              continue ; 
            }
            for n in  $allRoles; do [ $n == ${key} ] && rl+=" $key" && break; done ;;
       esac
    done
    echo $rl
}

###
# Terminate destroys the VM Instance.
terminate_instance() {
   local id
   id=$(get_instances $1 | jq -r '.Reservations[].Instances[].InstanceId') || return 1
  [ i-OK != "${id/-+([[:xdigit:]])/-OK}" ] && { echo "${FUNCNAME[0]} $1 : None or more than one exists: $id " >&2 ; return 1; }
   echo aws ec2 terminate-instances --instance-ids $id >&2
   aws ec2 terminate-instances --instance-ids $id >&2
}

###
# SSH Instance by tag Name.
#
# SshI supports tab completion, <tab><tab>to show available instance Names or <tab> to complete an Instance Name. 
#
#      $ awsLoad; # or module load aws, for one-time setup of your shell
#      $ sshI <tab><tab>
#      create_vpc   generate_ciData  help     run       security    start   tag
#      Bastion     el6-06      RHEL6     Logger      openldap-0  Repo        
#      nexus-0     el7-07      gitlab-0      NAT         Proxy       
#      $ sshI Bas<tab>
#      $ sshI Bas
#      ssh -A 52.222.34.123
#      Last login: ...edit...
#      
#             __|  __|_  )
#             _|  (     /   Amazon Linux AMI
#            ___|\___|___|
#     
#
sshI() {
   local json ip name=$1
   [ $# -gt 1 ] && { echo Usage: ${FUNCNAME[0]} NAME >&2; return 1; }
   [ $# -eq 0 ] && name=$(getInstanceNames Select)
   json=$(get_instances $name) || return 1
   case $(hostname) in 
      ip-* )
        ip=$(echo $json | jq -r .Reservations[].Instances[].PrivateIpAddress)
        ;;
      * )
        ip=$(echo $json | jq -r .Reservations[].Instances[].PublicIpAddress)
        ;;
   esac
   [ -z "${ip}" ] && { echo ERROR: ${FUNCNAME[0]} could not find IpAddress for $name; return 1; }
   shift
   echo ssh -YA $ip $@ >&2
   ssh -YA $ip $@ 
}

###
# Generate Instance data using "Profiles" and "InstanceRoles" objects.
# This function must query cloud resources, read-only access, no change requests are made.
instanceRoleData() {
   local usage="${FUNCNAME[0]} name_of_Instance_Role {optional_vpcID}"
   local vpcId="$2"  subnet sg json tmp
   local name="$1" json=""  q
   local n sgId snId profileName
   [ -z "$name" ] && { echo $usage; return 1; }
   [ -z "$vpcId" ] && { vpcId=$(getVpcId) || return 1 ; }
   [ Xnull == "X$(jq .Profiles $CIDATA)" ] && {
     echo ${FUNCNAME[0]}: ERROR No Profiles object in CIDATA >&2 ;
     return 1; 
   }
   # Find instance role using the provided name as a key.
   json=$(jq -r --arg n $name '.InstanceRoles[$n]' $CIDATA)
   [ "$json" == null ] && { echo ${FUNCNAME[0]}: ERROR Not found in InstanceRoles: $name >&2 ; return 1; }
   # Look for attributes of either "Profile" (string) or "Profiles" (list of strings) to merge.
   local pl; pl=$(echo $json | jq -r '[ .Profile // "", (.Profiles // [])[] ] | .[]')
   json=$(jq -r --arg n $name '.InstanceRoles[$n]' $CIDATA)
   # Add profile settings into the instance role. The first-in objects take precidence over later (nested) profiles.
   for profileName in $pl default ; do
       tmp=$(jwalkProfile "${profileName}")
       json=$(echo $tmp $json | jq -s add)
   done
   # Find the subnetId that matches the subnet-name in ciData. If null subnet-name, default to "compute".
   subnet=$(echo $json | jq -r '.Subnet // "compute"' ); 
   #snId=$(aws ec2 describe-subnets --f Name=tag:Name,Values=${subnet} Name=vpc-id,Values=$vpcId | jq -r '.[]|.[].SubnetId')
   qSubnet='.[]|.[]|select(.VpcId == $v)|select( $s == ('"${qTagName}"'))|.SubnetId'
   snId=$(awsCache ec2 describe-subnets | jq -r --arg s ${subnet} --arg v $vpcId "$qSubnet")
   [ subnet-OK != "${snId/-+([[:xdigit:]])/-OK}" ] && echo ${FUNCNAME[0]}: ERROR finding $name subnet \"$subnet\" >&2 && return 1
   # Add the SubnetId to the collection of settings for this instance-role.
   json=$(echo $json | jq --arg id $snId '[., {"SubnetId" : $id} ]| add')
   # Add the RoleName this is building data for 
   json=$(echo $json | jq --arg id $name '[., {"InstanceRoleName" : $id} ]| add')
   # Add Security Groups.  Earlier CIDATA had only one (in a string), later CIDATA can use a list (JSON-array).
   q='(.SG // $s) | if (type) == "array" then .[] else . end'
   idList='[]'
   for sg in $(echo $json | jq -r --arg s ${subnet/-*/} "$q"); do
      sgId=$(awsCache ec2 describe-security-groups | jq -r --arg v $vpcId --arg n $sg '.[] |.[] | select(.VpcId == $v)|select(.GroupName==$n)|.GroupId')
      [ sg-OK != "${sgId/-+([[:xdigit:]])/-OK}" ] && echo ${FUNCNAME[0]}: ERROR Could not find $name sgId for \"$sg\".>&2 && return 1
      idList=$(echo $idList | jq --arg s $sgId '.+[$s]')
   done
   # add the SecurityGroupIds.
   json=$(echo $json $idList | jq -s  '[.[0], {"SecurityGroupIds" : .[1]} ]| add')
   echo $json
}

###
# Older versions of ciData used an "Instances" JSON object, now replaced by the use Profiles and instanceRoles objects.
# The older object name was a poor choice, and conflicted with the meaning/purpose, - just confusing.
instanceData() {
   echo "${FUNCNAME[0]} WARNING this function is deprecated, use instanceRoleData. ">&2
   instanceRoleData $@
}

###
# Launch the given Instance-Role-name.
#    
launch_instance() {
   local vpcId name=$1 subnet sg json  RoleName q; local -i i 
   local dataFile instanceJsonFile cmd eip filtered_json arr
   [ $# != 1 ] &&  { echo "Usage: ${FUNCNAME[0]} role-name"; return 1; }
   [[ "$name" =~ " " ]] && { echo "ERROR No spaces allowed in ciData InstanceRole Name: $name" >&2 ; return 1; }
   [[ "$name" =~ "." ]] && { echo "ERROR No periods allowed in ciData InstanceRole Name: $name" >&2 ; return 1; }
   [[ "$name" =~ "-" ]] && { echo "ERROR No dashs allowed in ciData InstanceRole Name: $name" >&2 ; return 1; }
   [ ! -r "$CIDATA" ] && echo ${FUNCNAME[0]} No CIDATA >&2 && return 1
   vpcId=$(getVpcId) || return 1
   [ OK != "${vpcId/vpc-+([[:xdigit:]])/OK}" ] && { echo ${FUNCNAME[0]} $name ERROR no vpcId >&2; return 1; }

   q=".Reservations[].Instances[] | ${qTagName}"
   ## Add a suffix that enumerates instances made from this roleName, into the instance tag Name.
   arr=($(get_instances ALL | jq  -r "$q"  | grep -e "^$name-[0-9]*\$"))
   json=$(instanceRoleData $name $vpcId) || { echo ERROR instanceRoleData >&2 ; return 1; }
   i=0
   # Decide on a suffix, an enum
   case $(echo $json | jq -r .Enum ) in
      # unique number, first available:
      uniq*|first*|low* ) while [[ " ${arr[@]} " =~ " ${name}-$i " ]]; do let i++; done ;;
      # sequential, ever increasing number:
      * ) for n in ${arr[@]}; do [ ${n/*-/} -ge $i ] && { i=${n/*-/}; let i++; }; done ;;
   esac
   RoleName=$name; # Save the the role name, in instance json
   json=$( echo $json | jq --arg n $RoleName '[ ., { "RoleName": $n } ] | add')
   name+="-$i"; # this is our new enumerated name (tag Name), save in instance json.
   # we will add a AmiLaunchIndex to this later 
   json=$(echo $json | jq --arg n ${name} '[., {"Name": $n}] | add')
   #eip=$(getEIP $name); 
   #json=$(echo $json | jq --arg n ${eip} '[., {"eip": $n}] | add')
   # render userData for the instance to a file
   [ ! -d $WORKSPACE/userData ] && { mkdir -p $WORKSPACE/userData || return 1; }
   dataFile=$WORKSPACE/userData/$name.$(date +%s)
   instanceJsonFile=${dataFile}.instance.json
   ## No longer make the "Instance" object, keep it simple, by just a merge of cidata with instanceRoleData.
   # when conflictng objects  - the attribute values in the instanceRole must be kept.
   ## echo "$json $(cat $CIDATA)" | jq  -s '[{ "Instance" :(.[0])}, (.[1])]| add' > $instanceJsonFile
   json=$(echo "$(cat $CIDATA) $json" | jq  -s  add) 
   local entry sz
   # sanitize or delete a objects that need not popagate to the launched instance
   for n in Security Instances Description Profiles ChangeLog InstanceRoles InstanceDefaults ; do
      json=$(echo $json | jq "del(.$n)")
   done
   # make userData, giving it a JSON file of setting for this instance.
   echo "$json" > $instanceJsonFile
   $(dirname ${BASH_SOURCE[0]})/userData.rb $instanceJsonFile > $dataFile || { 
        echo ${FUNCNAME[0]} ERROR: failed userData.rb $instanceJsonFile; return 1; }
   sz=$(stat -t -c %s $dataFile)
   [ $sz -ge 16384 ] && { 
       msg="${FUNCNAME[0]}: ERROR User Data is too large: $dataFile"  
       msg+="User data is limited to 16384 bytes" 
       echo $msg >&2; return 1
   }
   cmd="aws ec2 run-instances  --user-data file://$dataFile"
   #local mapFile; mapFile=$WORKSPACE/userData/$name.mapping.$(date +%s)
   #$(dirname ${BASH_SOURCE[0]})/devMapping.rb $name > $mapFile && {
   #   [ -s $mapFile ] && cmd+=" --block-device-mappings file://$mapFile"
   #}
   # 4. check the cookbook has roles and atleast a Hello World recipe (accomplished by updata_s3Store).
   # 5. Update the s3Store which is used by the cloud-init process of a new instance (sync based on size-only, due to issues with berks-cookbooks time).
   update_s3Store || echo Warning failed to update bucket.
   cmd+=" --cli-input-json "
   filtered_json=$(filter_awscli_json ec2 run-instances "$json") || return 1
   local launchJson="$json"
   echo "$cmd $filtered_json" >&2
   [ x${NOOP/false/} != x ] && { echo ${FUNCNAME[0]}: NOOP is set, stopping here >&2; return 0;}
   json=$($cmd "$filtered_json") || return 1
   # Add the Name tag:
   # wait for instance to become ready, to get a  resourceId required for tag
   rId=$(echo $json | jq -r .ReservationId)
   [ OK != "${rId/r-+([[:xdigit:]])/OK}" ] && echo ${FUNCNAME[0]}: ERROR getting ReservationId >&2 && return 1
   local -i gotId gotRes
   local -i i=0 j=0; while [ $i -lt 10 ] ; do
       i+=1
       #echo json='$(aws ec2 describe-instances --f Name=reservation-id,Values='$rId' --o json)'
       json=$(aws ec2 describe-instances --f Name=reservation-id,Values=$rId --o json)
       showInst "$json" | grep pending && { sleep 10; continue; }
       showInst "$json"
       #echo "$json" | grep pending && { sleep 10; continue; }
       gotId=0; gotRes=0; for iId in $(echo $json | jq -r '.[] | .[].Instances[].InstanceId'); do
          let gotRes++
          [ OK == "${iId/i-+([[:xdigit:]])/OK}" ] && let gotId++
       done
       [ $gotId == $gotRes ] && break 
       echo wait for InstanceId...>&2
       sleep 10
    done
    [ OK != "${iId/i-+([[:xdigit:]])/OK}" ] && echo ${FUNCNAME[0]}: ERROR getting InstanceId >&2 && return 1
    #aws ec2 create-tags --resources $iId --tags Key=Name,Value=$name || rv+=1
    for iId in $(echo $json | jq -r '.[] | .[].Instances[]| "\(.InstanceId),\(.AmiLaunchIndex)"'); do
       tagName=${name%-*}-$(( ${name##*-} + ${iId##*,} ))
       tagInstance $tagName ${iId%,*} "$launchJson"
       eip=$(getEIP $tagName)
       [ OK == "${eip/eipalloc-+([[:xdigit:]])/OK}" ] && {
          echo aws ec2 associate-address --instance-id $iId --allocation-id $eip >&2
          printf "Associate PublicIp: "; aws ec2 describe-addresses --allocation-ids $eip | jq -r .Addresses[].PublicIp
          json=$(aws ec2 associate-address --instance-id $iId --allocation-id $eip)
          eip=$(echo $json | jq -r '.AssociationId' )
          [ OK != "${eip/eipassoc-+([[:xdigit:]])/OK}" ] &&  echo ${FUNCNAME[0]}: ERROR address-association "$json" >&2 && return 1
       }
    done
    showInst "$(aws ec2 describe-instances --f Name=reservation-id,Values=$rId --o json)"
    [ NAT == "${RoleName^^}" ] && {
        echo aws ec2 modify-instance-attribute --no-source-dest-check --instance-id  $iId >&2
        aws ec2 modify-instance-attribute --no-source-dest-check --instance-id  $iId
    }
    return $rv
}

####
# Set operational-tags on an instance, and/or what AWS billing logs reference as "user" tags.
#
# These user tags are set by our local billing administrator, i.e. the Jan-2018 billing records have:
# 
#      Creator
#      Department
#      Environment
#      Location
#      Name
#      OU
#      Organization
#      Owner
#      Product
#      Project
#      ProjectName
#      ProjectNumber
#      Purpose
#      ResponsibleParty
#      Role
#      Service
#      Status
#      Use

tagInstance() {
    local json data
    BUILD_TAG=${BUILD_TAG:-$(jq -r '.VpcName // .Project'  $CIDATA)}
    [ $# -lt 2 ] && { echo "Usage: ${FUNCNAME[0]} <Name> <InstanceId> {optional-JSON}" >&2; return 1; }
    #   JSON template of operational-tags  
    template1='[[
          { "Key": "Name", "Value": $n },
          { "Key": "Environment", "Value": (.Environment // "ENVIRONMENT" ) },
          { "Key": "Schedule", "Value": (.Schedule // "None" ) },
          { "Key": "Version", "Value": (.Version // "None" ) },
          { "Key": "ProjectName", "Value": (.VpcName // "None" ) },
          { "Key": "ResponsibleParty", "Value": (.KeyName // "None" ) },
          { "Key": "Role", "Value": (.RoleName // "None" ) },
          { "Key": "Build", "Value": $b },
          { "Key": "Creator", "Value": $b },
          { "Key": "Project", "Value": (.Project // "PROJECT") } ] ,  .Tags // []] | add
       | {
        "Resources": [ $id ], 
        "Tags": .
     }'
     # first (add) override data with optional-json $3
     local data=$(cat $CIDATA); data=$(echo "$data" "$3" | jq -s add)
    # Render the data into templates, first with addtional tags key/values
     json=$(echo $data | jq  --arg n "$1" --arg id "$2" --arg b "${BUILD_TAG}" "$template1")
     # the above json is used to cherry pick a few key values from cidata and optional json (after add, the optional taking preference).
     foo=$(echo $data | jq -s --arg n "$1" --arg id "$2" --arg b "${BUILD_TAG}" "$json")
     # add any Tags in $3, look again at $3, for a Tags
     echo  aws ec2 create-tags  --cli-input-json "$json"
# Apply the tags with create-tags and cli-input-json
     aws ec2 create-tags  --cli-input-json "$json"
}
# set operational-tags on a volume
tagVolume() {
    local json data
    BUILD_TAG=${BUILD_TAG:-$(jq -r '.VpcName // .Project'  $CIDATA)}
    [ $# -lt 2 ] && { echo "Usage: ${FUNCNAME[0]} <Name> <ResourceId> {optional-JSON}" >&2; return 1; }
#   JSON template of operational-tags  on an instance
    json='{
        "Resources": [ $id ], 
         "Tags": [
           { "Key": "Name", "Value": ((.Project // "PROJECT") + "-" + $n) },
           { "Key": "Environment", "Value": (.Environment // "ENVIRONMENT" ) },
           { "Key": "Version", "Value": (.Version // "None" ) },
          { "Key": "Build", "Value": $b },
           { "Key": "Project", "Value": (.Project // "PROJECT") }
         ]
     }'
     local data=$(cat $CIDATA)
# Render the JSON with given parameters for name and instanceId
     json=$(echo "$data" "$3" | jq -s --arg n "$1" --arg id "$2" --arg b  "${BUILD_TAG}" "add | $json")
     echo  aws ec2 create-tags  --cli-input-json "$json"
# Apply the tags with create-tags and cli-input-json
     aws ec2 create-tags  --cli-input-json "$json"
}
### 
# Retrieve or allocate a new EIP. 
#
# We cannot put a tag on an eipalloc, so we either save the publicIP or the eipalloc-id in CIDATA.
# 
getEIP() {
    local name=$1 json n
    json=$(jq .EIPs $CIDATA)
    for n in $name ${name%-*}; do 
         eip=$(echo $json | jq -r --arg n $n '.[$n]')
         [ "$eip" != null ] && break
    done
    [ "${eip^^}" == TRUE  ] || [ "${eip^^}" == EIPALLOC-TRUE ] && { 
        eip=$(aws ec2 allocate-address --o json | jq -r .AllocationId) || return 1; 
        [ OK != "${eip/eipalloc-+([[:xdigit:]])/OK}" ] && { return 1; }
        # save new EIP in  CIDATA 
        n=$CIDATA.$(date +%s); cp -p $CIDATA $n || return 1
        echo $json | jq --arg n $name --arg e $eip '{ "EIPs" : ([., { ($n): $e }]| add)}' >> $n
        jq -s  add $n > $CIDATA
        echo WARNING Commit of new EIPs in CIDATA is YTBD
    }
    echo $eip
}

###
# Get the console output from a VM Instance. Sometimes it is helpful, however depends on timing, the console output is not always available.
#
getConsole() {
     local usage="Usage: ${FUNCNAME[0]} [instanceTagName|id]"
     local json log id idList name retry=10 sleepsec=30
     [ -z "$1" ] && { echo "$usage" >&2; return 1; }
     local -i i
     [ -z "${1/i-*/}" ] && { idList="$1"; } || {
        json=$(get_instances ${1-:all})
        idList=$(echo $json| jq -r '.Reservations[].Instances[].InstanceId' )
     }
     for id in ${idList}; do 
         log=$(aws ec2 get-console-output --instance-id $id) 
         echo ":::::::::::::::: $(echo "$log" | jq -c '{InstanceId, Timestamp}') :::::::::::::::::::::"
         echo "$log" | jq -r .Output
     done
}
###
# Bash command line completion function
#
_ciStack_instances() {
     COMPREPLY=( $(compgen -W "$(getInstanceNames inVpc)" -- ${COMP_WORDS[COMP_CWORD]}) )
}
_ciStack_roles() {
     COMPREPLY=( $(compgen -W "$(getInstanceNames roles)" -- ${COMP_WORDS[COMP_CWORD]}) )
}
complete -F _ciStack_roles launch_instance
complete -F _ciStack_instances terminate_instance
complete -F _ciStack_instances sshI
complete -F _ciStack_instances getConsole
complete -F _ciStack_instances VIchef
complete -F _ciStack_instances devMapping.rb
complete -F _ciStack_instances userData.rb


###
# Deprecate this.
showIp() {
  local vpcId json fmt
  vpcId=$(getVpcId) || return 1 ; # vpcId=$(jq -r .VpcId $CIDATA)
  json=$(aws ec2 describe-instances --f Name=vpc-id,Values=$vpcId --o json)
  fmt='"\(.PublicIpAddress // .PrivateIpAddress ) \(.Tags[] | select(.Key=="Name").Value)"'
  echo $json | jq -r ' .Reservations[].Instances[] |'"$fmt"
}

###
# AWS-CLI bundle install.
#
install_aws() {
  type aws && return 0
  curl https://s3.amazonaws.com/aws-cli/awscli-bundle.zip -o awscli-bundle.zip;
   unzip awscli-bundle.zip || return 1
   ./awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws;
   touch /etc/profile.d/aws.sh || return 1
   chmod 644 /etc/profile.d/aws.sh
   echo "complete -C /usr/local/aws/bin/aws_completer aws" >/etc/profile.d/aws.sh
   echo 'type aws >/dev/null 2>&1 || PATH+=:/usr/local/aws/bin' >>/etc/profile.d/aws.sh
   echo Remove $(ls awscli-bundle*) ?
   rm -rI awscli-*
}

###
# The CI processes can use a session credential, this helper function will install the credentials. 
# STS should pose a lower risk, as the STS obtained credential has a limited duration.
# For testing, this helper function gets and formats the result for $HOME/.aws/credentials
# For example: To give a remote user _jenkins_, on host _dropi_,  a two hour duration session credential: 
# 
#      $ ciAwsCredentials 2*3600 jenkins@dropi
#      aws sts get-session-token --duration-seconds 7200
#      {
#        "Credentials": {
#          "AccessKeyId": "ABC...edit....XYZ",
#          "Expiration": "2017-03-13T04:36:09Z",
#          "SessionToken": "FQoDYXdzEJn//////////wEaDAEqsSxZVju...edit for brivity...jsgwdiiZi5jGBQ==",
#          "SecretAccessKey": "vFbj--edit for brivity...dxx"
#        }
#      }
#      1) yes
#      2) no
#      scp /home/djones/aws/STS_credentials.1489372571 jenkins@dropi:.aws/credentials ? 2<Enter>
#      $
#
# Beware: This will also change the remote users _.aws/config_, setting of __output__ and __region__ to your local settings.
#
# Once the Jenkins instance is established in AWS, this is nolonger needed, instead use an instance profile/role.
# On bootstrap of the first instance of Jenkins, or from an on-premises CIE, this is one solution to provide process credentials.
#
ciAwsCredentials() {
   [ $# != 2 ] && { echo Usage: ${FUNCNAME[0]} SECONDS USER@HOST; return 1; }
   local q json file; local -i sec; let sec=${1} || return 1
   local answer target=$2
   [ OK != "${target/*@*/OK}" ] && { echo ERROR: Invalid USER@HOST target: \"$target\"; return 1; }
   [ $sec -lt 900 ] && { echo WARNING: ${FUNCNAME[0]}: seconds increased to minimum of 900; sec=900; }
   file=~/aws/STS_credentials.$(date +%s)
   echo aws sts get-session-token --duration-seconds $sec >&2
   json=$(aws sts get-session-token --duration-seconds $sec ) || return 1
   echo $json | jq . 
   q='"[default]\naws_session_token = \(.SessionToken)\naws_access_key_id = \(.AccessKeyId)\naws_secret_access_key = \(.SecretAccessKey)\n"'
   echo $json | jq  -r ".Credentials | $q" > $file
   PS3="scp $file $target:.aws/credentials ?"
   select answer in yes no; do [ -n "$answer" ] && break; done
   [ "$answer" != yes ] && return 0
   echo scp $file  $target:.aws/credentials >&2
   scp $file  $target:.aws/credentials || return 1
   file=~/.aws/config; PS3="scp $file $target:.aws/config ?"
   select answer in yes no; do [ -n "$answer" ] && break; done
   [ "$answer" != yes ] && return 0
   echo scp $file  $target:.aws/config >&2
   scp $file  $target:.aws/config || return 1
}

###
# Create missing s3 buckets for a project.
# S3 bucket names are lower case, must be valid characters in a DNS record.
# The set of buckets are named in CIDATA.
#
generate_buckets() {
   local name=$(jq -r .Project $CIDATA)
   local bucket=$WORKSPACE/bucket
   local rv=0
   local url=$(jq -r .s3Store_SCM $CIDATA)/$name 
   [ -e $bucket ] || {  mkdir -p $bucket || return 1; }
   bucket+=/$name
   [ ! -d $bucket ] && {
         svn ls $url >/dev/null || {
            svn mkdir -m "$Issue Add project $name s3Store SCM folder." $(jq -r .s3Store_SCM $CIDATA)/$name || return 1
         }
         cd $(dirname $bucket) && svn co $url || return 1
   }
   for name in s3Store s3ProjectStore s3SysStore s3Home ; do
       url=$(jq -r .$name $CIDATA)
       [ $url == null ] && { echo Warning: $name is not defined && continue ; }
       [ $url != ${url,,} ] && { echo ERROR in CIDATA, for $name, the  bucket url Must be  lowercase && let rv++ ; }
       echo checking $name $url
       aws s3 ls $url >/dev/null 2>&1 || { echo Creating missing bucket $url; aws s3 mb $url || let rv++ ; }
   done
   return $rv
}
###
# Decide which aws profile name to use, based on (JOB) parameters given. 
# 
# The behavior of this function depends on paramters:
# 
# - SESSION_TOKEN
# - JOB_NAME
# - AWS_REGION
# 
# check for {JOB_NAME}-STS, or {JOB_NAME}, or default.
# When the Job provides a SESSION_TOKEN parameter, it is installed (w/ aws configure) as profile {JOB_NAME}-STS.
# When no SESSION_TOKEN is given, it looks for an existing profile name of CI-{JOB_NAME /w or wo AWS_ prefix}, or {JOB_NAME}.
# If the job does not supply AWS_REGION as a parameter, and no region exists in the profile, default to us-gov-west-1. 
export AWS_PROFILE=${AWS_PROFILE:-default}
check_aws_credentials() {
   local profile n 
   local dt access_key secret_key session_token s now
   now=$(date +%s)
   session_token=$(echo "${SESSION_TOKEN}" | jq -r .Credentials.SessionToken) || {
         echo SESSION_TOKEN paramter error .&2 ; return 1; }
   [ -n "${session_token}" ] && {
          profile=${JOB_NAME:-default}-STS
          dt=$(echo "${SESSION_TOKEN}" | jq -r .Credentials.Expiration)
          access_key=$(echo "${SESSION_TOKEN}" | jq -r .Credentials.AccessKeyId)
          secret_key=$(echo "${SESSION_TOKEN}" | jq -r .Credentials.SecretAccessKey)
          [ -n "$dt" ] && {
               sec=$(ruby -e 'require "date"; puts(DateTime.strptime(ARGV[0], "%Y-%m-%dT%H:%M:%S%Z").strftime("%s").to_s)' "$dt")
               [ $sec -le $now ] && { echo "SESSION_TOKEN has expired." >&2; return 1; }
          }
          aws configure --profile $profile set region ${AWS_REGION:-us-gov-west-1}
          aws configure --profile $profile set aws_access_key_id $access_key
          aws configure --profile $profile set aws_secret_access_key $secret_key
          aws configure --profile $profile set aws_session_token $session_token
          aws configure --profile $profile set output json
          aws configure set profile.$profile.expiration $sec
          AWS_PROFILE=$profile
   } 
   [ -z "$profile" ] && AWS_PROFILE=$(get_aws_profile)
   return 0
}

###
# Look for a profile of CI-{JOB_NAME}, {JOB_NAME}, or (preserve) AWS_PROFILE, or default
#
get_aws_profile() {
      local profile
      for profile in CI-${JOB_NAME} CI-${JOB_NAME/AWS_/} $JOB_NAME $AWS_PROFILE default; do
           aws configure get profile.${profile}.region &>/dev/null && break
      done
      echo $profile
}

###
# s3Store management for CI Jobs.
#
update_s3Store() {
   local name store cmd
   [ ! -f "$CIDATA" ] && { echo ${FUNCNAME[0]} No CIDATA; return 1; }
   name=$(jq -r .Project "$CIDATA" )
   store=$(jq -r .s3Store "$CIDATA" )
   [ ! -d $WORKSPACE/bucket/$name ] && { echo ${FUNCNAME[0]} missing ws/bucket/$name; return 1; }
   cmd="aws s3 ls $store"
   echo "${FUNCNAME[0]}: checking store: $cmd" >&2 ; $cmd >/dev/null ||  { 
       echo ${FUNCNAME[0]} could not list bucket \"$store\"; 
       cmd="aws s3 mb $store" ;
       echo "${FUNCNAME[0]}: $cmd"; $cmd ||  { echo ${FUNCNAME[0]} Failed operation on: \"$store\"; return 1; }
   }
   echo "${FUNCNAME[0]}: checking cookbook" >&2 
   ci_cookbook || { echo Cannot update due to  ci_cookbook error >&2;  return 1; }
## use --size-only, to ignore the file time-stamp, as berks-cookbooks are always getting new time-stamps (YTBD: can this be fixed? ).
   #for cmd in "aws s3 sync  bucket/$name $store/$name --size-only" "aws s3 cp  $CIDATA $store/$name/" ; do 
## With cidata is in /var/chef/environments, stop the extra copy to $store/$name.
   for cmd in "aws s3 sync  bucket/$name $store/$name --size-only"  ; do 
      echo "${FUNCNAME[0]}: $cmd" >&2 
      (cd $WORKSPACE && $cmd) || return 1
    done
}

### 
# ci_cookbook is a helper function for update_s3Store. It will stub out a chef-repo based on CIDATA.
#
# - The WORKSPACE/bucket/NAME/chef-repo is used to develop a new project from.
# - Generates any missing repo, missing cookbook, missing role-recipe,  per CIDATA.
# - Create missing ws/bucket/NAME/chef-repo/roles/ROLE.json, along with a Hello World recipe.
# - Default to cookbook-name {Project}"_ci", if no Cookbook key/value is present in CIDATA.
# - Default WORKSPACE Path: ws/bucket/__Project__/chef-repo/cookbooks/{cookbook-name}/recipies/__InstanceRoleName__.rb.
# - Create (or update) the chef environment by calling write_chef_environment (usually puts $CIDATA  into chef default_attributes).
# - Create (or update) the chef role by calling write_chef_role (usually puts instance data  into chef override_attributes).
## - Note that chef environments are not fully supported in chef-shell, - debug with pry or use a configuration w/o an environment with chef-shell.
# - Deprecate passing the cookbook as an argument, in the future only look in CIDATA.
#
# ## Example use of ci_cookbook
#
# > $ awsLoad
# > $ ciStack show NN.json
# > VPC: NN vpc-42fb6e27 10.130.0.0/16 evaluation
# > #Name       InstanceId           State    Instance   Placement-AZ VpcId        IAM-Profile    PrivateIP    PublicIP Project
# > NAT         i-0d7ab4259a26249cf  running  t2.micro us-gov-west-1a vpc-42fb6e27 null           10.130.0.73  52.61.63.39 None
# > jenkins-1   i-0f1b31f184024afa5  running  t2.micro us-gov-west-1a vpc-42fb6e27 CI-vpc-NN      10.130.20.55 null NN
# > bastion-0   i-06dfc163593593b50  running  t2.micro us-gov-west-1a vpc-42fb6e27 CI-vpc-NN      10.130.0.72  52.222.116.174 NN
# > $ ci_cookbook 
# > write_chef_role /home/djones/ws/bucket/NN/chef-repo/roles/bastion.json
# > write_chef_role /home/djones/ws/bucket/NN/chef-repo/roles/jenkins.json
# > write_chef_environment /home/djones/ws/bucket/NN/chef-repo/environments/default.json
# > Resolving cookbook dependencies...
# > Fetching 'fnmoc_ci' from source at ../../../../ciStack/chef-repo/cookbooks/fnmoc_ci
# > Fetching 'nn_ci' from source at .
# > Using fnmoc_ci (0.1.0) from source at ../../../../ciStack/chef-repo/cookbooks/fnmoc_ci
# > Using java (1.50.0)
# > Vendoring fnmoc_ci (0.1.0) to /home/djones/ws/bucket/NN/chef-repo/berks-cookbooks/fnmoc_ci
# > Vendoring java (1.50.0) to /home/djones/ws/bucket/NN/chef-repo/berks-cookbooks/java
# > Vendoring nn_ci (0.1.0) to /home/djones/ws/bucket/NN/chef-repo/berks-cookbooks/nn_ci
# > ci_cookbook: Modified /home/djones/ws/bucket, 1 new roles and recipes stubbed
# 
ci_cookbook() {
  local name cookbook="${1}" bucket=${2:-$WORKSPACE/bucket} n json new n file roles berksfp m sum
  [ -n "$cookbook" ] && echo "echo ERROR ${FUNCNAME[0]}: passing the cookbook name as an argument has been deprecated - specify cookbook in CIDATA."
  [ ! -r "$CIDATA" ] && { echo could not read CIDATA >&2; return 1; }
# - The name of the Project is taken from  the JSON file at: $CIDATA, key: __Project__
  name=$(jq -r .Project $CIDATA) || return 1;
  [ $name == null ] && return 1;
  cookbook=$(get_ci_cookbook_name) || return 1; 
  local -i modified=0
  [  -d $bucket/$name ] || { mkdir -p  $bucket/$name  || return 1; }
  [ -d $bucket/$name/chef-repo ] ||  { cd $bucket/$name && { chef generate repo chef-repo || return 1; } }
  [ -d $bucket/$name/chef-repo/cookbooks/$cookbook ] ||  { cd $bucket/$name/chef-repo/cookbooks && { chef generate cookbook $cookbook || return 1; } }
  berksfp=$bucket/$name/chef-repo/cookbooks/$cookbook/Berksfile 
  [ "$cookbook" != fnmoc_ci ] && { 
# - The CIE-common cookbook __fnmoc_ci__ and dependencies stubbed into the project Berksfile. 
# - When generating a new role, this will include recipe fnmoc_ci::common
     m=$bucket/$name/chef-repo/cookbooks/$cookbook/metadata.rb 
     grep -q fnmoc_ci $berksfp  || {
        #     sed -i '/^source/a cookbook fnmoc_ci, :path -> ../../../../ciStack/chef-repo/cookbooks' $berksfp
        sed -i '/^\s*metadata/d' $berksfp
        echo 'cookbook "fnmoc_ci", path:  "../../../../ciStack/chef-repo/cookbooks/fnmoc_ci"' >> $berksfp
        # why? -I don't think we need to do this now that we have berks-cookbooks
        # grep  -e '^\s*cookbook'  $(dirname $berksfp)/../../../../ciStack/chef-repo/cookbooks/fnmoc_ci/Berksfile >> $berksfp
        echo metadata >> $berksfp
        for n in $(awk  '/cookbook/{print $2}' $berksfp); do
           n=${n%%,*}
           grep -q -e "^\s*depends.*$n" $m || echo depends $n >> $m 
        done
     }
# - Pin the cookbook versions with Berksfile.lock, doing "berks install"
     [ ! -f $berksfp.lock ] && (cd $(dirname $berksfp) && berks install)
  }
  for n in files templates; do
   [ ! -d $bucket/$name/chef-repo/cookbooks/$cookbook/$n/default ] || mkdir -p $bucket/$name/chef-repo/cookbooks/$cookbook/$n/default 
  done
#roles=$(jq -r '[.Instances[].Name, (.Instances[].Roles |.[]?), (.Instances[].cidata.Roles |.[]?)] | sort |unique | .[]' $CIDATA)
# - Use ciData/templates/recipe.rb.erb to template a recipe for each 
  [ ! -d  $bucket/$name/chef-repo/roles ] && mkdir  $bucket/$name/chef-repo/roles 
  for n in $roles $(jq -r  '.InstanceRoles|keys|.[]' $CIDATA) ; do
     file=$bucket/$name/chef-repo/roles/$n.json
     local recipe=$bucket/$name/chef-repo/cookbooks/$cookbook/recipes/$n.rb
     local recipeSum=0
     [ -f $file ] &&  sum=$(sum $file)
     [  -f $recipe ] &&  reciepSum=$(sum $recipe)
     write_chef_role $file
     [ "$sum" != "$(sum $file)" ] && let modified++
     [ "$recipeSum" != "$(sum $recipe)" ] && let modified++
  done
  chefEnv=$(get_chef_environment_path)
# - Re-write the chef environment to freshen node[:cidata]
  [ -f "$chefEnv" ] && { envSum=$(sum ${chefEnv}); } 
  write_chef_environment $chefEnv
  [ "${envSum}" !=  "$(sum ${chefEnv})" ] && let modified++
# - Use berks dependency manager to populate chef-repo/berk-cookbooks
# 
  d=$bucket/$name/chef-repo/berks-cookbooks
  #[ ! -d $d ] && mkdir $d
# > berks vendor -b BUCKET/PROJECT/chef-repo/cookbooks/PROJECT_ci/Berksfile --delete BUCKET/PROJECT/chef-repo/berks-cookbooks
  berks vendor -b $berksfp --delete $d 
# > rm -fr BUCKET/PROJECT/chef-repo/berks-cookbooks/PROJECT_ci; # remove duplicate copy 
# 
  rm -rf $d/$cookbook
  [ $modified == 0 ] && return 0
  echo ${FUNCNAME[0]}: Modified $bucket, $modified new roles and recipes stubbed >&2
#  - It is left to a subsequent instance role launch function, to sync WORKSPACE/bucket/PROJECT to the project cloud store.
}


###
# Throttle aws describe-cmds, by keeping the last one cached, until.
# - The cache is stale after a set Time-To-Live expires (TTL).
# - Look in a different path for each region and service:  ~/.cache/aws/{region}/{aws-service}/{describe-cmd}
# - This is not option smart - so beware - only use it without filters on fairly static items.
# - This is not gaurded for sane use.
awsCache() {
   local ttl=10 cache=~/.cache/aws/$(aws configure get region)/"$1"/"$2"
   local now=$(date +%s)
   [ ! -L ${cache}_latest ] || [ $(( $now - $(stat -L -c %Z ${cache}_latest) )) -gt $ttl ] && { 
      [ ! -d $cache ] && { mkdir -p $cache || return 1; }
      aws $@ > ${cache}/$now || return 1
      find "${cache:-foobar}" -ctime 1 -exec rm --force '{}' \;
      ln -s --force ${cache}/$now ${cache}_latest
   }
   cat ${cache}_latest
}

###
# Return the path to the chef environment file
#  - Check if ENV ENVIRONMENT is set, or use default
get_chef_environment_path() {
    local myEnv=${ENVIRONMENT:-default}; # use "default" when no ENVIRONEMT variable is set.
    echo $WORKSPACE/bucket/$(jq -r .Project $CIDATA)/chef-repo/environments/${myEnv}.json
}

###
# Helper function to decide the name for ci_cookbook functions.
#
get_ci_cookbook_name() {
# - The Cookbook, is first taken from the JSON file: $CIDATA, key: __Cookbook__.
# - Otherwise, default to {project-name-lowercased}_ci, with project-name being the value in $CIDATA, key: __Project__.
  [ ! -r "$CIDATA" ] && return 1
  local name=$(jq -r .Project $CIDATA); [ $name == null ] && return 1;
  jq -r --arg cb ${name,,}_ci '.Cookbook // $cb'  $CIDATA
}

###
# Write the chef-repo environments JSON file, embedding CIDATA.
# - Present as chef node[cidata], via environment default_attributes.
# - Save existing environment override_attributes - as is.
# - (YTBD) How the cookbook version constraints are managed ....(Berksfile, metadata, ... not here now).
# I am still undecided on which route to take with chef - should CIDATA be the override or the default.
# There are 15 precedence level - too much to remember, ontop of this remember what order these are read, as 
# cookbooks can and do side-stepping in computed attributes.
write_chef_environment() {
   [ $# != 1 ] && { echo Usage: ${FUNCTNAME[0]} path/to/envnmt/file; return 1; }
   local envPath="$1" n cmd=. project=$(jq -r .Project $CIDATA)
   local cb=$(get_ci_cookbook_name) || return 1;
   # slup the existing override_attributes, and cookbook_versions to add back.
   [ -f ${envPath} ] && [ -n "$(jq . $envPath)" ] && for n in override_attributes cookbook_versions; do
        cmd+="  + { \"$n\": $(jq ".$n // {}" $envPath) }"
   done 
# - Overwrite given Path, use ciData for default_attributes, and preserving ( saved) override_attributes.
# - Look for shared settings in: ciData/global.json, add as node[:cidata][:global], for example Endpoints are in global.
   cat $CIDATA $(dirname $CIDATA)/global.json | jq  -s --arg cb $cb '.|add |{ "name": "cidata", "description": "Import of the project ciData JSON", "chef_type": "environment",
       "json_class": "Chef::Environment",
       "default_attributes": { "cidata" : .  },
       "override_attributes": { },
       "cookbook_versions": { ($cb) : ">= 0.1.0" }
       }' | jq "$cmd"   >$envPath.new
   diff -q -I discription $envPath $envPath.new || cp -f $envPath.new $envPath
   rm $envPath.new
}

###
# This function will write the chef-repo roles JSON file, embedding CIDATA.
# This does not preserver an existing chef role.
# It will check for a recipe by the same name, and template a new recipe when missing.
write_chef_role() {
   [ $# -lt 1 ] && { echo "Usage: ${FUNCTNAME[0]} {path/to/roles/roleName.json} [optional_JSON]"; return 1; }
   local rj ij="$2" name desc
   [ ! -r "$CIDATA" ] && { echo "ERROR ${FUNCTNAME[0]}: Cannot read CIDATA"; return 1; }
   local cb=$(get_ci_cookbook_name) || return 1;
   local rolePath="$1" n cmd=. project=$(jq -r .Project $CIDATA)
   [ -n "${rolePath/*.json}" ] && { 
        echo "ERROR ${FUNCTNAME[0]} expecting /path/to/{roleName}.json file" >&2; return 1; }
   [ ! -f "${rolePath}" ] && touch $rolePath
# - The name matches the given role-path
   name=${rolePath##*/}; name=${name/.json/}; 
# - If not given JSON, use instanceRoleData function to extract from CIDATA
   [ -z "$ij" ] && { ij=$(instanceRoleData $name) || return 1;  }
# - Overwrite given chef role Path, only if there is a change.
    desc="Role created by $(hostname):$(basename ${BASH_SOURCE[0]}):${FUNCNAME[0]}"
    echo $ij | jq  --arg cb $cb --arg n "$name" --arg d "$desc" '{ 
      "name": $n, "description": $d , "chef_type": "role", "json_class": "Chef::Role",
      "run_list": (.run_list // [ "recipe[" + $cb + "::" + $n + "]" ]),
      "default_attributes": (.default_attributes // {}),
      "cookbook_versions": (.cookbook_versions // { ($cb) : ">= 0.1.0" }),
      "override_attributes": (.override_attributes // {}),
      "json_class": "Chef::Role" }' > $rolePath.new
    diff -q -I discription $rolePath.new $rolePath || cp -f $rolePath.new $rolePath
    rm -f $rolePath.new 
    local recipe=${rolePath%%/roles*}/cookbooks/$cb/recipes/$name.rb
    echo "$ij" > $WORKSPACE/${FUNCNAME[0]}.tmp.json
    templateRecipe $recipe $(dirname $CIDATA)/templates/recipes/roleName.rb.erb $WORKSPACE/${FUNCNAME[0]}.tmp.json
    rm -f $WORKSPACE/${FUNCNAME[0]}.tmp.json 
}

###
# Template missing recipe and/or missing MD document comments.
#  - Use given_erb _JSON files
#  - Append to existing recipe file,  (hopefully some) embedded Markdown from genven ERB template, 
# 
# > instanceRoleData bastion > jf
# > templateRecipe bastion.rb $(dirname $CIDATA)/templates/recipes/roleName.rb.erb  jf
# > bashDoc bastion.rb
# 
templateRecipe() {
    local recipe="$1" erb="$2" jsonFile="$3" 
    [ ! -r "$erb" ] || [ ! -r "$jsonFile" ] && { echo "ERROR: Usage: ${FUNCNAME[0]} {pathToRecipe} {pathToJson} {pathToERB}"; return 1; }
    [ -f "$recipe" ] && {
        grep -q -e '^#md[+-].' $recipe || 
          templateJsonData $jsonFile $erb | grep   -e "^#md-" -B 20 >> $recipe
    } || {
        templateJsonData $jsonFile $erb >> $recipe
    }
}
###
#  Command completion function for  json to  erb templating.
#
_templateJsonData() {
  local cur prev files
  cur=${COMP_WORDS[COMP_CWORD]}
  prev=${COMP_WORDS[COMP_CWORD-1]}
  case ${COMP_CWORD} in
    1) files=$(ls $WORKSPACE/ciData/*.json) ;;
    2) files=$(ls $WORKSPACE/ciData/templates/*.erb) ;;
   esac
   COMPREPLY=( $(compgen -W "$files" -- $cur) ) 
   return 0
}

complete -F _templateJsonData templateJsonData

###
# YTBD rewrite or deprecate this, check_eipalloc, with the new Schema, this may not be needed.
# check addresses that are in ciData/*.json files, report duplicate use.
#
check_eipalloc() { return 0; }
 Xcheck_eipalloc() {
  local foo file json n eip ins q addr ytbd="eipalloc-true" ; local -i rv=0
  unset EIPhash; declare -A EIPhash; # dictionary indexed by the eipalloc-id
  foo=$(for file in $WORKSPACE/ciData/*.json; do
   jq -r --arg file ${file##*/} '"\($file):\(.Instances[].cidata.ec2.associateAddress)"' $file 
  done | grep -v null)
  for n in $foo; do EIPhash[${n/*:/}]+="${n/:*/} "; done
  json=$(aws ec2 describe-addresses)
  ins=$(aws ec2 describe-instances)
  q='{"Reservations" : [ { "Instances" : [ '
  q+='(.Reservations[].Instances[] | select(.InstanceId == $id))'
  q+=']}]}'
  echo $ytbd place-holder in ${EIPhash[$ytbd]}
  for eip in ${!EIPhash[@]}; do 
       [ ${ytbd^^} == ${eip^^} ] && { continue; }
       [ dup = "${EIPhash[$eip]/*json*json*/dup}" ] && {
            echo ERROR Duplicate use of $eip in ${EIPhash[$eip]} 
            let rv++
       }
       [ OK != "${eip/eipalloc-+([[:xdigit:]])/OK}" ] && {
             echo ERROR such: $eip ${EIPhash[$eip]} 
            let rv++
             continue
        }
        addr=$(echo $json | jq --arg eip $eip '.Addresses[] | select( .AllocationId == $eip )')
        [ -z "$addr" ] && { echo ERROR $eip for ${EIPhash[$eip]} not found in AWS.; let rv++; continue;  }
        id=$(echo $addr | jq -r .InstanceId)
        [ "$id" == null ] && { echo $eip for ${EIPhash[$eip]} not assoc w/instance.; echo $addr; continue;  }
        tmp=$(echo $ins | jq --arg id $id "$q") 
        echo $eip $(showInst "$tmp")
  done
  for eip in $(echo $json | jq -r '.Addresses[] | select(.AssociationId==null).AllocationId'); do
      [ -z "${EIPhash[$eip]}" ] &&  echo $eip is unused, and not reserved in WORKSPACE/ciData.
  done
  return $rv
}

###
# Generate Markdown documentation from comments. Shell function headers are designated with /^###/.
#
# * Lines beginning with "# "  or "###" or a function definition are used.
# * Lines between regular expressions of "/^#md-/" and /^#md+/" are ignored.
# 
# Hints or tricks to transforming your script to a markdown doc:
#
# * Simply proceed your functions with one line consisting of "###". 
# * Start with "#<space>" sequence, for additional MD lines.
# * Indent lines to exclude from markdown.
# * Start with "##" to exclude from markdown.
## A Double pound started line is ignored (like this one)
 # A space or indented line is ignored. (like this one)
bashDoc() { 
  local file=$1; 
  [ -n "$file" ] && printf "%s ${file##*/}\n\n" "%"
  awk '/^###|^# |^#$|^#md[+-]|^[A-z]+.*\()[ ]*{/; '  $file | 
    awk 'BEGIN{ p = 0 }; 
         /^#md\+/ { p = 0; next } 
         /^#md-/ { p = 1; next } 
           p { next }
         /^###/ { for( i = 1; i <= lines; ++i) { print l[i]; delete l[i];} ; lines=0; l[lines++] = substr($0,3); next } 
        /\()[ ]*{/{ printf "\n## %s\n\n", $1; for (i = 1 ; i <= lines; i++ ) { print l[i]; delete l[i]; } lines = 0; printf "<!-- images/%s -->\n", $1; next }
        lines { l[lines++] = substr($0,3); next } 
       {print substr($0,3)}
       END {
           for (i = 1 ; i <= lines; ++i)
              print l[i]
      }
      '
}

###
# Insert images in document.
#
bashDocWithImages() {
   local mdLink file="$1" images=images/${1##*/}
   [ ! -f $file ] && return 1
   bashDoc $file > ${file##*/}.md
   [ ! -d $images ] && { echo ${FUNCNAME[0]}: No $images/*.png files to insert from `pwd`; return 0; }
   # remove unwanted ()
   sed -i -e 's/\(-- images\/.*\)()/\1/' ${file##*/}.md
   for n in $(cd $images; ls *.png | sort); do
       mdLink='![inserted image]('$images/$n')'
       sed -i -e "/-- images\/${n%-*} --/ i\
           ${mdLink}"  ${file##*/}.md
   done
   sed -i -e "/-- images\/.*/d" ${file##*/}.md
}

###
# A wrapper for bashDoc, to make this transform groovy line comments. (It will not effect block comments). 
#
groovyDoc() {
# - Find line comments, and transform, with "sed  's%^//%#%' $file"
   sed  's%^//%#%' $* | bashDoc 
}

###
# Generate doc files from embedded MD in cookbook recipes and templates.
#
cookbookDoc() {
   [ $# != 1 ] &&  { echo Usage: ${FUNCNAME[0]} pathToCookbook; return 1; }
   local p=$1  file
   local cb=$(basename $p)
   echo "% Cookbook: $cb"
   cat $p/README.md
   for dir in recipes templates attributes test; do
     [ ! -d $p/$dir ] && continue
     echo -e "\n## ${dir^}\n"
     echo "===="
     for file in $p/$dir/* ; do
        [ -d $file ] && continue
        echo -e "\n### ${file##*/}\n"
        echo "----"
        grep -q -e "#md+" $file && { cat $file | bashDoc ; continue; }
        grep -q -e "//md+" $file && { groovyDoc $file | bashDoc ; continue; }
     done
   done
}


###
# DEBUG echo 
#
db_echo() {
  [ "$DEBUG" == true ] && echo -e "DEBUG:${FUNCNAME[1]}: $@"
  return 0
}

_ciStack_dependencies() {
    local cmd; local -i rv=0
    for cmd in jq aws; do
       type $cmd >/dev/null || { echo ${FUNCNAME[0]}: missing command line tool: $cmd >&2; let rv++ ; }
    done
    return $rv
}

###
#  This function should be deprecated, now that the launch will add an enumeration to resolve Name conflicts .
# reNameInstance changes the tag "Name", on an instance.
#
reNameInstance() {
   [ $# != 2 ] && { echo Usage: ${FUNCNAME[0]} oldTagName  newTagName >&2; return 1; }
   local json iId oldName=${1-=Bastion} newName=${2-=Bastion0}
   json=$(get_instances $oldName)
   iId=$(echo $json | jq -r .Reservations[].Instances[].InstanceId)
   aws ec2 create-tags --resources $iId --tags Key=Name,Value=${newName}
}

###
# Manage the IAM policies for a project VPCs. 
#
# To update a  managed  IAM policy: 
#
# - This creates a new version, here using template_vpc_lockdown_policy
# - Checks if the default limit of 5 versions  exist, stop after giving policy admin instructions (fail)
# - Add new policy version
# - Make the new policy the default
# 
update_vpc_policy() {
    local q role json vpcId policyName desc arn policy cmd n pj
    role=$(vpc_ec2_roles) || return 1
    policy=$WORKSPACE/$role.policy.json  
    vpcId=$(getVpcId) || return 1
    policyName=CI-$vpcId
# - [Template a fresh policy document](ciStack.sh.html#template_vpc_lockdown_policy)
    template_vpc_lockdown_policy > $policy || return 1
    #update_role_policy $role $policyName $policy
# - Calls [update_custom_policy](ciStack.sh.html#update_custom_policy) 
    json=$(update_custom_policy $policyName $policy) || return 1
}

###
# update managed AWS IAM custom policy on a role
# 
update_role_policy() {
    local q role json vpcId policyName desc arn policy cmd n pj roleName
    [ $# != 3 ] && { echo Usage: ${FUNCNAME[0]} groupName policyName path/to/policyDocument.json >&2; return 1; }
    policy="$3"
    [ -r $policy ] || { echo ERROR: ${FUNCNAME[0]} cannot read policy document: \"$policy\" >&2; return 1; }
    roleName=$1
    policyName=$2
# - Calls [update_custom_policy](ciStack.sh.html#update_custom_policy) 
    json=$(update_custom_policy $policyName $policy) || return 1
# - Check that role name is a valid, or create if missing.
    role=$(aws iam list-roles| jq --arg n $roleName '.Roles[]| select(.RoleName == $n)') || return 1
    [ -z "role" ] && { echo No $roleName role exists;  
         role=$(aws iam create-role --role-name $roleName  --assume-role-policy-document unfinished | jq .Role) || return 1; }

}
###
# update managed AWS IAM custom policy on a group
# 
update_group_policy() {
    local q role json vpcId policyName desc arn policy cmd n pj
    [ $# != 3 ] && { echo Usage: ${FUNCNAME[0]} groupName policyName path/to/policyDocument.json >&2; return 1; }
    policy="$3"
    [ -r $policy ] || { echo ERROR: ${FUNCNAME[0]} cannot read policy document: \"$policy\" >&2; return 1; }
    groupName=$1
    policyName=$2
# - Call update_custom_policy function
    json=$(update_custom_policy $policyName $policy) || return 1
     q='.Policies[] | select(.PolicyName==$n)'
    json=$(aws iam list-policies | jq -r --arg n "${policyName}" "$q" ) 
    arn=$(echo "$json" | jq -r .Arn); [ OK != "${arn/arn:aws*policy*/OK}" ] && return 1
# - Check that group name is a valid, or create if missing.
    group=$(aws iam list-groups| jq --arg n $groupName '.Groups[]| select(.GroupName == $n)') || return 1
    [ -z "$group" ] && { echo No $groupName group exists;  
         group=$(aws iam create-group --group-name $groupName | jq .Group) || return 1; }
    # It does not error if the attach-group-policy is repeated - so just do it again.
    #q='.AttachedPolicies[]| select( .PolicyArn == $n )'
    #json=$(aws iam list-attached-group-policies --group-name $groupName | jq --arg n $arn "$q")
    #[ -n "$json" ] &&  return 0
# - Attach current policy version
    cmd="aws iam attach-group-policy --group-name $groupName --policy-arn $arn"
    echo $cmd >&2
    $cmd
}
###
# update managed AWS IAM custom policy 
#
update_custom_policy() {
    local q role json vpcId policyName desc arn policy cmd n pj
    [ $# != 2 ] && echo Usage: ${FUNCNAME[0]} policyName path/to/policyDocument.json >&2 && return 1
    policyName=$1
    policy=$2
     q='.Policies[] | select(.PolicyName==$n)'
     json=$(aws iam list-policies | jq -r --arg n "${policyName}" "$q" ) 
     arn=$(echo "$json" | jq -r .Arn); [ OK != "${arn/arn:aws*policy*/OK}" ] && return 1
     n=$(echo $json | jq -r .DefaultVersionId)
     echo "${FUNCNAME[0]}: aws iam get-policy-version --policy-arn $arn --version-id $n > $policy.$n"
     pj=$(aws iam list-policy-versions  --policy-arn $arn  )
     [ $(echo $pj | jq '.Versions|length') -ge 5 ] && {
         echo "ERROR: ${FUNCNAME[0]}: Your account has five or more versions of policy: $policyName." >&2
         echo "ERROR: ${FUNCNAME[0]}: limits the number of version at this point." >&2
         echo "ERROR: ${FUNCNAME[0]}: The policy-administrator will need to remove old policy versions." >&2
         q='.Versions[]| select(.IsDefaultVersion == false)'
         q+='|.VersionId +$d+ .CreateDate +$d+ " To remove: aws iam delete-policy-version --policy-arn " + $arn '
         q+='+" --version-id " + .VersionId'
         echo $pj | jq -r --arg d " " --arg arn $arn "$q" >&2
         return 1
     }
     aws iam get-policy-version --policy-arn $arn --version-id $n > $policy.$n || return 1
     cmd="aws iam create-policy-version  --policy-arn $arn  --policy-document file://$policy --set-as-default" 
     echo "${FUNCNAME[0]}: $cmd " >&2
     $cmd
}


###
#  inRange is a helper function for scheduler.
#
inRange() { 
    local i="$1" range="$2";
    [ -z "$range" ] && return 0;
    [ -n "${range/*-*/}" ] && { 
        [ $i -le $range ] && return 0
    } || { 
        [ $i -le ${range/*-/} ] && [ $i -ge ${range/-*/} ] && return 0
    };
    return 1
}

###
# showJson is a helper functions for printing and a formated line of each member of an array of json objects.
# Still a WIP, this is intended as the one place to tweek output format, and input query.
# functions like: showVol. showInst, lsvm, lsvol, showEip should (eventually) use this.
showJson() {
   declare -A AFormat AMapJN
   local hdr q cols json n
   json="$1" ; shift || return 1
   AFormat=([Name]="%-11.11s" [InstanceId]="-%20.20s" [State]="%-8.8%" [InstanceType]="%-8.8s" [Placement-AZ]="%14.14s" [VpcId]="%-8.20" [IAM-Profile]="%-8.20s" [PrivateIP]="%-8.16s" [PublicIP]="%-12.16s" [default]="%10.40s")
   
   AMapJN=([State]="State.Name" [Placement-AZ]="Placement.AvailabilityZone" [IAM-Profile]="IamInstanceProfile.Arn" [PrivateIP]="PrivateIpAddress" [PublicIP]="PublicIpAddress" [Name]="$qTagName" )
   hdr='#'; q=""; # build hdr and query
   for n; do
     [ ${#hdr} -lt 2 ] && hdr+="$n" || hdr+=" $n" 
     [ -n "${Aformat[$n]}" ] && format+=" ${Aformat[$n]}" || format+=" ${Aformat[default]}"
     [ -n "${AMapJN[$n]}" ] && m="${AMapJN[$n]}" || m="$n"
     [ X == X"${m/.*/}" ] && { q+=" $m"; continue; } ; # use the pattern as given if it begins with .
     [ X == X"${m/\(*/}" ] && { q+=" $m"; continue; } ;  
     q+=" .$m"; # add a starting dot, use as jq filter
   done
   [ -n "$DEBUG" ] && { echo printf \"${format}\\n\" $hdr ; }
   printf "${format}\n" $hdr
   for  line in $(echo $json | jq "$q"); do printf "${format}\n" $line; done
}
###
# showEip is still an experiment.
#
showEip() { 
    local hdr addrs json="$1" q format="%-11.11s %-11.11s %-8.8s %-8.8s %14.14s %-12.12s %-14.14s %-12.16s %s %s";
    [ ${#json} == 0 ] && json=$(aws ec2 describe-instances);
    addrs=$(aws ec2 describe-addresses)
    xaddrs=$(echo $addrs | jq ".Addresses[] | select(.InstanceId) | . + {  Name : (${qTagName}) }" | jq -s . );
    eips=$(echo $xaddrs | jq ".[] | { (.InstanceId) : . }" | jq -s . | jq add);
    q='.eips as $eips | .foo.Reservations[].Instances[] | . + { eip : $eips[(.InstanceId)] }';
    input=$(echo "{ \"eips\" : $eips , \"foo\" : $json }" | jq "$q | select(.eip)" );
    q='.[] | ';
    q+="[ (${qTagName}), .InstanceId, .State.Name, .InstanceType, .Placement.AvailabilityZone, .VpcId, .IamInstanceProfile.Arn, .PrivateIpAddress, .PublicIpAddress, .eip.AllocationId]";
    hdr="#Name InstanceId State InstanceType Placement-AZ VpcId IAM-Profile PrivateIP PublicIP EIP";
    printf "$format\n" $hdr;
    echo $input | jq -s -c -r "$q" | sed -e 's/^\[//' -e 's/]$//' -e 's/,/\t/g' -e 's/"//g' -e 's/arn\:.*instance-profile.//' | while read line; do
        printf "$format\n" $line;
    done
}

###
# Find the intersection of keys  between input json and generate-cli-skeleton
#
filter_awscli_json() {
   local usage="Usage: ${FUNCNAME[0]}  service sub-command json"
   local qUsed cmd msg="ERROR ${FUNCNAME[0]}: "
   local gen service="$1" cmd="$2" jsonIn="$3" n
   [ -z "$cmd" ] && { echo $usage; return 1; }
   echo $jsonIn | jq . > /dev/null || { echo $msg JSON; return 1; }
   local genCmd="aws $service $cmd --generate-cli-skeleton" 
   gen=$($genCmd) || { echo $msg: $genCmd; return 1; }
   qUsed='[(.[1] | keys | unique)[], (.[0] |keys | unique)[] ]| group_by(.)[] | select(length > 1)[0]'
    arrA=( $(echo "[ $gen, $jsonIn ]" | jq "$qUsed") ); #BASH array of used keys
    for n in ${arrA[@]}; do echo $jsonIn | jq {$n}; done | jq -s '.|add'
}

###
# Helper function for nested Profiles. Used by jwalkProfile.
# 
## jwalk A W  '{ "A" : {  "k1": "Av" }, "B" : { "k1" : "Bv", "k2" : "BBv" } }'
 #  {"k1":"Av"}
## jwalk A W '{ "A" : { "W": "B", "k1": "Av" }, "B" : { "k1" : "Bv", "k2": "BBv" } }'
 #  {"k1":"Av","k2":"BBv","W":"B"}
## jwalk A W '{ "A" : { "W": "C", "k1": "Av" }, "B" : { "k1" : "Bv", "k2": "BBv" } }'
 # ERROR No such key C
# 
jwalk() {
   local key="$1" walker="$2" json="$3" v
   [ $# != 3 ] && { echo Useage ${FUNCNAME[0]} start_key walker_key json; return 1; }
   declare -A jwalk_value; jwalk_keys=(); 
   # should there be nested objects to walk:
   while [ -n  "$key" ];  do
     [ $key == null ] && break; # stop when no more nests to walk
     [ -n "${jwalk_value[$key]}" ] && break ; # stop if cyclic
     jwalk_keys+=($key)
     jwalk_value[$key]=$(echo $json | jq .$key)
     [ "${jwalk_value[$key]}" == null ] && { echo ERROR No such key $key; return 1; }
     key=$(echo ${jwalk_value[$key]} | jq -r .$walker)
   done
   local -i i=0;
   i=${#jwalk_keys[@]}; while [ $i -gt 0 ];  do
       let i--
       key=${jwalk_keys[$i]}
       echo ${jwalk_value[$key]} | jq .
       #[ i == 0 ] && jq  -n --arg x "${jwalk_keys[@]}" '{"W": $x }'
   done | jq -c -s add 
}

###
# Walk down nested profiles, adding (merging) into a collection of settings.
# - leave it up to the caller to  apply the defaults
jwalkProfile() {
   [ $# -ne 1 ] && { echo Usage: ${FUNCNAME[0]} profile_name; return 1; }
   local tmp name=$1 json=$(jq .Profiles $CIDATA)
   [ "$json" == null ] && { echo ${FUNCNAME[0]} ERROR No Profiles in CIDATA. Please migrate $CIDATA; return 1; }
   tmp=$(jwalk ${name} Profile "$json") || return 1  
   echo $tmp 
}


###
# This is a menu or helper for aws ec2 create-volume. Manually use, independently.
# It allows the user to select a build-VM (used to create, label, partition, LVM, and/of filesystem initialization.)
# Prompts for the volume attributues, then creates the volume, and attaches it to the selected VM.
# It gives suggestions for creating an LVM using the build-VM. 
# Pior to running this, the build-VM must exists in the AZ which the volume should be created.
createVol() {
   local json n instJson vId iId devName
   echo Select the BuildVM instance, you will attach the new storage, for  innitialization:
   instJson=$(get_instances $(getInstanceNames select) | jq '.[][].Instances[]')
   iId=$(echo  $instJson | jq -r .InstanceId)
   local l=$(echo $instJson | jq -r '.BlockDeviceMappings[].DeviceName')
   local devName=$(echo "$l" | tail -1 | sed 's%\(/dev/.*d\).*%\1%' )
   l=$(echo "$l" |  sed 's%/dev/.*d\(.\).*%\1%' )
   for n in {f..z}; do echo $n | fgrep -q "$l" || break ; done
   devName+=$n
   echo Next available DeviceName: $devName

   # Build cli-input-json for create-volume, 
   # AZ 
   json=$(echo $instJson | jq '{AvailabilityZone: .Placement.AvailabilityZone}')
   # Size 
   n=""; PS3="Size > "; select n in $1  10 20 100 ; do [ -n "$n" ] && break; done
   #json=$(echo $json | jq --arg n $n '[., { "Size": $n}]|add' )
   json=$( echo $json | jq '[., { "Size": '$n'}]|add' )
   # Type
   n=""; PS3="VolumeType > "; select n in gp2 io1 ; do [ -n "$n" ] && break; done
   json=$(echo $json | jq --arg n $n '[., { "VolumeType": $n}]|add' )
   # Iops YTBD
   #n=""; PS3="Iops > "; select n in YTBD; do [ -n "$n" ] && break; done
   # json=$(echo $json | jq --arg n $n '[., { "Iops": $n}]|add' )
   echo aws ec2 create-volume --cli-input-json \'$json\'
   json=$(aws ec2 create-volume --cli-input-json "$json") || return 1
   vId=$(echo $json | jq -r .VolumeId)
   echo -n Enter Volume Name:\ ; read n
   local vgName=volGroup$n lvName=${n}Vol
   echo tagVolume $n $(echo $json | jq -r .VolumeId)
   tagVolume $n $(echo $json | jq -r .VolumeId)
   json=$(jq -n --arg v $vId --arg i $iId  --arg d ${devName}  '{ "VolumeId": $v, "InstanceId": $i, "Device": $d }')
   echo aws ec2 attach-volume --cli-input-json "$json"
   aws ec2 attach-volume --cli-input-json "$json" || return 1
   cat << EOF
      echo run the following on the instance:
      vgName="${vgName:-volGroupNAME}"
      lvName="${lvName:-NAMEVol}"
      parted -a optimal --script ${devName} mklabel gpt
      parted -a optimal --script ${devName} mkpart primary 0% 100% 
      pvcreate ${devName}1
      vgcreate \${vgName} ${devName}1
      size=\$(vgdisplay -c \${vgName} | cut -d: -f12)
      lvcreate \${vgName}  --name \${lvName} --thin -l  100%FREE
      pvscan && vgscan && lvscan
      aws ec2 create-snapshot --volume-id $vId --description "LVM template: \${lvName}, buildHost: \$(hostname)"
EOF
# to make a snapshot of the volume 

}



###
# show subnets in Project VPC, or in given json. 
#
showSubnets() {
    local json="$1"
    [ -z "$json" ] && json=$(aws ec2 describe-subnets)
    local q b=".Subnets[]" keys
    keys="SubnetId "
    keys+=$(echo $json | jq -r '.Subnets[0]|keys|.[]'| grep -v -e Tags -e SubnetId)
    #q="$b"; q+='| " \(.SubnetId) "'
    q="$b"; q+="| \"\( ${qTagName}) \(${qTagProject}) "; for n in $keys; do q+='\(.'$n') '; done; q+=\"
    format="%-8.8s %-8.8s %-10.22s %-14.14s %8.8s %-8.8s %6.6s %10.10s %s %s"
   format="%-8.8s %-5.5s  %s"
   format="%-8.8s %-5.5s  %-10.22s %s %s  %-8.10s %s %s"
    hdr="#Name Project Subnet $keys"
   printf "$format" $hdr; echo 
   echo $json | jq -r "$q" | while read line; do printf "$format" $line; echo ; done
}

###
# show Snapshots in an account
#
showSnapshots() {
  local q=".Snapshots[]"; q+='|"\(.SnapshotId) \(.VolumeId) \(.VolumeSize) \('"${qTagProject}"') \(.Description)"'
  local v 
  local o=$(aws iam get-user | jq -r .User.Arn | cut -d: -f 5)
  o=${o:-148916920302}
  local volumes=$(lsvol)
  local snapshots=$(aws ec2 describe-snapshots --owner-id $o | jq -r "$q")
  for v in $(echo "$snapshots" | awk '{print $2}'); do
       echo "$volumes" | grep $v 
       echo "$snapshots" | grep $v 
       echo xxxxxxxxx ; 
  done
  echo Total GB: Volumes: $(echo "$volumes" | sed s/G// | awk 'BEGIN{i=0}; END{print i}; /Iops/{i+=$4}') \
    Snapshots: $( echo "$snapshots" | awk 'BEGIN{i=0}; END{print i}; {i+=$3}')
}

###
# ShowSGrules in project VPC
#
##  WIP still needs to show Instances-Name and/or GroupNames, CIDRs
showSGrules() {
  local q=".SecurityGroups[]"; q+='|"\(.GroupName) \(.GroupId) \(.IpPermissions[]| ([.ToPort,  (.IpRanges[].CidrIp // .UserIdGroupPairs[].GroupId )] ) "'
  local q=".SecurityGroups[]"; q+='|"\(.GroupName) \(.GroupId) \(.IpPermissions[]| .ToPort) "'
  local q=".SecurityGroups[]"; q+='|"\(.GroupName) \(.GroupId) \(.IpPermissions[]| (.ToPort,  (.IpRanges[].CidrIp // null), (.UserIdGroupPairs[].GroupId // null )) ) "'
  local q=".SecurityGroups[]"; q+='|"\(.GroupName) \(.GroupId) \(.IpPermissions[]| (.ToPort,  (.IpRanges[].CidrIp // .UserIdGroupPairs[].GroupId  )) ) "'
  local q='.SecurityGroups[]'; q+='|"\(.GroupName) \(.GroupId) IpPermission: \(.IpPermissions[]| [(.IpProtocol, .ToPort,  (.IpRanges[].CidrIp // .UserIdGroupPairs[].GroupId  ))] ) "'
  local q='.SecurityGroups[]'; q+='|"\(.GroupName) \(.GroupId) IpPermission: \(.IpPermissions[]| [(.IpProtocol, (.ToPort|tostring),  (.IpRanges[].CidrIp // .UserIdGroupPairs[].GroupId  ))] ) "'
  local q='.SecurityGroups[]'; q+='|"\(.GroupName) \(.GroupId) ingress: \(.IpPermissions[]| [(.IpProtocol, (.ToPort|tostring),  (.IpRanges[].CidrIp // .UserIdGroupPairs[].GroupId  ))]|join(" ") ) "'
  local v 
  local json=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values=${1:-$(getVpcId)} )
  echo $json | jq -r "$q" 
  # add a map of the sg-id to group-name
  #local map=$(echo $json | jq  '[.[][]| { "\(.GroupId)" : "\(.GroupName//null)" }] | add')
  #local x='.[1]SecurityGroups[]'; x+='|"\(.GroupName) \(.GroupId) IpPermission: \(.IpPermissions[]| [(.IpProtocol, (.ToPort|tostring),  (.IpRanges[].CidrIp // .UserIdGroupPairs[].GroupId  ))]|join(" ") ) "'
  # echo "$json $map"| jq -s -r "$x" 
}

###
# Helper function for picking from my ~/.aws/ profiles
#
getProfileNames() {
    ruby -r 'parseconfig' -e 'ParseConfig.new(ENV["HOME"] + "/.aws/config").params.to_h.keys.sort.each{|k| puts "#{k.sub(/^profile /,"")}" }' 
}

###
# Shell  function to set my envvironment AWS_PROFILE, and CIDATA.
#  - Set AWS_PROFILE to a profile  in ~/.aws/config
#  - Set CIDATA when a companion project is found in WOKSPACE/ciData/[AWS_]{profile}.json 
#  - Includes tab-completion of the profile name
awsProfile() {
   local foo="$1"
   #ruby -r 'parseconfig' -e 'ParseConfig.new(ENV["HOME"] + "/.aws/config").params.to_h.each{|k,v| puts k }' | sed -e /preview/d -e s/profile//|sort
   [ -z "$foo" ] &&  select foo in $(getProfileNames); do [ -n "$foo" ] && break; done
   export AWS_PROFILE=$foo
   [ -f $WORKSPACE/ciData/${foo}.json ] && CIDATA=$WORKSPACE/ciData/${foo}.json
   [ -f $WORKSPACE/ciData/AWS_${foo}.json ] && CIDATA=$WORKSPACE/ciData/AWS_${foo}.json
}
_aws_profiles() { COMPREPLY=( $(compgen -W "$(getProfileNames)" -- ${COMP_WORDS[COMP_CWORD]}) ); }
complete -F _aws_profiles awsProfile
###
# Manage the fnmoc_ci IAM-group and policies
#
# [sample policy document]: https://s3.amazonaws.com/awsiammedia/public/sample/DelegateManagementofMFA/DelegateManagementofMFA_policydocument_060115.txt
# 
# - Also see: Deligate MFA management [sample policy document]. 
# 

fnmoc_ci_group_update() {
    local groupName acct template json groups id policy policyName q n v
    local cmd desc policyDoc partition arn
    policyDoc=$WORKSPACE/$$.policydoc.json
    groupName="fnmoc-ci"
# - Use IAM get-user to find account and partition
    json=$(aws iam get-user)
    acct=$(echo $json | jq -r .User.Arn | cut -d: -f5)
    partition=$(echo $json | jq -r .User.Arn | cut -d: -f2)
# - Template fresh polcy document json, for this AWS account and partition
    template=${CIDATA%/*}/templates/aws_iam/DelegateManagementofMFA_policydocument_060115.txt
    sed -e s/ACCOUNT-ID-WITHOUT-HYPHENS/$acct/g -e s/arn:aws/arn:$partition/g $template > $policyDoc
# - Check __AllowIndividualUserToManageThierMFA__ exists
    policyName=AllowIndividualUserToManageThierMFA
    update_group_policy $groupName $policyName $policyDoc
}


ciData2param() { aws ssm put-parameter --name /$(jq -r .Project $CIDATA)/CIDATA --type String --value "$(jq -c . $CIDATA)"; }
paramCIDATA() { aws ssm put-parameter --name /$(jq -r .Project $CIDATA)/CIDATA --type String --value "$(jq -c . $CIDATA)"; }





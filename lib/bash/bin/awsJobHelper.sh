#!/bin/bash
#md+ bashDoc transforms this to markdown doc.
# This helper script is used in conjunction with [AwsUI.groovy] and an AWS_PROJECT Jenkins job.
# Such  jobs  provide a facade interface, that can preform limit management of cloud resources.
# The provided facade interface intentionally limits tasks such as changing VM-Instance run state, 
# launching new VM instances from pre-defined server roles, based on project settings (JSON ciData) 
# and credentials form an entity having the associated project management IAM role.
# 
# Requires:
# 
# - [AwsUI.groovy] to employ this
# - Jenkins [AWS_Project job] template, to employ AwsUI.groovy
# - [Uno-choice Jenkins plugin] to employ groovy scripted job active choices parameters
#
## $HeadURL: https://svn.nps.edu/repos/metocgis/infrastructure/trunk/tools/awsJobHelper.sh $ 
## $Id: awsJobHelper.sh 68709 2018-03-03 02:08:20Z dljones@nps.edu $

# [AWS_Project job]: https://svn.nps.edu/repos/metocgis/infrastructure/trunk/ciData/templates/job.xml.erb
# [AwsUI.groovy]: https://svn.nps.edu/repos/metocgis/infrastructure/trunk/tools/groovy/ciTools/AwsUI.groovy
# [Uno-choice Jenkins plugin]: https://plugins.jenkins.io/uno-choice
# 
# # Functions
# 
. $(dirname ${BASH_SOURCE[0]})/ciStack.sh || { 
   echo "ERROR ${BASH_SOURCE[0]##*/}: Could not use ciStack module"; 
   [ -n "${PS1}" ] && return 1
   exit 0; 
}

# Note: 
#
# - CIDATA values are reset in main, based on JOB_NAME.
# - WORKSPACE values are reset in main, to ~/sws, need only exists on the groovy scipt host (Jenkins master)
export CIDATA  WORKSPACE

###
# The main driver function uses the JOB_NAME environment varible, to find project settings (CIDATA).
# Requires a working copy of ciData at ~/$WORKSPACE/ciData on the Jenkins master.
# The  Script WORKSPACE (sws) and CIDATA paths are not options (in this version).
main() {
# Cache Time To Live (TTL 120 seconds) decides when fresh updates are pulled from the cloud services.
    ttl=120; # number of seconds before cache is stale
    WORKSPACE=~/sws
    [ ! -d $WORKSPACE/.cache ] && { mkdir -p $WORKSPACE/.cache || return 1; }
    # In general CIDATA will associate with JOB_NAME (AKA jenkinsProject.displayName in Groovy binding).
    for CIDATA in  $WORKSPACE/ciData/AWS_${JOB_NAME#AWS_}.json $WORKSPACE/ciData/${JOB_NAME#AWS_}.json ${2:-$CIDATA}; do
       [ -f $CIDATA ] && break; 
    done
    [ ! -f "$CIDATA" ] && { 
         CIDATA=${WORKSPACE}/ciData/${JOB_NAME#AWS_}.json 
         generate_ciData ${JOB_NAME#AWS_} &>> ${WORKSPACE}/gen.log || {
             echo ERROR: Administrative action required to provide: $CIDATA;
             return 0; # (non-error) return, allows the UI script to decide what display 
         } 
         cd ${CIDATA%/*} 
         svn add ${CIDATA%%*/} 
         svn propset svn:keywords "HeadURL Id"  ${CIDATA%%*/}
         svn ci -m "New project ciData file" ${CIDATA%%*/} 
    }
    JOB_NAME=${JOB_NAME:-${CIDATA##*/}}; JOB_NAME=${JOB_NAME/.json/}
    cache="${3:-$WORKSPACE/.cache/${JOB_NAME}}"
    cmd="${1:-showInst}"
    latest=$(updateCache $cache $ttl)
    [[ ${cmd^^} =~ REQUIR. ]] && { getRequirements "$@" ; return 0; }
    getInfo "$cmd" $latest 2>> ${WORKSPACE}/${JOB_NAME}.error.log
}

###
# Purge stale data from ~/$WORKSPACE/.cashe/$JOB_NAME, after 20 days, or older than the last 20 runs.
#
cleanCache() {
  ## YTBD
  local p 
  local -i s before; (( before = $(date +%s) - 3600 * 24 * 20 ))
  [ ! -d "$1" ] || [ X != X${1/*.cache*/} ] && return 1
  for  p in $(ls -t $1 | sed -n '20,$p'); do 
   s=$(stat -c %Y $p)
   [ $s -gt $before ] && continue
    rm -fr  $n
  done
  return 0
}

###
# __updateCache__ creates cache folders in given path,  when the latest is older than givin TTL (or default 120s).
# Return the latest cache folder, which has content from the Cloud provider (instances.json).
# 
updateCache()  {
   local cache="$1"
   local -i  ttl=${2:-120} now=$(date +%s) lastMod=0 i; i=$now
   local latest
   [ ! -d "$cache" ] && { mkdir -p   "$cache" || return 1; } || lastMod=$(stat -c %Y $cache)
   (( i = $now - $lastMod ))
   latest=$cache/$now
   [ $i -gt $ttl ] &&  {
      [ ! -d $latest ] && mkdir $latest
      # After the first run, does create_vpc,  svn update is needed to  provide CIDATA containing VpcId.
      getVpcId &>/dev/null || ( cd ${CIDATA%/*}; svn update ; )
      jFile=$latest/instances.json
      get_instances all >  $jFile 2>> $cache/error.log
      aws iam get-user > $latest/iam-get-user.json 2>>$cache/error.log
      [ -s $jFile ] && {
         n=showInst
         file=$latest/${n}.html
         echo '<pre>' > $file
         echo '<div style="overflow: auto; resize: both; "><pre>' > $file
         $n "$(cat $jFile)" >> $file 2>> $cache/error.log
         echo Last Update: $(date) >> $file
         echo '</pre></div>' >> $file
         cleanCache  $cache &>> $cache/error.log 
      } || rm -fr $latest
   } || {
     [ ! -d $latest ] && { 
        latest=$(ls -td $cache/* | grep -v log | head -1)
     }
   }
   echo $latest
}

###
# __getInfo__ will echo return arguments for UI choices, based on given command and latest cache data.
# 
# For example, the following Groovy Sript, returns command choices, for a Single Select, Active Choices Parameter:
# 
# ````groovy
#     def cmd = "/usr/bin/env JOB_NAME=" + jenkinsProject.displayName  +  "  ${System.getenv('HOME')}/sws/tools/awsJobHelper.sh COMMAND"
#     rl=[]; try {  cmd.execute().text.eachLine{ rl << it } } catch (e) { [ "ERROR ${cmd}" , e.message  ] } 
# ````
getInfo() {
   local cmd=$1 latest=$2 n outFile
   local excludeState='.Reservations[].Instances[] | select( .State.Name != $state )| '"$qTagName";
   case $cmd in
     show* )
        echo $latest/$cmd.html ;;
     run|start )
        cat $latest/instances.json | jq -r --arg state running "${excludeState}" ;;
     stop )
        cat $latest/instances.json | jq -r --arg state stopped "${excludeState}" ;;
     terminate )
        cat $latest/instances.json | jq -r --arg state nomatter "${excludeState}" ;;
     launch )
        for n in $(getInstanceNames roles 2> $latest/../error.log); do echo $n ; done ;;
     User )
        jq -r .User.Arn $latest/iam-get-user.json ;;
     Region ) aws configure get region ;;
     CIDATA ) echo $CIDATA ;;
     BUCKET_SCM ) 
        echo $(jq -r .s3Store_SCM $CIDATA)/$(jq -r .Project $CIDATA) ;;
     COMMAND )
       [ ! -f ~/.aws/credentials ] && { echo aws_credentials; return 0; }
       [ ! -f ~/.aws/config ] && { echo ERROR You must manually configure aws-cli; return 0; } 
       [ ! -f $CIDATA ] && { echo generate_ciData ; return 0; }
       getVpcId &>/dev/null || { echo create_vpc ; return 0; }
       for n in start stop launch terminate; do echo $n; done
        ;;
     * )
        n=$(jq -r ."$cmd" $CIDATA) && [ "$n" != "null" ] && { echo $n; } || { echo No options for $cmd; } 
        ;;
    esac
}

###
# Requirements check if optional input is required from the user.
#
getRequirements() {
  # expect "required:COMMAND:subject:JSON"
  local cmd json tmp=${1#*:}
  cmd=${tmp%%:*}
  json=${tmp##*:}
#  In the case of create_vpc, there should be a short json doc with the required STS cretdential.
#  This prompts the user to Enter the required short term session credential (JSON).
  case $cmd  in
    create_vpc ) 
      tmp=$(echo $json | jq .Credentials) || { echo "ERROR parsing Credentials JSON"; return 0; }
      [ -z "$tmp" ] || [ null == "$tmp" ] &&  \
        echo "Enter the required short term session credentials, for $cmd." || echo "" ;;
    *credentials ) echo Manual install of  AWS access key, AWS secret key, and default AWS region requred ;;
    * )  echo "No additional requirements" ;;
  esac
}

#md-
# Stop after loading shell functions, when sourced in an interactive shell. 
# Only run main if there is not an interactive prompt string (PS1).
[ -z "${PS1}" ] && main "$@"

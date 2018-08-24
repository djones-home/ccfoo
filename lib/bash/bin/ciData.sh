#!/bin/bash
## $HeadURL: https://svn.nps.edu/repos/metocgis/infrastructure/trunk/tools/ciData.sh $
## $Id: ciData.sh 60776 2017-05-09 11:49:48Z dljones@nps.edu $
#
# This library is used by several utilities in CI processes, see patchRelease, ciBootStrap, and ciStack. 
# ciData functions are driven from  Bash. This is early (novice) work with JSON.
#
# - Environment: 
#     * Parameter __CIDATA__ - must hold path to project-settings JSON file.
#     * jq -  Command-line JSON processor (v1.3 or greater)
#
# # Helper Functions for Indirect Use
#
# Document version:
#
#       $Id: ciData.sh 60776 2017-05-09 11:49:48Z dljones@nps.edu $
#       $HeadURL: https://svn.nps.edu/repos/metocgis/infrastructure/trunk/tools/ciData.sh $
#
#

type jq >/dev/null 2>&1 || { 
   echo ERROR: ciData requires jq - Command-line JSON processor >&2 
   echo This can be obtained from EPEL, i.e. \"yum install --enablerepo=epel jq\"  >&2 ; exit 1; 
}

###
# Create the ciData.json file - stub - deprecated with the use templates
createJsonStub() {
   local v=0.0.1 url=https://svn.nps.edu/repos/metoc 
   local desc="Data used by CI processes for build, test, and release."
   jq -n --arg group ${1:-None} --arg url $url --arg v $v --arg desc "$desc" \
 '{"Components": [ ], "SCM_prefix": $url, "ReleaseGroup": $group, "Version": $v, "Description": $desc, "aws" : [] }'
}

###
#
#
export CIDATA
getCiDataPath() { 
   [ -n "${CIDATA}" ] && {
      [ -n "$1" ] && [ ${CIDATA##*/} == $1 ] && {
          echo "$CIDATA"; return 0; }
   }
   [ -z "${1}" ] && echo ${FUNCNAME[0]}: ERROR: filename KeyValue CIDATA environment variable is required >&2 && return 1
   echo $WORKSPACE/ciData/${1}; 
}

###
# check the ciData folder exists in WORKSPACE.
# Check out the default URL if not ciData.
# Update the co of ciData
# Create a stub.json file if one does not exists.
check_ciData() {
    local file=$(getCiDataPath $1) || return 1;  
    [ OK != "${file/*.json/OK}" ]  ||
      [ $# -lt 1 ] && { echo Usage: ${FUNCNAME[0]} GroupName.json optional_ComponentNames >&2; return 1; }
    local group=${1/.json/}
    local -i rv=0
    local URL=https://svn.nps.edu/repos/metocgis/infrastructure/branches/djones/ciData
    [ ! -e $file ] && { 
       [ ! -d "${file%/*}" ] &&  { svn co $URL ${file%/*} >&2 || return 1; } 
          [ ! -e $file ] && { 
             createJsonStub ${group} > $file || return 1
             (cd ${file%/*} && svn add ${file##*/} && svn propset svn:keywords "Id HeadURL" ${file##*/} ) >&2  || return 1
             (cd ${file%/*} && svn ci -m "$Issue Stubbing new ciData $1" ${file##*/} ) >&2  || return 1
          }
    }
    echo ${FUNCNAME[0]}: $file, $(cd ${file%/*} &&  svn update) >&2 
    shift; for name; do
        jq --arg n $name '.Components[] | select(.Name==$n )' $file | grep -q Name ||
           addComponent $name $file >/dev/null
    done
    echo $file
    return $rv
}


###
#
checkVersion() {
 local Name=$1 version=$2 json=$3
 local Usage="${FUNCNAME[0]} Name version /path/to/ciData.json"
 [ X$version !=  X$(jq -r '.Components[] | select(.Name == "'$Name'").Version' $json) ] && {
      echo ERROR Componet $Name has a different version in $json
      return 1
   }
   return 0
}

###
# Update key:value pair, given component name, and json file.
#
updateComponent() {
      local n=$1 k=$2 v=$3 json=$4 tmpFile=${FUNCNAME[0]}.tmp cmd
      [ ! -r "$json" ] && {
           echo Usage: ${FUNCNAME[0]} ComponentName ComponentKey ComponentValue /path/to/file.json >&2
           return 1
      }
      case $k in 
         # if a known key for  pre-built JSON value, test that it parses 
         Uploaded )  v=$(echo $v | jq  .) || { echo Not a good value; return 1; } ;;
         # otherwise treat as a string, use jq --raw-input to make a JSON-value.
         * ) v=$(echo $v | jq --raw-input .) ;;
      esac
      cmd='(.Components[] | select(.Name=='$(echo $n | jq --raw-input .)').'$k') |= '; 
      cmd+=$v
      jq "$cmd" $json > $tmpFile &&
          cat $tmpFile > $json && rm $tmpFile
}


###
#
addComponent() {
      local n=$1  json=$2 tmpFile=${FUNCNAME[0]}.tmp
      [ ! -r "$json" ] && {
           echo Usage: ${FUNCNAME[0]} ComponentName /path/to/file.json >&2
           return 1
      }
      jq  '(.Components) |= .  + [{"Name" : "'$n'"}]'  $json > $tmpFile &&
          cat $tmpFile > $json && rm $tmpFile
}

addTime() { updateComponent $1 Time ${3:-$(date  +%s)} $2 ; }

###
# parse a mvn build log, make a JSON list of uploads
#
parseMvnUploaded() {
  local  comma="" log=$1 
  buf=""; comma=""; for line in $(sed -n 's/.*Uploaded: //p' $log | awk '{print $1}' | sort -u | jq -R '.'); do
     buf+="$comma""$line"
    comma=", "
  done 
  echo "[ $buf ]" | jq .
}

###
# update Uploaded: list for a component
addUploaded() {
      local n=$1 log=$2 json=$3
      updateComponent $n Uploaded "$(parseMvnUploaded $log)" $json
}

###
ciDataComponents() { jq -r '.Components[].Name' ${CIDATA}; }
###
ciDataUploaded() { 
   if [ $# == 0 ]; then
          jq -r '.Components[].Uploaded[]' ${CIDATA}; 
   else 
         for n ; do jq -r --arg n $n '.Components[] | select(.Name==$n).Uploaded[]' ${CIDATA} ; done
   fi
}
###
ciDataDeployables() {
  local n
  [ $# == 0 ] && set -- $(jq -r '.Components[].Name' ${CIDATA})
  for n ; do
     jq -r --arg n $n '.Components[] | select(.Name==$n).Uploaded[]' ${CIDATA} |
         grep -v -e '.xml$\|.pom$\|.jar$'
  done
}
###
#  Filter for deployable componets
isDeployable() { [ 0 != $(ciDataDeployables $* | wc -l) ]; }
###
#  WIP get GAV from the Uploaded values:
ciData2Artifacts() {
  local n line G A V T Q
  for n ; do ciDataDeployables $n | while read line; do
     line=${line/*repositories\/}; line=${line#*/}
     f=${line##*/}; line=${line%/*};
     V=${line##*/}; line=${line%/*};
     A=${line##*/}; line=${line%/*};
     G=${line//\//.}; 
##     echo G=$G, A=$A, V=$V, f=$f
     T=${f##*.} 
     Q=${f%.*} 
     Q=${Q#*-} 
     echo $G:$A:$T:$Q or $G:$A:$T:$V-${Q#*-} \?
     
  done; done
}

###
# As the name says.
updateCiDataKeyValue() {
      local n=$1 v=$2  jsonFile=${CIDATA} tmpFile=${FUNCNAME[0]}.tmp 
      [ ! -r "$jsonFile" ] && {
           echo Usage: ${FUNCNAME[0]}  Could not read CIDATA, expecting: CIDATA=/path/to/file.json >&2
           return 1
      }
      [ $# -ne 2 ] && {  echo Usage: ${FUNCNAME[0]} key value >&2;  return 1; }
      jq --arg value "${v}" '(.'"${n}"') |= $value'  $jsonFile > $tmpFile &&
             cat $tmpFile > $jsonFile && rm $tmpFile
}

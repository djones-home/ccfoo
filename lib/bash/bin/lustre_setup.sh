#!/bin/bash
#md+ bashDoc transforms this to markdown doc.
#  
# # Lustre Parallel Filesystem Deployment
# 
# This contains a module of functions used to setup Lustre servers in AWS. 
# 
# - The Lustre AMI is constructed using __build_lustre_image__ 
# - Meta-data for configuring the cluster is obtained via EC2 Tags.
# 
# ## Usage
#
# ### Server setup
# 
#     lustre_setup.sh
#
# ### Client setup
# 
#     lustre_setup.sh client
#
# ### Install and build Luster kernel for AMI
# 
#     source lustre_setup.sh
#     build_lustre_image
#
# # Module Functions
# 
###
# This function script dependencies. The script depends on having the aws-cli, and the 'jq' utility.
install_deps() {
   rpm -q epel-release >/dev/null || yum install -y epel-release
   rpm -q jq >/dev/null || { yum install -y jq || return 1; }
   install_aws &&  uname -a | grep -q lustre && return 0
   echo ERROR: ${FUNCNAME[0]}: This instance is missing dependencies, perhaps the lustre kernel. >&2
   return 1
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
   rm -rI awscli-bundle*
}

###
# Meta-data functions: getRegion, getInstance, getVpcid, and getBlockStores read the magic URL "http://169.254.169.254/latest/meta-data.
# As the name indicates they return the AWS region, instance-id, VPC-id, or block-storage-mappings of the instance, which invokes the function.
# 
## in the future, one can also get the json document, 
## curl --silent http://169.254.169.254/latest/dynamic/instance-identity/document | jq .
# 
getRegion() { local region=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone/)  && echo ${region%?}; }
getInstanceId() { curl -s http://169.254.169.254/latest/meta-data/instance-id/; }
getVpcId() { aws ec2 describe-instances --region ${1:-$(getRegion)} --instance-id ${2:-$(getInstanceId)} | jq -r '.[][].Instances[0].VpcId' ; }
getAmiLaunchIndex() { echo $(curl -s http://169.254.169.254/latest/meta-data/ami-launch-index); }
getInstanceIdentDoc() { echo $(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document); }
###
# The returned lists storage and devicename. 
# ```bash
# $ getBlockStores
# ami /dev/xvda1
# ephemeral0 /dev/xvdb
# root /dev/xvda1
# ```

getBlockStores() { 
    local store dev
    for store in $(curl -s http://169.254.169.254/latest/meta-data/block-device-mapping/); do
         dev=$(curl -s http://169.254.169.254/latest/meta-data/block-device-mapping/$store); 
         dev=${dev/\/dev\/}
         #[ x != x${store/ephemeral*/} ] && continue
         [ ! -e /dev/$dev ] && dev=${dev/sd/xvd}
         echo $store /dev/$dev
    done
}

###
# Get the tag value, given a key. 
# Block returning from this function until the desired ec2 tag is present, or the timeout expires.
# 
getTagValue() {
   [ -z "$1" ] && echo "ERROR: Usage: ${FUNCNAME[0]} <keyName> [optional-id|instance-id] [timeout|600]" >&2 && return 1
   # read my instance-id, then associated tags.
   local key=${1}  value="" id="$2" region
   [ -z "$id" ] && {
       region=$(getRegion)
       id=$(getInstanceId)
   } || {
       region=$(aws configure get region) || return 1
   }
   [ -z "$id" ] && echo "ERROR:Could not determine instance-id. Usage: ${FUNCNAME[0]} <keyName> [optional-id|instance-id] [timeout|600]" >&2 && return 1
   local  -i timeout=${3:-600}
   local  -i start=$(date +%s) 
   # read my tags, wait upto 5 minutes for  Name and Roles
   while  [ $(($(date +%s) - $start)) -lt 300 ] ; do 
      json=$(aws ec2 describe-instances --region $region --output json --instance-ids $id) || return 1
      value=$(echo $json | jq --arg k $key -r '.[][].Instances[0].Tags[]|select(.Key == $k).Value ')
      [ -n "$value" ] && break
       echo $(date) waiting for Tags: Key=$key >&2; sleep 10; 
   done
   echo $value
}

###
# This function collects all lustre Tags from instances in a VPC, returns JSON like following example:.
# 
# ```bash
# $ getLustreServers
# [
#  {
#    "InstanceId": "i-025e0daa3850f1df9",
#    "PrivateIpAddress": "10.0.20.137",
#    "lustre": "scratch mgs mdt0",
#    "State": "running",
#    "Name": "lMDS-1",
#    "fsName": "scratch"
#  },
#  {
#    "InstanceId": "i-01d615b57dc58ddbe",
#    "PrivateIpAddress": "10.0.20.250",
#    "lustre": "scratch ost0 ost1",
#    "State": "running",
#    "Name": "lOSS-0",
#    "fsName": "scratch"
#  }
# ]
# ```
## 
getLustreServers() {
   local q='.[][].Instances[] | select(.Tags[].Key == "lustre")'
   json=$(aws ec2 describe-instances --region $(getRegion) --filter Name=vpc-id,Values=$(getVpcId) | jq "$q")
   q='{ InstanceId, PrivateIpAddress, "lustre": (.Tags[]|select(.Key == "lustre").Value ), "State": .State.Name, '
   q+=' "Name": (.Tags[]|select(.Key == "Name").Value), "fsName" : (.Tags[]|select(.Key == "lustre").Value | split(" ")[0]) }'
   echo $json | jq  "$q" | jq -s .
}

### 
# Get the Network ID (NID) for the MGS for which this server is associated.
# This expect a lustre-server to only be involved with one lustre-filesystem.
# 
# ```bash
# $ getMgsNid
# 10.0.20.137@tcp0
# ```
# 
getMgsNid() {
    local fsname nid value ; local -i timeout=1800 start=$(date +%s)
    [ -z "$1" ] && value=$(getTagValue lustre); # this is meant to block until timeout or the lustre tag is created
    fsname=${value%% *}
   while : ; do 
      # filter to only servers for my fsname, and " mgs ", block until found or timeout.
      nid=$(getLustreServers | jq -r --arg n $fsname '.[] | select(.fsName == $n) | select( .lustre | contains(" mgs ")) | "\(.PrivateIpAddress)@tcp0"')
      [ -n "$nid" ] && break
      [ $(($(date +%s) - $start)) -gt $timeout ]  && return 1
      echo $(date) waiting for an instance tagged as lustre mgs for $fsname  >&2; sleep 20; 
    done
    echo $nid
}

###
# Add the lustre distribution repos
#  At the time of writing: el7.3.1611
install_lustre_el7_repo() {
 local file=/etc/yum.repos.d/lustre.repo
 [ -f $file ] && return 0
cat >$file <<EOF
[lustre-server]
name=CentOS-$releasever - Lustre
baseurl=https://downloads.hpdd.intel.com/public/lustre/latest-feature-release/el7.3.1611/server/
gpgcheck=0

[e2fsprogs]
name=CentOS-$releasever - Ldiskfs
baseurl=https://downloads.hpdd.intel.com/public/e2fsprogs/latest/el7
gpgcheck=0

[lustre-client]
name=CentOS-$releasever - Lustre
baseurl=https://downloads.hpdd.intel.com/public/lustre/latest-feature-release/el7.3.1611/client/
gpgcheck=0
EOF
}

###
# Build a lustre server upon a centos or RHEL 7.3 distro:
# - Reboot to install the new kernel.
build_lustre_image() {
   install_lustre_el7_repo
   rpm -q epel-release || yum install epel-release -y
   yum upgrade e2fsprogs -y
   yum install lustre-tests -y
   yum install --disablerepo=* --enablerepo=lustre-server kernel
# we also need to install the correct kernel headers, if we were running the kernel:
# yum install "kernel-devel-uname-r == $(uname -r)"
   kver=$(rpm -q kernel | grep lustre); kver=${kver/*kernel-/}
   rpm -q kernel-devel-$kver || yum install "kernel-devel-uname-r == ${kver}" -y
   downgrade_kernel2lustre
   uname -a | grep -q lustre || echo You must reboot to install the new kernel.>&2
}
downgrade_kernel2lustre() {
   local got_lustre=0 rl=""
   for pkg in  $(rpm -q kernel | sort -d) ; do
      [ X${pkg/kernel-*lustre*/} == X ] && { got_lustre=1 && continue ; }
      [ $got_lustre == 1 ] && rl+=" $pkg"
   done
   [ -z "$rl" ] && return 0
   echo yum remove $rl
   yum remove $rl
}


install_ena_driver() {
    echo ${FUNCNAME[0]} YTBD
}
  
install_ixgbevf_driver() {
    echo ${FUNCNAME[0]} YTBD
}

## The process that orchastrates the deployment, must make tags, to associate the filesystem and object targets, as follows: 
# aws ec2 create-tags --tags Key=lustre,Value="scratch ost0 ost1" --resources i-01d615b57dc58ddbe
# aws ec2 create-tags --tags Key=lustre,Value="scratch mgs mdt0" --resources i-025e0daa3850f1df9


# 

setup_lnet_modprobe() {
   local file=/etc/modprobe.d/lnet.conf
  [ -f $file ] && return 0
    echo 'options lnet networks=tcp0(eth0)' > $file
}

# MGS or OSS, then create lnet.modules


setup_lnet_modules() {
  setup_lnet_modprobe
  local file mod dev; 
  mod=lnet; dev=/dev/lnet; file=/etc/sysconfig/modules/lnet.modules
  [ ! -f $file ] && {
     [ ! -d ${file%/*} ] && mkdir -p ${file%*}
     echo '#!/bin/bash' > $file
     echo "[ ! -c ${dev} ] && exec /sbin/modprobe $mod &>> /dev/null" >> $file
     chmod +x $file
  }
  [ ! -x $file ] && chmod +x $file
  $file
}
setup_lustre_modules() {
  local file mod
  mod=lustre 
  file=/etc/sysconfig/modules/${mod}.modules
  [ ! -f $file ] && {
     [ ! -d ${file%/*} ] && mkdir -p ${file%*}
     echo '#!/bin/bash' > $file
     echo "/sbin/lsmod | grep -q $mod || exec /sbin/modprobe $mod &>> /dev/null" >> $file
     chmod +x $file
  }
  [ ! -x $file ] && chmod +x $file
  $file
}

###
# setup ephemeral storge targets for lustre
# Offset indexs by the ami-launch-index 
#
setup_lustre_targets() {
  local n fsname  lustre nid dir 
  local -i offset=$(getAmiLaunchIndex)
  declare -a  targets=() args=() stores=()
  umount /mnt &>>/dev/null; # cloudinit is mounting the first ephemeral volume how is this happening.
  local -i i=0 rv=0 j=0
  lustre=$(getTagValue lustre) || { echo WARNING: Could not get lustre configuration data; return 1; }
  nid=$(getMgsNid) || { echo WARNING: Could not determine lustre MGS NID >&2; return 1; }
  fsname=${lustre/ */}
  args=(); targets=(); for  n in ${lustre#* } ; do 
    case $n in 
     mgs ) 
         [ $offset == 0 ] && args[${#targets[@]}]+=" --mgs";;
     mdt* ) 
        j=$(( ${n/*t/} + $offset ))
        args[${#targets[@]}]+=" --fsname=$fsname --mdt --index=$j"
        targets[${#targets[@]}]=mdt$j 
          ;;
     ost* ) 
          j=$(( ${n/*t/} + $offset ))
          args[${#targets[@]}]+=" --fsname=$fsname --ost --mgsnode=${nid} --index=${j}"
          targets[${#targets[@]}]=ost$j 
           ;;
     * ) fsname=$n ;;
    esac
  done
  stores=( $(getBlockStores | awk '/ephemeral/{print $2}') ); 
  echo Info: ${FUNCNAME[0]}: $(set | grep ^stores) >&2
  echo Info: ${FUNCNAME[0]}: $(set | grep ^targets) >&2
  echo Info: ${FUNCNAME[0]}: lustre tag= $lustre >&2
  [ ${#stores[@]} != ${#targets[@]} ] && { 
       echo ERROR: ${FUNCNAME[0]}: The number of stores and targets differ: ${#stores[@]} != ${#targets[@]} >&2
       return 1; 
  }
  for i in  ${!targets[@]}  ; do
     echo Info: ${FUNCNAME[0]}: mkfs.lustre ${args[$i]} ${stores[$i]}
     dir=/lustre/${fsname}_${targets[$i]} 
     [ ! -d $dir ] && mkdir -p $dir
     fix_fstab ${stores[$i]}  $dir ||
       mount | grep -v lustre | grep -q -e "^${stores[$i]}\s" &&  umount ${stores[$i]}
     mkfs.lustre ${args[$i]} ${stores[$i]} || let rv++
     [ ! -d $dir ] && mkdir -p $dir
     mount  -t lustre ${stores[$i]} ${dir} || mount ${stores[$i]}
     let i++
  done
  return $rv
}

###
# ephemeral stores are sometimes already mounted on centos as /mnt
# use noauto for ephemeral storage - as it will not mount on reboot.
# Just delete any entry in fstab for the given device
fix_fstab() {
  local dev="$1" mnt="$2" options=${3:-noauto}
  local line="$dev $mnt lustre $options 0 0"
  #unalias cp &>>/dev/null; cp -fp /etc/fstab /etc/fstab.bak
  #[ ! -e "$dev" ] && return 1;
  #mount | grep -v lustre | grep -q -e "^$dev\s" &&  umount $dev
  #grep -v  "^$line" /etc/fstab | grep -q -e "^$dev\s" &&
    sed -i "s%^\($dev\)[[:space:]]%#\1%" /etc/fstab 
  #grep -q "^$line" /etc/fstab || echo "$line" >> /etc/fstab
  #diff /etc/fstab /etc/fstab.bak
}

setup_server() {
   local mgsNID
   local -i rv=0
   install_deps || { echo ERROR: $0 could not install or find dependencies >&2; return 1; }
   lustre=$(getTagValue lustre) || { echo WARNING: Could not get lustre configuration data, abort >@2; return 1; }
   nid=$(getMgsNid) || { echo WARNING: Could not determine lustre MGS NID >&2; return 1; }
   setup_lnet_modules 
   setup_lustre_modules 
   [ -n "${lustre}" ] &&  { setup_lustre_targets || { let rv++; echo Warning: ${FUNCNAME[0]}: ERROR returned from setup_lustre_targets ;} }
   return $rv
}

setup_client() {
   local -i rv=0
   local nid json
   install_deps || { echo ERROR: $0 could not install or find dependencies >&2; return 1; }
   setup_lnet_modules
   setup_lustre_modules
   json=$(getLustreServers) 
   for fsname in $(echo $json | jq -r '.[].fsName' | sort -u); do
     nid=$(echo $json | jq -r --arg n $fsname '.[] | select(.fsName == $n) | select( .lustre | contains(" mgs ")) | "\(.PrivateIpAddress)@tcp0"')
     [ $(echo "$nid" | wc -l) != 1 ] && { echo ERROR: ${FUNCNAME[0]}: Could not find a single mgsspec in : $nid >&2; let rv++; continue; }
     [ ! -d /lustre/$fsname ]  && mkdir -p /lustre/$fsname
     mount -t lustre $nid:/$fsname /lustre/$fsname || let rv++
   done
   echo $rv
}


main() {
 # Add /usr/local/bin if not already in PATH
 [ -n "${PATH/*\/usr\/local\/bin*/}" ] && PATH+=:/usr/local/bin
 case $1 in 
   client ) setup_client ;;
   * ) setup_server ;;
 esac
}

[[ $- =~ i ]] || main $@


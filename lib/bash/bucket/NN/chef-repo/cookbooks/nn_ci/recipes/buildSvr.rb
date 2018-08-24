require "json"
include_recipe "fnmoc_ci::common"
include_recipe "fnmoc_ci::app"
include_recipe "fnmoc_ci::phantomjs"
#include_recipe "fnmoc_ci::grow-volumes"

#md+ This marks this file as having embedded Markdown, for the cookbookDoc function  
#  ### A recipe to provision a buildSvr InstanceRole.
#
# This role fnmoc and NITESNext geoserver demonstration servers in AWS - in a similar fashion to the
# on-premisis (ERN) BuildSvr_Afloat_CI and BuildServer_Ashore_CI Jenkins builds, by:
#
# - Building in a WORKSPACE
# - Using Parameters (staged) from a Jenkins Job
# - Downloading artifacts from repos
# 
# Workflow: 
# 
#  - Use fnmoc_ci::common to setup system LDAP services, or other common settings to CIE cloud systems
#  - Use fnomc_ci::app  to establisg settings for  App-servers.
#  - Use this this recipe to establish a Jenkins-like WORKSPACE
#  - Run {citools}/bin/BuildSvr, same process as the ERN on-premis CI servers.
#
# Also See: [CIE Docs](https://incubator2.nps.edu/)
#
#md-  block  parsing comments for MD until the next #md+ commnet line.

# 
# Initially, Jenkins jobs are staging the aws deploy data:
# 
#     aws s3 cp $WORKSPACE/aws_deploy_data.json $(jq -r .s3SysStore $CIDATA)/ws/${BUILD_TAG}.json
#      
#     [djones@NN-bast]$ aws s3 ls fnmoc.nn.systems/ws/
#     2018-04-14 15:23:45       4279 None.json
#     2018-04-05 19:24:05       4279 jenkins-BuildSvr_CI_afloat_aws-10.json
#     2018-04-05 19:27:42       4279 jenkins-BuildSvr_CI_afloat_aws-11.json
#     ....edit...
# 
## node['BUILD_TAG'] = "jenkins-BuildSvr_CI_afloat_aws-10"
## otherwise 
## node['BUILD_TAG'] = "None" 

# - Resize /home
#    - Tests were unsuccessful on Centos-6, with dracut-module-growroot-0.20-2.el6, and ami-92961cf3
#    Although it does resize the partition, the older kernel does not see it until the next reboot.
#    The sample below, taken from a login to the newly launched instance, with BlockDeviceMappings that increased the
#    volume-size to 50G, although xvda is 50G and boot.log says growroot did resize xvda2, the lvm partition
#    size is still shown (xvda2 is still 19.5G), and pvresize does not see the added space (before rebooting).
#    It is difficult to determine the cause, as it is lacking something in initramfs, LVM tools perhap (vgchange?).
#  - Also see: [spel-el6-growroot], [growroot-fix], [backslasher-blog] on this topic. 
# 
# [spel-el6-growroot]: https://github.com/plus3it/spel/blob/3807036184854dfa10292c0434793978d3d644a7/docs/LargerThanDefaultRootEBS_EL6.md
# [growroot-fix]: https://raw.githubusercontent.com/plus3it/AMIgen6/master/GrowSetup.sh
# [backslasher-blog]: http://blog.backslasher.net/growroot-centos.html
#    
# ````bash
#     [root@ip-10-130-20-202 root]# grep growroot /var/log/boot.log
#     growroot: '/' is hosted on an LVM2 volume: setting $rootdev to /dev/xvda2
#     growroot: CHANGED: partition=2 start=976896 old: size=40966144 end=41943040 new: size=103879359,end=104856255
#     #     [root@ip-10-130-20-202 root]# pvs
#       PV         VG         Fmt  Attr PSize  PFree
#       /dev/xvda2 VolGroup00 lvm2 a--u 19.53g    0 
#     [root@ip-10-130-20-202 root]# lsblk
#     NAME                           MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
#     xvda                           202:0    0   50G  0 disk 
#     ├─xvda1                        202:1    0  476M  0 part /boot
#     └─xvda2                        202:2    0 19.5G  0 part 
#       ├─VolGroup00-rootVol (dm-0)  253:0    0    4G  0 lvm  /
#       ├─VolGroup00-swapVol (dm-1)  253:1    0    2G  0 lvm  [SWAP]
#       ├─VolGroup00-homeVol (dm-2)  253:2    0    1G  0 lvm  /home
#       ├─VolGroup00-varVol (dm-3)   253:3    0    2G  0 lvm  /var
#       ├─VolGroup00-logVol (dm-4)   253:4    0    2G  0 lvm  /var/log
#       └─VolGroup00-auditVol (dm-5) 253:5    0  8.5G  0 lvm  /var/log/audit
# ````

## This requires a prerequisit reboot of Centos-6, following grow-root.
bash 'resize-home' do
 code <<-EOF
   lsblk
    pvs
    pvresize -dv   /dev/xvda2
    lvresize -vd -l +100%FREE /dev/VolGroup00/homeVol
    pvs
    resize2fs /dev/VolGroup00/homeVol
 EOF

end

# - When /dev/VolGroup01/workspaceVol exists, resize and mount it.
bash 'resize-workspace' do
 code <<-EOF
   lv=/dev/VolGroup01/workspaceVol
   mapper=/dev/mapper/VolGroup01-workspaceVol
   pv=/dev/xvdf1
   mnt=/workspace
   kernelVersion=$(uname -r)
   [ -e $lv ] && {
      rpm -q gdisk || yum install gdisk -y
      vgchange -an VolGroup01
      growpart -v /dev/xvdf 1
      [ el6 == "${kernelVersion/2*/el6}" ] && {
          # rel6 does not support partition update, instead delete and add from the kernel. 
          partx -d /dev/xvdf
          partx -a /dev/xvdf
      }
      pvresize -dv   $pv
      lvresize -vd -l +100%FREE  $lv
      vgchange -ay VolGroup01
      e2fsck -y -f /dev/VolGroup01/workspaceVol
      resize2fs $lv
      grep -q $mnt /etc/fstab || echo "$mapper $mnt ext4 defaults 0 0" >> /etc/fstab
      mkdir $mnt
      mount $mnt
      #chmod --reference=/tmp $mnt
   }
 EOF
   not_if { File.exists?("/workspace") }
end



# - Get the build parameter JSON document named in BUILD_TAG
tmpdir = Chef::Config['file_cache_path']
deploy_data_file = "#{tmpdir}/#{node[:BUILD_TAG]}.json"
url = "#{node["cidata"]["s3SysStore"]}/ws/#{node["BUILD_TAG"]}.json"
`aws s3 cp #{url} #{deploy_data_file}` 
deploy_data = JSON.parse(File.read("#{deploy_data_file}"))

jboss_user = "jboss"
workspace = "/workspace/#{jboss_user}"

# - Insure JBOSS_USER exists
user jboss_user do
  comment "JBOSS User"
  home "/home/#{jboss_user}"
  shell "/bin/bash"
end

# - Insure /home/JBOSS_USER exists
directory "/home/#{jboss_user}" do
   owner jboss_user
   group jboss_user
   mode '0750'
end

# - Install a jboss init script from cookbook files.
cookbook_file  '/etc/init.d/jboss-standalone' do
  mode '0755'
  owner 'root'
  group 'root'
  notifies :run, 'bash[chkconfig_jboss]', :immediate
end

# - Enable jboss-standalone service (chkconfig on)
bash 'chkconfig_jboss' do
  code '/sbin/chkconfig --add jboss-standalone; /sbin/chkconfig jboss-standalone on'
  action :nothing
end

# - Add BuildSvr required packages: tree
package "tree"
# - Add ksh used by ops script
package "ksh"

# - Create WORKSPACE
directory workspace do
   owner jboss_user
   group jboss_user
   mode '0755'
   recursive true
end

# - Make /gis a link into WORKSPACE, for GIS data dir
# - Make /u a link into WORKSPACE, for legacy FNMOC paths
%w{
    /gis
    /u
}.each { |pth|
  link pth do
   to  "#{workspace}/#{File.basename(pth)}"
   link_type :symbolic
  end
}
# - Make /satdat a symlink to /gis/satdat, for legacy FNMOC paths
link "/satdat" do
   to  "/gis/satdat"
   link_type :symbolic
end

# ERN drop server used /usr/local/jboss as HOME, vs /home/jboss
# Some deploy parameters need this link, i.e. JKS_KEYSTORE
link "/usr/local/jboss" do
   to  "/home/#{jboss_user}"
   link_type :symbolic
end

file  '/etc/security/limits.d/jboss.conf' do
   content <<-EOH.gsub(/^ {6}/,"")
      # Increase limits for jboss
      jboss      soft    nproc     2048
      jboss      hard    nofile    20000
      jboss      soft    nofile    20000

   EOH
end

# - move /var/cache/yum to /workspace/cache/yum
bash 'move_yum_cache_to_workspace' do
   code <<-EOF
       sed -i -e s%^cachedir=/var%cachedir=/workspace% /etc/yum.conf
       mkdir -p /workspace/cache
       chmod --reference=/var/cache /workspace/cache
       chcon --reference=/var/cache /workspace/cache
       mv /var/cache/yum /workspace/cache
       ln -s /workspace/cache/yum /var/cache/yum
   EOF
   not_if { File.exists?("/workspace/cache") }
end

bash 'legacyOpsPaths' do
   code <<-EOF
   [ -L /tmpso ] || ln -s  /workspace/tmpso /tmpso
   [ -e /workspace/tmpso ] || { mkdir /workspace/tmpso
                     chmod --reference=/tmp /workspace/tmpso
   }
   [ -L /satdat ] || ln -s  /gis/satdat /satdat
   [ -e /opt/global/webservices  ] ||  { mkdir -p /opt/global/webservices
      ln -s #{workspace}/jboss /opt/global/webservices/jboss; 
      ln -s #{workspace}/jboss /opt/global/webservices/jboss7; 
   }
   EOF
end

## at some point jboss will need to use sudo to configure service scripts
## this is overkill
file '/etc/sudoers.d/jboss' do
   content "#{jboss_user} ALL=(ALL) NOPASSWD:ALL "
   mode '0440'
end

# - Prep Workspace
#   - Installs citools/bin into workspace, from svn imetocgis repo
#   - Use SSM secure-string parameters to setup subversion auth cache files
bash 'prep_workspace' do
   user jboss_user
   cwd workspace
   code <<-EOF
   HOME=/home/#{jboss_user}
   aws configure set region #{`aws configure get region`}
   aws configure set output json
   #PW=$(aws ssm get-parameter --name /#{node[:cidata][:Project]}/svn/foobar --w --query Parameter.Value --out text)
   url=https://svn.nps.edu/repos/metocgis/infrastructure/continuous-integration/trunk/tools/bin
   #svn co --trust-server-cert --non-interactive --username jboss --password "$PW" $url
   l=$(aws ssm describe-parameters --query 'Parameters[?starts_with(Name, `/NN/roles/buildSvr/svn/auth`)].Name' --out text)
   cmd="aws ssm get-parameter --query Parameter.Value --output text --w --name "
   oldumask=$(umask)
   umask 077
   [ ! -d $HOME/.subversion/auth ] && mkdir -p $HOME/.subversion/auth 
   for n in $l ; do
     p=$HOME/.subversion/auth${n/*auth/}
     [ ! -d $(dirname $p) ] &&  mkdir -p $(dirname $p) 
     [ ! -f $p ] && $cmd $n > $p   
   done
   umask $oldumask
   svn co $url
   ssh-keygen -C "#{node[:BUILD_TAG]}" -q -N "" -f /home/jboss/.ssh/id_rsa
   install -m 600 /home/jboss/.ssh/id_rsa.pub /home/jboss/.ssh/authorized_keys
   EOF
   notifies :run, 'bash[buildSvr]'
end

bash 'copy_deploy_data' do
   code <<-EOF
     install -m 600 -o #{jboss_user}  #{deploy_data_file} /home/#{jboss_user}/deploy_data.json 
   EOF
end
# - Load deploy data, JSON containing Job Parameter or shell env to declare.
# - Pull redacted values from ssm secure parameters
# - Run the legacy BuildSvr script
bash 'buildSvr' do
   user jboss_user
   cwd workspace
   code <<-EOF
   export LC_ALL=en_US.UTF-8
   export LANG=en_US.UTF-8
   export USER=#{jboss_user}
   role=buildSvr
   dataFile=#{deploy_data_file}
   ssmPrefix=#{node[:cidata][:Project]}/roles/$role
   declare -xr HOME=/home/#{jboss_user}; # make HOME Read-Only
   declare -xr WORKSPACE=$HOME/ws; # make WORKSPACE Read-Only
   [ -L $HOME/ws ] || ln -s #{workspace} $HOME/ws
   [ -L $HOME/ws/.m2 ] || {
      mkdir #{workspace}/.m2 && ln -s #{workspace}/.m2 $HOME/.m2
   }
   save_path=$PATH; redactedKeys=""
   for key in $(jq -r 'keys|.[]' ${dataFile}); do
       v=$(jq -r .$key ${dataFile})
       declare -x ${key}="$v"
       [ REDACTED == "$v" ] && redactedKeys+=" $key"
   done
   # 
   for key in $redactedKeys ; do
      v=$(aws ssm get-parameter --name /${ssmPrefix}/$key --w --query Parameter.Value --out text) || continue
      declare -x $key="$v"
   done
   homeStore="s3://fnmoc.nn.systems/#{jboss_user}"
   aws s3 sync $homeStore $HOME/
   PATH=/opt/chefdk/bin:${save_path}:${WORKSPACE}/bin:/opt/maven/bin
   declare -x MAVEN_OPTS="-Djavax.net.ssl.trustStore=$HOME/certs/jboss.jks -Djavax.net.ssl.keyStore=$HOME/certs/jboss.jks -Djavax.net.ssl.keyStorePassword=${JKS_TRUSTSTORE_PW} -DtrustStorePassword=${JKS_TRUSTSTORE_PW}"
   # It would nice to remove this - after deprecating BuildSvr.func:install_maven use of it
   declare -x M2_HOME=/opt/maven
   declare -x S3STORE=#{node[:cidata][:s3Store]}
   BuildSvr  2>&1 | tee  $HOME/ws/console.txt
   EOF
   action :nothing
   notifies :run, 'bash[root_httpd]'
end

# - install the local httpd setup which build server creates
bash "root_httpd" do
   command "#{workspace}/root_httpd.sh"
   only_if { File.exists?( "#{workspace}/root_httpd.sh") }
   action :nothing
end

# 
# % Install common setup for all VMs in the CI-STACK
# 

require "pry" if $stdout.tty?
#binding.pry if $stdout.tty?

##  sshd setup only happens on install of openldap-clients package, YTBD:force the setup of sshd -2017/12 djones
##  until that happens, (FOR TEST PURPOSES ONLY) I remove the package (rpm -e openldap-clients) to trigger sshd configuration change to use LDAP for authorized keys. 
#  
# ## Common attributes and their default values:
# 
# - node[__LDAP__][__BASE__] =  LDAP context root, i.e. dc=example,dc=com
node.default["LDAP"]["BASE"] = "dc=exern,dc=nps,dc=edu"
# -  node[__LDAP__][__URI__] = ldap://{openldap-0 privateIP}  (YTBD: Use tags to find openldap-# , "hub" VPC, primary/secondary in different AZs)
node.default["LDAP"]["URI"] = "ldap://10.0.20.4"
node.default[:vhostname] = "incubator2.nps.edu"

`rpm -q jq || yum install -y --enablerepo=epel jq`

unless node.has_key?("cidata") 
    Chef::Log.fatal("No cidata found. Normally this is put in your chef environment by ciTools.") 
    raise
end
unless node[:cidata].has_key?("Global") 
    Chef::Log.fatal("No Global cidata found. Normally this is put in your chef environment by ciTools.") 
    raise
end
n = node[:cidata]["Project"] + ":" + node["instanceName"]
node.default[:vhostname] = node[:cidata][:Global][:Endpoints][:Vhosts][n] if node[:cidata][:Global][:Endpoints][:Vhosts].has_key?(n)

#package "jq" do
#  options "--enablerepo=epel"
#end

# 
# ##  Install the LDAP client packages
#   

ldapClients =  node["platform"] =~ /ubuntu/ ? "ldap-utils" : "openldap-clients"
ldapConf =  node["platform"] =~ /ubuntu/ ? "/etc/ldap/ldap.conf" : "/etc/openldap/ldap.conf"
package ldapClients do
# - Trigger the setup of the client configuration, on install of packge.
  notifies :run, 'bash[openldap_client_configuration]'
# - Trigger the setup of fetching SSH public keys from LDAP, on install of packge.
  notifies :run, 'bash[authorizedKeysCmd]'
end

# 
# ##  Setup /etc/openldap/ldap.conf (RHEL), or /etc/ldap/ldap.conf (Ubuntu)
# 
bash 'openldap_client_configuration' do
 code <<-EOH
# - Set BASE to node[:LDAP][:BASE]
   sed -i 's/^.*BASE.*/BASE #{node[:LDAP][:BASE]}/' #{ldapConf}
# - Set URL to node[:LDAP][:URL]
   sed -i 's%^.*URI.*%URI #{node[:LDAP][:URI]}%' #{ldapConf}
 EOH
 action :nothing
end


authCmd = "/usr/local/sbin/fetchSSHKeysFromLDAP"

# ## Install authCmd from cookbook file.
cookbook_file  authCmd do
    mode "0755"
    owner "root"
    group "root"
end
# 
# ##  Ldap sshPublicKey fetch setup
# 
## YTBD dynamicly determing the source path for the fetcht utility, or put it into a template or chef_file
## This should run just after cloud-init, - which will create admin users - test that each of users has fetch-able ssh keys (or fail).
bash "authorizedKeysCmd" do
 code <<-EOH
#  - Install the Authorized-keys-command
   authCmd=#{authCmd}
   declare -i rv=0 keycount=0
#  - Loop through user-folders in /home,  to verify authorized keys are available from LDAP.
   for u in $(cd /home && ls -d *); do
#  - Ignore /home/{dir} if not a user in the local passwd file, this is mainly for cloud-init accounts (admin).
     grep -q -e "^${u}:" /etc/passwd || continue
     ${authCmd} $u  | grep -q ssh-rsa && { let keycount++; continue; } || {
          echo WARNING Could not fetch SSH Keys from LDAP for user: $u in #{node[:LDAP][:URI]} >&2
     }
   done
   [ $rv != 0 ] || [ $keycount == 0 ] && { exit 1; }
#  - Set SELinux authlogin_nsswitch_use_ldap and nis_enable flags
   seInfo=$(getenforce)
   [ "${seInfo/*Enforc*/X}" == X ] || [ "${seInfo/*Permis*/X}" == "X" ]   && {
       for n in nis_enable  authlogin_nsswitch_use_ldap ; do
          seInfo=$(getsebool $n) || { echo WARNING $n could not getsebool $n, perhaps not known this release; continue; }
          [ "${seInfo/* on/TRUE}" == TRUE  ] && continue 
          setsebool -P $n 1 || let rv++
        done
   }
   [ $rv != 0 ] && { exit $rv; }
# - Configure SSHd to use LDAP vs. ~/.ssh/authorized_keys, via AuthorizedKeysCommnadUser and AuthorizedKeysCommnad.
   config=/etc/ssh/sshd_config
   sed -i -e 'sX^.*AuthorizedKeysCommandUser .*XAuthorizedKeysCommandUser nobodyX'   $config
   sed -i -e 'sX^.*AuthorizedKeysCommand .*XAuthorizedKeysCommand '${authCmd}'X'   $config
# - Restart sshd with a new configuration.
   cmd="systemctl restart sshd"
   type systemctl 2>/dev/null  ||  cmd="service sshd restart"
   $cmd
 EOH
# - This action does nothing, until triggered to run upon install of the __openldap-client__ package.
 action :nothing
end


# 
# ## Maven  install and configure
# 
# - Use node[:common][:s3URL] as the path prefix (default is "s3://cibootstrap/common")
node.default[:common][:s3URI] = "s3://cibootstrap/common"
# - Use node[:common][:maven_dist] as the name of the tar ball image.
node.default[:common][:maven_dist] = "apache-maven-3.3.9-bin.tar.gz"

bash "maven_install" do
   code <<-EOH
# - Install by unarchiving a versioned folder into /opt/, i.e. /opt/apache-maven-3.3.9
     MAVEN_HOME=/opt/maven
     distFile=#{node[:common][:maven_dist]}
     dirName=#{node[:common][:maven_dist].sub(/-[^-]*$/, '')}
     aws s3 cp #{node[:common][:s3URI]}/$distFile /tmp/$distFile &&
     tar --directory /opt/ -xzf /tmp/$distFile &&
# - Symlink the versioned folds as /opt/maven
     ln -s --force /opt/${dirName} $MAVEN_HOME && rm /tmp/${distFile} &&
## backup copy of settings.xml
     cp /opt/maven/conf/settings.xml  /opt/maven/conf/settings.xml.dist
   EOH
# - Guard (prevent) a maven re-install if the /opt/{apache-maven-x.y.z} folder exists.
   not_if { File.exist?("/opt/" + node[:common][:maven_dist].sub(/-[^-]*$/, '')) }
# - Run script to build /etc/profile.d/maven.sh, if maven is installed.
  notifies :create, 'file[/etc/profile.d/maven.sh]'
# - Run template action for global settings.xml (YTBD)
#md- notifies :run, 'template[/opt/maven/conf/settings.xml]'
end

#md+
# - Create the profile.d setup file, only if maven is installed.
file  "/etc/profile.d/maven.sh" do
   mode "0644"
   content "export MAVEN_HOME=/opt/maven; PATH+=:/opt/maven/bin"
   owner "root"
   group "root"
   action :nothing
end

# - Template the settings.xml when a maven dist is installed
# 
template  "/opt/maven/conf/settings.xml" do
   mode "0644"
   source "maven_conf_settings_xml.erb"
   action :nothing
end

# 
# ## Java
#
node.default["java"]["jdk_version"] = "8" 
node.default["java"]["set_environment"] = true 
node.default["java"]["install_flavor"] = "oracle" 
node.default['java']['oracle']['accept_oracle_download_terms'] = true 
include_recipe "java::default" if node["java"].has_key?("accept_license_agreement")
#md+
# - Using the vendor-cookbooks/java, provided __override_attributes__ are set.  
# If the __accept_license_agreement__ attribute is true, then include the java::default recipe.
# For example, the following JSON object from (a partial of) /var/chef/environments/default.json:
# ````bash
# "override_attributes": {
#      "java": {
#            "jdk_version" : "8",
#            "install_flavor" : "oracle",
#            "set_etc_environment" : "true",
#            "accept_license_agreement" : "true",
#            "oracle" : {
#                 "accept_oracle_download_terms" : "true",
#                 "jce" : { "enabled" : "true"}
#            },
#            "jdk" : {
#               "7" : { "x86_64": {
#                           "url": "https://imetoc.nps.edu/nexus/public/path_to_artifact",
#                           "checksum" : "SHA-256_checksum_of_artifact"
#                        }
#               }
#            }
#       }
# }
# ````

# 
# ## Trusted Certificate Authorities (i.e. DoD PKI CAs)
# 
#  - YTBD

###
# Install node
# 
#node.default[:common][:node_dist]="v6.11.5"
node.default[:common][:node_dist]="NONE" unless node.has_key?(:common)
node.default[:common][:node_dist]="NONE" unless node[:common].has_key?(:node_dist)
bash "node_install" do
   code <<-EOH
install_node() {
  local v=${1:-v6.11.5}
  local flavor=node-$v-linux-x64 
  [ -d /opt/$flavor ] && { echo /opt/$flavor  already exists; return 0; }
  wget http://nodejs.org/dist/$v/$flavor.tar.xz && 
  tar --directory /opt/ -xf $flavor.tar.xz || return 1
  [ -L /opt/node ] && {
       echo Removing link $(ls -l /opt/node)
       rm /opt/node
  }
  ln -s $flavor /opt/node
  [ ! -f /etc/profile.d/node.sh ] && {
      install -m 755 /etc/profile.d/node.sh
      echo '[ -n "${PATH/*:\/opt\/node\/bin*/}" ] && PATH+=:/opt/node/bin' >/etc/profile.d/node.sh
  }
}
install_node #{node[:common][:node_dist]} && {
      [  -f /opt/node/bin/grunt ] || env PATH=$PATH:/opt/node/bin /opt/node/bin/npm -g install grunt-cli
   }

   EOH
   not_if { node[:common][:node_dist].upcase == "NONE" }
end

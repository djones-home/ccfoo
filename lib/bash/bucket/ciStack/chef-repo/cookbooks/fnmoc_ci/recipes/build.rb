#md+
# This chef recipe sets up the build-0 slave node for Jenkins to use to perform builds on.
#
include_recipe 'java'

package %w{ subversion unzip wget }

# - Create linux user jenkins.
user 'jenkins' do
        comment 'Jenkins user'
        home '/var/lib/jenkins'
        shell '/bin/bash'
end

#
# - Configure yum to use soft certs and with the necessary repos it will be using
#
#
 
template "/var/lib/yum/client.cert" do
 	source "client.cert"
end

template "/var/lib/yum/client.key" do
	source "client.key"
end

template "/etc/yum.conf" do
	source "yum.conf"
end

template "/etc/yum.repos.d/nexus.repo" do
	source "nexus.repo"
end

template "/etc/yum.repos.d/mrepo_ern.repo" do 
 	source "mrepo_ern.repo"
end

template "/etc/yum.repos.d/epel.repo" do
	source "epel.repo"
end


package "rpm-build"

                             
###
# -  Install node(npm and gruntcli)
#
node.default[:common][:node_dist]="v6.11.5"
#node.default[:common][:node_dist]="NONE"
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
 


# - Install grunt_cli for node
bash "install_grunt_cli" do
	code <<-EOH
		/opt/node/bin/npm -g install grunt-cli
	EOH
not_if {File.exist?("/opt/node/bin/grunt")}
end
#md+ This marks this file as having embedded Markdown, for the cookbookDoc function  
#  ### A recipe to provision a build InstanceRole
#
# You should replace this a with useful description of how a __build__ is provisioned.
# 
# Workflow: 
# 
#  - Interesting step
#  - Anonther interesting step in the setup
#
# Also See: [CIE Docs](https://incubator2.nps.edu/)
#
#md-  block  parsing comments for MD until the next #md+ commnet line.

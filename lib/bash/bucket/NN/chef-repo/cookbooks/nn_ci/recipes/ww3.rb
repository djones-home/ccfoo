#md+ This marks this file as having embedded Markdown, for the cookbookDoc function  
#  ### A recipe to provision a ww3 InstanceRole
#
# You should replace this a with useful description of how a __ww3__ is provisioned.
# 
# Workflow: 
# 
#  - Interesting step
#  - Anonther interesting step in the setup
#
# Also See: [CIE Docs](https://incubator2.nps.edu/)
#
#md-  block  parsing comments for MD until the next #md+ commnet line.

puts "Hello World. File: #{__FILE__},  roles: #{node['roles']}."

###
# - Include the CIE common setup 
# 
include_recipe "fnmoc_ci::common"

####
# - Install curl, vm, and jq
package %{ curl vim jq }

###
# - Create this fake config file in tmp, when missing
file "/tmp/path-to-fake-cfg" do
  content  <<-EOH.gsub(/^ {6}/, '')
      [default]
      name=gitlab_gitlab-ce
      baseurl=https://packages.gitlab.com/gitlab/gitlab-ce/el/7/$basearch
      repo_gpgcheck=1
      gpgcheck=0
   EOH
  action :create_if_missing
  notifies :run, 'bash[my_post_install]'
end



###
# - Run these commands in bash, if notificed, otherwise this does nothing.
#

bash 'my_post_install' do
  code <<-EOH
  echo Rather than "ehco", this could do somehing like: "systemctl enable myservice"
  EOH
  action :nothing
end


bash 'openproject_install' do
  action :nothing
  command <<-EOH
   rpm --import https://rpm.packager.io/key
   yum -y install openproject
  EOH
   notifies :run, 'bash[openproject_configure]', :immediate
end

bash 'openproject_configure' do
  action :nothing
  command <<-EOH
    echo wait and see, we cannot run the gui, openproject configure, so we need to a template YTBD
  EOH
end

file '/etc/yum.repos.d/openproject.repo' do
   content  <<-EOH.gsub(/^ {6}/, '')
      [openproject]
      name=Repository for opf/openproject-ce application.
      baseurl=https://rpm.packager.io/gh/opf/openproject-ce/centos7/stable/6
      enabled=1
      
   EOH
   action :create_if_missing
   notifies :run, 'bash[openproject_install]', :immediate

end
#md+ This marks this file as having embedded Markdown, for the cookbookDoc function  
#  ### A recipe to provision a openproject InstanceRole
#
# You should replace this a with useful description of how a __openproject__ is provisioned.
# 
# Workflow: 
# 
#  - Interesting step
#  - Anonther interesting step in the setup
#
# Also See: [CIE Docs](https://incubator2.nps.edu/)
#
#md-  block  parsing comments for MD until the next #md+ commnet line.

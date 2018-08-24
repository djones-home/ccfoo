puts "app: Hello World"
include_recipe "fnmoc_ci::common"
#include_recipe "fnmoc_ci::app"

# For example to install a packages:
#  - Use of yum package installs, the following example would insure four packages are installed, including packages that require enabling the epel repo.
#package %w{ subversion wget unzip jq } do
#  options "--enablerepo=epel"
#end




#md+ This marks this file as having embedded Markdown, for the cookbookDoc function  
#  ### A recipe to provision a app InstanceRole
#
# You should replace this a with useful description of how a __app__ is provisioned.
# 
# Workflow: 
# 
#  - Interesting step
#  - Anonther interesting step in the setup
#
# Also See: [CIE Docs](https://incubator2.nps.edu/)
#
#md-  block  parsing comments for MD until the next #md+ commnet line.

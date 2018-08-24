#md+ This marks this file as having embedded Markdown, for the cookbookDoc function  
#  ### A warpper recipe to provision an openldap InstanceRole
#
# Also See: [CIE Docs](https://incubator2.nps.edu/)
#
#md-  block  parsing comments for MD until the next #md+ commnet line.


###
# - Include the CIE common setup 
# 
include_recipe "fnmoc_ci::common"
include_recipe "fnmoc_ci::openldap"


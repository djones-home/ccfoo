
#md+
# Recipe to provision jenkins
#
# - Includes the fnmoc_ci cookbook jenkins recipe.

include_recipe "fnmoc_ci::jenkins"

# 
#
#md+ This marks this file as having embedded Markdown, for the cookbookDoc function  
#  ### A recipe to provision a jenkins InstanceRole
#
# You should replace this a with useful description of how a __jenkins__ is provisioned.
# 
# Workflow: 
# 
#  - Interesting step
#  - Anonther interesting step in the setup
#
# Also See: [CIE Docs](https://incubator2.nps.edu/)
#
#md-  block  parsing comments for MD until the next #md+ commnet line.

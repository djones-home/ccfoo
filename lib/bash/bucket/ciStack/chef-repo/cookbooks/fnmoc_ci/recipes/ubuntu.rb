#md+
#  ### A recipe to provision a ubuntu InstanceRole
#
# Workflow: 
# 
#  - Interesting step
#  - Anonther interesting step in the setup
#
# Also See: [CIE Docs](https://incubator2.nps.edu/)
#
#md-  block  parsing comments for MD until the next #md+ commnet line.


###
# - Include the CIE common setup 
# 
include_recipe "fnmoc_ci::common"

####
# - Install packages 
#     - curl, vim, jq, subversion nodejs npm  pandoc
package %w{ curl vim jq subversion nodejs npm pandoc }
# 

#     - rippledoc
# - Install reveal-md framwework for Markdown slides is ciedoc site
bash 'reveal-md-Install' do
  code <<-EOH
    npm install -g reveal-md &&
    ln -s /usr/bin/nodejs /usr/bin/node
  EOH
  not_if { File.exists?("/usr/bin/nodejs") }
end

# - Install reveal-md framwework for  Markdown slides is ciedoc site
bash 'rippledocJar' do
  code <<-EOH
    install -D /var/chef/cookbooks/fnmoc_ci/files/rippledoc-0.1.2-standalone.jar  /usr/local/bin/
  EOH
  not_if { File.exists?("/usr/local/bin/rippledoc-0.1.2-standalone.jar") }
end

# - Install rippledoc.sh
file '/usr/local/bin/rippledoc.sh' do
  mode "0755"
  content <<-EOH
#!/bin/bash
java -jar /usr/local/bin//rippledoc-0.1.2-standalone.jar "$@"
EOH
end

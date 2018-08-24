#md+ bashDoc to transform into markdown
###
# ## Install gitlab service.
# Install GitLab CE Omnibus on el7, Centos 7, Redhat 7, ...
# The omnibus install has chef embedded in the release, so we cannot run chef inside chef.
# Manually run (or schedule) the last step (which uses chef).
#
#  1. Install server package
#  #. ....
#
# Reference https://about.gitlab.com/downloads/#centos7

#
# ### Node["nexus"][ _variables_ ]:
#
# -  __packageURL__   The artifact to install
node.default["nexus"]["packageURL"] = "dc=ccs,dc=nps,dc=edu"


#  gitlab-ctl reconfigure
#
file "/etc/yum.repos.d/gitlab_gitlab-ce.repo" do
  content  <<-EOH.gsub(/^ {6}/, '')
      [gitlab_gitlab-ce]
      name=gitlab_gitlab-ce
      baseurl=https://packages.gitlab.com/gitlab/gitlab-ce/el/7/$basearch
      repo_gpgcheck=1
      gpgcheck=0
      enabled=1
      gpgkey=https://packages.gitlab.com/gitlab/gitlab-ce/gpgkey
      sslverify=1
      sslcacert=/etc/pki/tls/certs/ca-bundle.crt
      metadata_expire=300
      
      [gitlab_gitlab-ce-source]
      name=gitlab_gitlab-ce-source
      baseurl=https://packages.gitlab.com/gitlab/gitlab-ce/el/7/SRPMS
      repo_gpgcheck=1
      gpgcheck=0
      enabled=1
      gpgkey=https://packages.gitlab.com/gitlab/gitlab-ce/gpgkey
      sslverify=1
      sslcacert=/etc/pki/tls/certs/ca-bundle.crt
      metadata_expire=300
   EOH
  action :create_if_missing
  # notifies :run, 'bash[gitlab_post_install]'
end

package %{ curl policycoreutils postfix gitlab-ci.x86_64 }

bash 'gitlab_post_install' do
  code <<-EOH
  systemctl enable postfix
  systemctl start postfix
  firewall-cmd --permanent --add-service=http
  systemctl reload firewalld
  file=/root/root_gitlab
  echo '#!/bin/bash' > $file 
  echo '# cannot run chef inside chef so manually run this' >> $file
  echo sudo gitlab-ctl reconfigure >>$file
  chmod +x $file
  EOH
  action :nothing
end
#
# install ssl certificates

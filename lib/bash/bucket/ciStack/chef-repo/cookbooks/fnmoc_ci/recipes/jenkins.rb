#md+ bashDoc to transform into markdown
###
# ## Install Jenkins service.
#
# Install jenkins from an rpm - the self-contained package, confugure init scripts, to accomidate the CIE.
#
# - Jenkins CLI
# - Security Authentication and Authorization
# - Set a minimal list of plugins in the cieSetup.groovy template, those given in __node[:jenkins_plugins]__.
# - YTBD: Do we support pinned plugin versions here or do that elsewhere (AMIs, backups, restore script w/cli) ?.
# The latest version of these will be installed from the updatecenter.
# For specific versions of jenkins plugings concider keeping an S3 or local store to copy from
# Additional jenkins plugings can be added with the ssh-cli, following this recipe:
# 
# > sudo - ssh -p 8022 maintuser@localhost install-plugin  docker-workflow 
# > ### or 
# > ssh -p 8022 $CN@localhost install-plugin  docker-workflow 
# 
# - YTBD move jenkins_admins to a more appropriate place, perhaps ciData/global.json, (now default to Dan and Kevin).
node.default[:jenkins_admins] = %w( JONES.DANIEL.L.1265422345 SEZEN.KEVIN.SERMET.1412295257 )

node.default[:jenkins_plugins] = %w(
  mailer
  credentials
  ssh-credentials
  ssh-slaves
  ldap
  reverse-proxy-auth-plugin
  subversion
  uno-choice
)

  # build-timeout credentials-binding 
  # email-ext github-organization-folder 
  # gradle workflow-aggregator 
  # timestamper ws-cleanup


# - YTBD, document CIE convensions for setting node.override: in cb, role, or env.
# - Share use of a few  community jenkins cookbook attributes, i.e.  __jenkins_args__.
node.default[:jenkins][:master][:jenkins_args] = " --prefix=/jenkins"
node.default[:jenkins][:master][:host] = node[:fqdn]


## user jenkins is made by the rpm install script

# -YTBD: Move the attribute setup to install oracle java 
node.override["java"]["accept_license_agreement"] = true
node.override["java"]["jdk_version"] = "8"
node.override["java"]["install_flavor"] = "oracle"
node.override["java"]["set_etc_environment"] = "true"
include_recipe "fnmoc_ci::common"

# ### Recipe workflow:

# - Gotta have rpm-build, subversion, git, and wget packages.
package %w{ rpm-build subversion git wget }  do
  options "--enablerepo=epel "
end

## AWS DNS will return the PrivateIP when we lookup the public name
#proxyPrivateIp = `getent hosts #{node[:vhostname]}`.split(" ")[0]

# - Install a pgdg repo, as a postgresql package is needed for the sonar plugin data
# - YTBD move this pgdg repo setup to a db recipe, and just include_recipe.

unless node["cidata"].has_key?("pgdg_repo_rpm") 
   a = { 
     "rhel7" => "https://download.postgresql.org/pub/repos/yum/9.6/redhat/rhel-7-x86_64/pgdg-redhat96-9.6-3.noarch.rpm",
     "rhel6" => "https://download.postgresql.org/pub/repos/yum/9.0/redhat/rhel-6-x86_64/pgdg-redhat90-9.0-5.noarch.rpm" 
   }
   i =  node[:platform_family] + node[:platform_version].split(".")[0]
   unless a.has_key?(i)
        Chef::Log.fatal("Platform is not supported here: #{i}, nore is there a value in node[:cidata][:pgdg_repo_rpm] ")
        raise
   end
   node.default["cidata"]["pgdg_repo_rpm"] = a[i]
end
bash "install_pgdg" do
 code <<-EOH
   rpm -i #{node["cidata"]["pgdg_repo_rpm"]}
 EOH
 not_if { !Dir.glob('/etc/yum.repos.d/pgdg*.repo').empty? }
end


# - Insure there is a yum.repo.d/jenkins.repo
#    - SELinux at this time, does not allow cloud-init run_cmds to use firewall-cmd, they just hang, on CentOS7, either add policy, or turn off enforce.

bash "install_jenkins" do
 code <<-EOH
  wget -O /etc/yum.repos.d/jenkins.repo http://pkg.jenkins.io/redhat-stable/jenkins.repo
  rpm --import http://pkg.jenkins.io/redhat-stable/jenkins.io.key
  if type firewall-cmd 2>/dev/null; then
    setenforce Permissive
    firewall-cmd --zone=public --add-port=8080/tcp --permanent
    firewall-cmd --zone=public --add-service=http --permanent
    firewall-cmd --reload
    setenforce Enforcing
  fi
  # for EL6, YTBD get the shell function from BuildSvr.func for this:
  # iptables_additions 8080 tcp #{`getent hosts #{node[:vhostname]}`.split(" ")[0]}
  yum -y install jenkins
  # service jenkins start
  # chkconfig jenkins on
 EOH
 not_if {File.exists?("/etc/yum.repos.d/jenkins.repo")}
end

# - Install the jenkins master ssh private key - if available.
#    In AWS, checks the SSM service for a secureString (encrypted) parameter.
directory  "/var/lib/jenkins/.ssh" do
   owner 'jenkins'
   group 'jenkins'
   mode '0700'
   recursive True
end

file "/var/lib/jenkins/.ssh/id_rsa" do
   content  `aws ssm get-parameter --name /#{node[:cidata][:Project]}/users/jenkins/ssh/id_rsa --w --query Parameter.Value --out text`
   owner 'jenkins'
   group 'jenkins'
   mode '0700'
   recursive True
end

# - Install /etc/system/jenkins configuration from a template
## Beware creating this file before the rpm installs confused the preinstall script - and the rpm install failed.
template "/etc/sysconfig/jenkins" do
   source "sysconfig.jenkins.erb"
   notifies :run, 'bash[restart_jenkins]', :delayed
end

# - Install Jenkins init hook scripts into JENKINS_HOME/init.groovy.d
directory "/var/lib/jenkins/init.groovy.d" do
    owner "jenkins"
    group "jenkins"
    recursive true
end

directory "/var/lib/jenkins/jobs"  do
    owner "jenkins"
    group "jenkins"
end

#   - 01_ciePlugins.groovy will install missing plugins
template "/var/lib/jenkins/init.groovy.d/01_ciePlugins.groovy" do
   source "ciePlugins.groovy.erb"
   #notifies :restart, 'service[jenkins]', :immediate
   notifies :run, 'bash[restart_jenkins]', :delayed
end

#   -  02_cieSecurity.groovy: sets the security realm, authz strategy, SSHD port, and disable unsecure protocols.
template "/var/lib/jenkins/init.groovy.d/02_cieSecurity.groovy" do
   source "cieSecurity.groovy.erb"
   notifies :run, 'bash[restart_jenkins]', :delayed
end

#   - 03_setup-users-groovy: may reset authz strategy, add matrix users/groups/administrators, add the admin ssh-cli authorized keys
template "/var/lib/jenkins/init.groovy.d/03_setup_users.groovy" do
   source "setup-users.groovy.erb"
   notifies :run, 'bash[restart_jenkins]', :delayed
end



#md-
# At the time chef starts, if there is not be a jenkins service, this gave an exception (v12)
# For this reason, I dropped use of the "service" statement for jenkins, replaced with  bash code.
#service 'jenkins' do
#   action :nothing
#end
#md+

# - Create a Jenkins job named AWS_{Project} that runs the ciStack UI.
# This job allows users to show, stop, start, launch, and terminate VM instances in AWS.
# The AWS_{project} jobs require the Active Choices plugin, a.k.a uno-choice. and a script work space on the master (sws folder).

template "/var/lib/jenkins/jobs/AWS_#{node[:cidata][:Project]}.xml" do
    source "AWS_job.xml.erb"
    owner "jenkins"
    group "jenkins"
    not_if { File.exists?("var/lib/jenkins/jobs/AWS_#{node[:cidata][:Project]}.xml") }
end

# - Create /var/lib/jenkins/sws folder - for the aws_UI.groovy, used by AWS_{project} jobs.
directory "/var/lib/jenkins/sws" do
   owner 'jenkins'
   group 'jenkins'
end

# - Restart jenkins only if notified of init.groovy updates.
bash 'restart_jenkins' do
 code <<-EOH
    if type systemctl 2>/dev/null; then
       systemctl restart jenkins
    else
       service jenkins restart
    fi
 EOH
 action :nothing
end

# ## Also see:
# - The [AWS UI job](https://incubator2.nps.edu/ciedocs/tools/groovy) at this time will populate the sws folder, requires svn credentials, therefore expect Jenkins to do this for it-self.
# - [Restore Jenkins](https://incubator2.nps.edu/ciedocs/backups) jobs (if given a backup/restore location) YTBD
# - [Add build slaves](https://incubator2.nps.edu/ciedocs/resources/jenkins/nodes), given this instance has credentials for this. YTBD
# - [Credentials in the CIE](https://incubator2.nps.edu/ciedocs/credentials)

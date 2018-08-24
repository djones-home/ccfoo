#md+
# # Cookbook install_jenkins
# Recipe:: default
#
## Copyright (c) 2016 The Authors, All Rights Reserved.
#
# This cookbook installs and configures Jenkins, Sonar, and all peripheral packages needed to 
# run such as postgres and JAVA.
require 'openssl'
require 'net/ssh'
 # YTBD, check that root has a key, ssh-keygen if none
 #bash 'keygen' do
 #   code <<-EOF
 #   ssh-keygen -q -N ""
 #   EOF
 #   not_if { File.exists?('/root/.ssh/id_rsa') }
 #end
 #
 #key = OpenSSL::PKey::RSA.new(File.read("root/.ssh/id_rsa"))
 #
 #private_key = key.to_pem
 #public_key = "#{key.ssh_type} #{[key.to_blob].pack('m0')}"

 # The following override code has no effect.
 # It is being overriden in the roles.

# This recipe sets a few default attributes, however, the intent is to override these in the chef-roles :
# 
# - Set a number of the node["__java__"] variables for the java community cookbook

node.default["java"]["jdk_version"] = "8"
node.default["java"]["set_environment"] = true
node.override["sonarqube"]["version"] = "5.6.1"
node.override["sonarqube"]["checksum"] = "9cb74cd00904e7c804deb3b31158dc8651a41cbe07e9253c53c9b11c9903c9b1"
#node.default["java"]["install_flavor"] = "oracle"
#node.default['java']['oracle']['accept_oracle_download_terms'] = true
#node.default['java']['oracle']['accept_license_agreement'] = true

include_recipe 'java'
include_recipe 'jenkins::master'
include_recipe 'sonarqube'

user 'postgres' do
        comment 'Postgres user'
        home '/var/lib/pgsql'
        shell '/bin/bash'
end

#
# - Install and configure postgres as necessary for Sonar.
#
#

node.default[:fnmoc_ci][:yum][:pgdg] = "https://download.postgresql.org/pub/repos/yum/9.0/redhat/rhel-6-x86_64/pgdg-redhat90-9.0-5.noarch.rpm"
bash "install_pgdg" do
 code <<-EOH
   rpm -i #{node[:fnmoc_ci][:yum][:pgdg]}
 EOH
 not_if { !Dir.glob('/etc/yum.repos.d/pgdg*.repo').empty? }

end

package "postgresql90.x86_64"
package "postgresql90-server"
package "postgresql-libs.x86_64"
package "postgis90.x86_64"
package "proj"
package "jq" do
	options "--enablerepo=epel"
end

package %w{ subversion unzip wget }

#md-
#perl 'configPostgres' do
#        code <<-EOH
#                if (! -e /var/lib/pgsql/9.0/data/pg_hba.conf) {
#                        `runuser -l postgres -c '/usr/pgsql-9.0/bin/initdb -D /var/lib/pgsql/9.0/data'`;
#                       `cp /var/chef/cookbooks/fnmoc_ci/templates/pg_hba.conf /var/lib/pgsql/9.0/data`;
#                       `chown postgres.postgres pg_hba.conf`;
#                        `cp /var/chef/cookbooks/fnmoc_ci/templates/postgresql.conf /var/lib/pgsql/9.0/data`;
#                        `chown postgres.postgres postgresql.conf`;
#                } else {
#                        print "Postgres is already configured\n\n";
#                }
#        EOH
#end

#template '/var/lib/pgsql/9.0/data/pg_hba.conf' do
#   source 'pg_hba.erb'
#   owner 'postgres'
#   group 'postgres'
#   mode 0755
#end


#node.normal['jenkins']['master']['version'] = '2.92'
# Set the private key on the Jenkins executor
#node.run_state[:jenkins_private_key] = private_key
#node.override['jenkins']['executor']['protocol'] = 'http'

#node.override['jenkins']['master']['jvm_options'] = '-Djenkins.install.runSetupWizard=false'


#md+
# - configuring Java ... (again?)
# - OOPs here it is overriding java stuff  (YTBD resovle this potential conflict)

node.override['java']['jdk_version'] = '7'
node.override['java']['install_flavor'] = 'oracle'
node.override['java']['jdk']['7']['x86_64']['url'] = 'http://artifactory.example.com/artifacts/jdk-7u151-linux-x64.tar.gz'
node.override['java']['jdk']['7']['x86_64']['checksum'] = 'The SHA-256 checksum of the JDK archive'
node.override['java']['oracle']['accept_oracle_download_terms'] = true

perl 'copy_jenkins_config' do
        code <<-EOH
                `cp /var/chef/cookbooks/install_jenkins/templates/jenkins /etc/sysconfig`;
        EOH
end


 #
 #service 'jenkins_restart' do 
 #	supports :restart => true
 #	action :enable
 #	subscribes :restart, 'service[jenkins]', :immediately
 #end
 
# - Configure Jenkins...
perl 'updateConfig' do
        code <<-EOH
		sleep 120;
		@config=`cat /var/lib/jenkins/config.xml`;
		open(OUT,">/tmp/config.xml");
		foreach $conf(@config) {
			chomp($conf);
			if (($conf =~ /slaveAgentPort/)&&($conf =~ /-1/)) {
				$conf =~ s/-1/12345/;
			}
##			if (($conf =~ /denyAnonymousReadAccess/)&&($conf =~ /true/)) {
##				$conf =~ s/true/false/;
##			}
##			if (($conf =~ /authorizationStrategy/)&&($conf =~ /FullControlOnceLogged/)) {
##				$conf =~ s/FullControlOnceLoggedInAuthorizationStrategy/AuthorizationStrategy\\$Unsecured/;
##			}
			print OUT "$conf\n";
		}
		close(OUT);
		`cp /tmp/config.xml /var/lib/jenkins`;
		`rm /tmp/config.xml`;
		`touch /tmp/.RESTART_JENKINS`;
        EOH
end

# - Create a root user

perl 'create-root-user' do
        code <<-EOH
		`cd /var/lib/jenkins/users; mkdir root`;
		`cp /var/lib/jenkins/chef-repo/cookbooks/install_jenkins/templates/root_config.xml /var/lib/jenkins/users/root/config.xml; chown -R jenkins.jenkins /var/lib/jenkins/users/root`;
		`touch /tmp/.RESTART_JENKINS`;
        EOH
not_if do ::File.exists?('/var/lib/jenkins/users/root/config.xml') end 
end
execute "restart jenkins" do
        user "root"
        group "root"
        command "service jenkins restart; rm /tmp/.RESTART_JENKINS"
	only_if { File.exists?('/tmp/.RESTART_JENKINS') }
end

perl 'sleep_before_plugins' do
	code <<-EOH
		`whoami`;
		sleep 150;
	EOH
end

# - add plugins...
jenkins_plugin 'audit-trail' 
#jenkins_plugin 'build-pipeline-plugin'
jenkins_plugin 'build-user-vars-plugin'
jenkins_plugin 'backup-interrupt-plugin'
jenkins_plugin 'structs' do
        version '1.10'
end
jenkins_plugin 'mailer' do
        version '1.20'
end

jenkins_plugin 'git-client' do
        version '1.19.0'
end

jenkins_plugin 'ssh-credentials' do
        version '1.12'
end
jenkins_plugin 'token-macro' do
        version '2.0'
end
jenkins_plugin 'icon-shim'
jenkins_plugin 'credentials' do
        version '2.1.11'
end
jenkins_plugin 'cobertura'
jenkins_plugin 'configurationslicing'
#jenkins_plugin 'cucumber'
jenkins_plugin 'uno-choice'
jenkins_plugin 'cucumber-reports'
jenkins_plugin 'cvs'
jenkins_plugin 'groovy'
jenkins_plugin 'javadoc'
jenkins_plugin 'jobConfigHistory'
jenkins_plugin 'job-dsl'
jenkins_plugin 'jquery'
jenkins_plugin 'export-params'
jenkins_plugin 'ldap'
jenkins_plugin 'maven-plugin'
jenkins_plugin 'monitoring'
##jenkins_plugin 'parameterized-trigger'
jenkins_plugin 'performance'
jenkins_plugin 'PrioritySorter'
jenkins_plugin 'repository-connector'
jenkins_plugin 'role-strategy'
jenkins_plugin 'ruby-runtime'
jenkins_plugin 'sitemonitor'
jenkins_plugin 'sonar'
jenkins_plugin 'subversion'
jenkins_plugin 'testlink'
jenkins_plugin 'translation'
jenkins_plugin 'ssh-slaves' do
	version '1.15'
end


perl 'addPrefix' do
	code <<-EOH
		`cp /etc/sysconfig/jenkins /tmp`;
		open(OUT,">>/tmp/jenkins");
		$a = "JENKINS_ARGS=";
		$b = "\\"\\$JENKINS_ARGS";
		$c = " --prefix=";
		$d = "/jenkins\\"";
##		print OUT "JENKINS_ARGS\=\"\$JENKINS_ARGS --prefix=/jenkins\"";
		print OUT "${a}${b} ${c}${d}";
		close(OUT);
		`cp /tmp/jenkins /etc/sysconfig/jenkins`;
		`rm -f /tmp/jenkins`;
	EOH
end


execute "restart jenkins" do
	user "root"
	group "root"
	command "service jenkins restart"
end


sonarqube_plugin 'checkstyle' do
	version '2.4'
end

sonarqube_plugin 'java' do
  version '4.2'
end

sonarqube_plugin 'javascript' do
  version '2.16.0.2922'
end


#sonarqube_plugin 'pmd' do
##	version '2.5'
#end

#sonarqube_plugin 'findbugs' do
##	version '3.3'
#end

sonarqube_plugin 'scm-svn' do
  version '1.3'
end


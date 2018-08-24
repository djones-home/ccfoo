#md+
# This chef recipe sets up the app(deployment) server with JBoss.  It deploys the necessary artifacts from Nexus and updates the GIS database for use by the NITES-Next team.
#
include_recipe 'java'


# - Create linux user jenkins.
user 'jenkins' do
        comment 'Jenkins user'
        home '/var/lib/jenkins'
        shell '/bin/bash'
end

# - Configures yum with soft certs and sets up the necessary repos.
#
cookbook_file '/etc/yum.repos.d/nexus.repo' do
   mode '0600'
   owner 'root'
end

cookbook_file '/etc/yum.repos.d/mrepo_ern.repo' do
   mode '0600'
   owner 'root'
end

## Deprecated yum.conf install
## This is changing global ssl* settings, which instead could be done on the sepecific repos in need (ern and nexus).
## If we do this, then we need to maintain 
##  - (multipe) platform specific copies (rhel-7.2.., centos-6.., centos-7, ...)
##  - including changing other repos  that assume sslverify is (globally) off, for each platform
### From /var/log/cloud-init-output.log:
##  - update content in file /etc/yum.conf from 9fab17 to da6bca
##    --- /etc/yum.conf	2017-03-22 05:32:26.000000000 +0000
##    +++ /etc/.chef-yum20180413-1564-188utr5.conf	2018-04-13 17:11:14.240000003 +0000
##    @@ -23,4 +23,8 @@
##     
##     # PUT YOUR REPOS HERE OR IN separate files named file.repo
##     # in /etc/yum.repos.d
##    +sslcacert=/etc/pki/tls/certs/dod-root-certs.pem
##    +sslverify=1
##    +sslclientcert=/var/lib/yum/client.cert
##    +sslclientkey=/var/lib/yum/client.key
###
## Do not install this, today, due to resulting  work elsewhere.
## cookbook_file '/etc/yum.conf' do
##    mode '0600'
##    owner 'root'
## end

cookbook_file '/etc/pki/tls/certs/dod-root-certs.pem' do
   mode '0644'
   owner 'root'
end

### If the distro already has the repo, this should not overwrite it, - the added action will guard that.
## The eprl repo not enabled, by default; the 'package' resource can still use it with:
##  options "--enablerepo=epel "
## 
cookbook_file '/etc/yum.repos.d/epel.repo' do
   mode '0600'
   owner 'root'
   action :create_if_missing
end

## Deprecated:
## The pgdg-centos95-9.5-3.noarch.rpm will overwite this when it installs.
## It provides not only the repo but the GPG key install also. 
## Is this needed? No, it can be easily avoid. The only difference from the rpm repo file is the sslverify :
## [root@ip-10-130-20-7 tmp]# diff /etc/yum.repos.d/pgdg-95-centos.repo ./etc/yum.repos.d/pgdg-95-centos.repo
## 7d6
## < sslverify=0
## That is just undoing the setting that were changed in /etc/yum.conf (global changes) needed only ern and nexus repos.
## So the alternative is to leave the yum.conf with the defaults, and just setup ssl-params locally in the ern and nexus repo stanzas.
## 
##cookbook_file '/etc/yum.repos.d/pgdg-95-centos.repo' do
##   mode '0600'
##   owner 'root'
##end

##
## Either  pull the rpm from a known location (S3, mrepo)  or discover how to ask chef where this is, or
## parhap (later)  add this to  our mrepo , 
## Today, using S3:
# - Install pgdg repo conf and GPG key from S3 common store
commonStore = "#{node['cidata']['s3Store']}/common"
tmpdir = Chef::Config['file_cache_path']
rpm = "pgdg-centos95-9.5-3.noarch.rpm"
bash 'pgdg-repo-install' do
    code <<-EOH
    aws s3 cp #{commonStore}/#{rpm} #{tmpdir}/ &&
    rpm -i -p #{tmpdir}/#{rpm} && rm #{tmpdir}/#{rpm}
    EOH
    not_if { File.exists?("/etc/pki/rpm-gpg/RPM-GPG-KEY-PGDG-95") }
end
##

# - Installs client.cert from cookbook files
cookbook_file '/var/lib/yum/client.cert' do
   mode '0600'
   owner 'root'
end
 
# - Installs client.key from SSM secure parameter store
file '/var/lib/yum/client.key' do
   mode '0600'
   owner 'root'
   content  `aws ssm get-parameter --name /#{node[:cidata][:Project]}/certs/cert.key --w --query Parameter.Value --out text`
end		

# - Installs and configures postgres for the GIS database to be used by JBoss
package  'postgresql95-server.x86_64' do
   notifies :run, 'perl[initdb_postgres]', :immediate
end

# - Packages:  postgis, gdal, proj, jq, lsof
%w{ 
   postgis24_95.x86_64
   gdal.x86_64
   gdal-devel
   gdal-python
   proj-devel
   jq
   lsof
 }.each  do |pkg|
  package pkg do
    options "--enablerepo=epel "
  end
end


## Deprecated:
## Replaced the following with "service NAME initdb" in 'perl[initdb_postgres]', above.
##perl 'configPostgres' do
##	code <<-EOH
##		if (! -e /var/lib/pgsql/9.5/data/pg_hba.conf) { 
##			`runuser -l postgres -c '/usr/pgsql-9.5/bin/initdb -D /var/lib/pgsql/9.5/data'`;
##		} else {
##			print "Postgres is already configured\n\n";
##		}
##	EOH
##end


# - Start newly installed postgre
perl 'initdb_postgres' do
	code <<-EOH
		`chkconfig postgresql-9.5 on`;
		`service postgresql-9.5 initdb`;
	EOH
   action :nothing
   notifies :run, 'bash[restart_postgres]', :delayed
end

## dbinit would  not run with postgresql.conf and pg_hba.conf files installed, 
## so moved run dbinit before, have these  trigger restart

cookbook_file '/var/lib/pgsql/9.5/data/postgresql.conf' do
   mode '0755'
   owner 'postgres'
   group 'postgres'
   notifies :run, 'bash[restart_postgres]', :delayed
end

template '/var/lib/pgsql/9.5/data/pg_hba.conf' do
   source 'pg_hba.erb'
   owner 'postgres'
   group 'postgres'
   mode 0755
   notifies :run, 'bash[restart_postgres]', :delayed
end

bash 'restart_postgres' do
    code "service postgresql-9.5 restart"
    action :nothing
end

bash 'start_postgres' do
    code "service postgresql-9.5 start"
    action :nothing
end

# - Setup Maven for use, when /opt/maven does not exists.
perl 'copy_maven' do
	code <<-EOH
		`aws s3 cp s3://cibootstrap/common/apache-maven-3.3.9-bin.tar.gz /opt/apache-maven-3.3.9-bin.tar.gz`;
		`cd /opt; gunzip apache-maven-3.3.9-bin.tar.gz; tar xvf apache-maven-3.3.9-bin.tar`;
		`ln -s  /opt/apache-maven-3.3.9 /opt/maven`;
	EOH
    not_if { File.exists?("/opt/maven") }
end
#md-

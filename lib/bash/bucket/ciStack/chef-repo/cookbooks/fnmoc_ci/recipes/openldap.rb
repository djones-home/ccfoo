#md+ bashDoc to transform into markdown
###
# ## Install OpenLDAP service.
#
#  1. Install servers, clients, and doc packages
#  2. Set the admin password
#  3. Import schemas
#  4. Set the domain for the LDAP user DB
#  5. Add firewall rules to allow LDAP services
#  6. Load user DB
#

#
# ### Node["openldap"][ _variables_ ]:
#

require "base64"
# -  __basedn__   LDAP context root, i.e. dc=example,dc=com
#node.default["openldap"]["basedn"] = "dc=ccs,dc=nps,dc=edu"
node.default["openldap"]["basedn"] = "dc=exrn,dc=nps,dc=edu"
# -  __PW_FILE__   file to store a new random-generated password, default: /root/pw{time}
node.default["openldap"]["PW_FILE"] = "/root/pw#{Time.now.to_i}"
`touch #{node["openldap"]["PW_FILE"]}`
`chmod 600 #{node["openldap"]["PW_FILE"]}`
File.open( node["openldap"]["PW_FILE"], 'w') {|file| file.write( Base64.encode64(Random.srand.to_s)[0,31]) }
# -  __certFile__     Path to certificate
node.default["openldap"]["certFile"] = "/etc/openldap/certs/cert.pem"
# -  __certKey__    Path to key for x509 certificate
node.default["openldap"]["certKey"] = "/etc/openldap/certs/priv.pem"
## -  openssh-schema   Path to schema for sshPublicKey attribute
# -   __LDIF__         Path to an ldif of the user DB, default: "s3://cibootstrap/ldap/cie.ldif"
node.default["openldap"]["LDIF"] = "s3://cibootstrap/ldap/cie.ldif"

#
# ### Packages
#

# - Install clients package, install notifies bash resource scripts to setup system ldap.conf.
package %w{ openldap-clients openldap-devel  } do
  notifies :run, 'bash[openldap_client_configuration]'
end


# - Install servers and openldap-devel for the addtional docs, notifies bash resource scripts if servers package is installed.
# - Install openssh-ldap,  as reference for ssh pubic key schema and  How-to-doc.
# - Use a modify openssh-ldap schema (cookbook file), to allow LDAP entry creation with or without an SSH-public-key attribute.
package %w{ openldap-servers openssh-ldap } do
  notifies :run, 'bash[ldap_firewall_rules]'
  notifies :run, 'bash[openldap_servers_init]'
  notifies :run, 'bash[openldap_schema]'
  notifies :run, 'bash[openldap_changes]'
  notifies :run, 'bash[openldap_base]'
  notifies :run, 'bash[openldap_load]'
end

### YTBD put the sssd setup to another recipe, that all clients run
### - Install client authentication packages for LDAP client to use SSSD
##package %w{ sssd sssd-client } do
##  notifies :run, 'bash[ldap_sssd_client_configuration]'
##end
#
# ### Templates
#

# - The changes.ldif will configure the user db domain, RootPW, RootDN, suffix
template '/etc/openldap/changes.ldif' do
   action :nothing
   source 'changes.ldif.erb'
   variables( lazy { { rootPW:  File.read(node['openldap']['PW_FILE']), 
                       certFile:  node['openldap']['certFile'],
                       certKey:  node['openldap']['certKey'],
                       basedn:  node['openldap']['basedn'] 
                     } })
end

# - The base.ldif will create enties in the user db for domain, people, and groups
template '/etc/openldap/base.ldif' do
   action :nothing
   source 'base.ldif.erb'
   variables( lazy { { rootPW: File.read(node['openldap']['PW_FILE']), basedn:  node['openldap']['basedn'] } })
end

# ### Cookbook file installs
# 
# - Install openldap/schema/ad.[schema,ldif] files, used to extend/supliment inetorgperson with AD-like attributes.
# 
%w{ ad.schema ad.ldif openssh-lpk-openldap.ldif }.each { |file |
   cookbook_file "/etc/openldap/schema/#{file}" do
      source file
      owner 'ldap'
      group 'ldap'
      mode '0644'
      action :create
  end
}

# - Install filter_ldif script from cookbook file.
cookbook_file "/etc/openldap/ldapLoad.rb" do
      owner 'ldap'
      group 'ldap'
      mode '0755'
      action :create
end

# ###  Resource scripts  
#
# Bash resource scripts do the setup work, and utilize LDIF tamplates.
#
# - Configure ldap.conf
bash 'openldap_client_configuration' do
 code <<-EOH
   sed -i 's/^.*BASE.*/BASE #{node['openldap']['basedn']}/' /etc/openldap/ldap.conf
   sed -i 's%^.*URI.*%URI ldap://localhost%' /etc/openldap/ldap.conf
 EOH
 action :nothing
end

# - Create a private key, /etc/openldap/certs/priv.pem
# - Create a certificate, /etc/openldap/certs/cert.pem
# - NOTE: the cert file/key needs work: path should be move to a variable in the future, for one source
# - Add ldap.log to rsyslog, if needed
# - Start slapd
bash 'openldap_servers_init' do
 code <<-EOH
   cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
   chown ldap  /var/lib/ldap/DB_CONFIG
   touch /etc/openldap/passwd
   chmod 600 /etc/openldap/passwd
   openssl req -new -x509 -nodes -out #{node['openldap']['certFile']} \
      -keyout #{node['openldap']['certKey']} -days 3650 -subj /O=Navy/OU=fnmoc_ci/CN=ldap.#{node['openldap']['basedn']}
   chown ldap:ldap #{node['openldap']['certFile']} #{node['openldap']['certKey']}
   chmod 600 #{node['openldap']['certKey']}
   grep -q ldap.log /etc/rsyslog.conf ||  { echo 'local4.* /var/log/ldap.log' >> /etc/rsyslog.conf; systemctl restart rsyslog; }
   # slaptest #{node["openldap"]["basedn"]}
   systemctl start slapd
   systemctl enable slapd
   sleep 5
   # list the initial set of dn:olcDatabases entries, from the first (config) DB. (frontend, config, monitor, hdb|bdb):
   ldapsearch  -Q -Y EXTERNAL -H ldapi:/// -LLL -b cn=config olcDatabase=\* dn
 EOH
 action :nothing
end


# - Add the basic three schema: cosine, nis, and inetorgpreson
# - Adding schema, notifies creation of changes and base LDIF files from templates
bash 'openldap_schema' do
 #  ldapadd -Y EXTERNAL -H ldapi:/// -D "cn=config" -f chrootd.ldif
 # Why the -D ????
 code <<-EOH
   ldapadd -Q -Y EXTERNAL -H ldapi:/// -D "cn=config" -f /etc/openldap/schema/cosine.ldif
   ldapadd -Q -Y EXTERNAL -H ldapi:/// -D "cn=config" -f /etc/openldap/schema/nis.ldif 
   ldapadd -Q -Y EXTERNAL -H ldapi:/// -D "cn=config" -f /etc/openldap/schema/inetorgperson.ldif 
   ldapadd -Q -Y EXTERNAL -H ldapi:/// -D "cn=config" -f /etc/openldap/schema/ad.ldif 
   ldapadd -Q -Y EXTERNAL -H ldapi:/// -D "cn=config" -f /etc/openldap/schema/openssh-lpk-openldap.ldif
 EOH
  action :nothing
  notifies :create, 'template[/etc/openldap/changes.ldif]', :immediate
  notifies :create, 'template[/etc/openldap/base.ldif]', :immediate
end


bash 'openldap_changes' do
 code <<-EOH
   #ldapmodify -Y EXTERNAL -H ldapi:/// -D "cn=config" -f /etc/openldap/changes.ldif
   ldapmodify -Y EXTERNAL -H ldapi:///  -f /etc/openldap/changes.ldif
 EOH
 action :nothing
end

# - Create the top or base object for user data, and OUs under it for Groups and People
bash 'openldap_base' do
 code <<-EOH
   ldapadd -x -w #{File.read(node['openldap']['PW_FILE'])} -H ldapi:/// -D "cn=Manager,#{node['openldap']['basedn']}" -f /etc/openldap/base.ldif
 EOH
 action :nothing
end

# - Install host-firewall rules.
#    - SELinux at this time, does not allow cloud-init run_cmds to use firewall-cmd, they just hang, on CentOS7, either add policy, or turn off enforce.

bash 'ldap_firewall_rules' do
 code <<-EOH
   setenforce Permissive
   firewall-cmd --list-all
   firewall-cmd --permanent --add-service=ldap
   firewall-cmd --permanent --add-service=ldaps
   firewall-cmd --reload
   firewall-cmd --list-all
   setenforce Enforcing
  EOH
   action :nothing
end

# - Load LDAP user data
#   - Get the ldif from S3
#   - Install net-ldap gem
#   - Run loadLdap.rb
bash 'openldap_load' do
 code <<-EOH
   cd /root/
   aws s3 cp #{node['openldap']['LDIF']} ldap.ldif
   gem list --local | grep -q ^net-ldap || gem install net-ldap 
   export LDAPBASE=#{node["openldap"]["basedn"]}
   export LDAPPW="#{File.read(node['openldap']['PW_FILE'])}"
   export LDAPBINDDN="cn=Manager,#{node['openldap']['basedn']}"
   /etc/openldap/ldapLoad.rb ldap.ldif 
  EOH
   action :nothing
end

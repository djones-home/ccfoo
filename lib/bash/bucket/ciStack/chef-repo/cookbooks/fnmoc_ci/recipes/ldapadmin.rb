###
# Install LDAPadmin  service
# - phpldapadmin from EPEL 
#   - Install apache as a dependency, with  "require local" on  the context roots /ldapadmin and /phpldapadmin,
#   for security.  Use ssh -L to tunnel back to your admin work station to use ldapadmin.
## - migrationtools.noarch : Migration scripts for LDAP, where are these ?

yum_package %w{ phpldapadmin } do
  options "--enablerepo=epel"
  notifies :run, 'bash[ldapadmin_init]'
end

bash 'ldapadmin_init' do
 code <<-EOH
   sed -i 's/^.*BASE.*/BASE #{node['openldap']['basedn']}/' /etc/openldap/ldap.conf
   sed -i 's%^.*URI.*%URI ldap://localhost%' /etc/openldap/ldap.conf
   systemctl start httpd
   systemctl enable httpd
 EOH
 action :nothing
end




puts "nexus: Hello World"
#md+ bashDoc to transform into markdown
###
# ## Install Nexus service.
#
#  1. Install servers, clients, and doc packages
#

#
# ### Node["nexus"][ _variables_ ]:
#

###
#
#

# -  __basedn__   LDAP context root, i.e. dc=example,dc=com
#node.default["ldap"]["basedn"] = "dc=ccs,dc=nps,dc=edu"
node.default["ldap"]["basedn"] = "dc=exern,dc=nps,dc=edu"
node.default["ldap"]["URI"] = "ldap://10.0.20.4"
# -  __PW__      administrative password, defaults to "redhat"
node.default["nexus"]["downloadURL"] = "http://download.sonatype.com/nexus/3/latest-unix.tar.gz"

package "openldap-clients" do
  notifies :run, 'bash[openldap_ldap_conf]'
end

bash "openldap_ldap_conf" do
 code <<-EOH
   sed -i 's/^.*BASE.*/BASE #{node['ldap']['basedn']}/' /etc/openldap/ldap.conf
   sed -i 's%^.*URI.*%URI #{node['ldap']['URI']}%' /etc/openldap/ldap.conf
   ldapsearch -x objectClass=domain | grep -i ^dn: || exit 1
 EOH
 action :nothing
end

bash "install_nexus" do
 code <<-EOH
   curl --silent  ${node[:nexus][:downloadURL]}
 EOH
 action :nothing
end

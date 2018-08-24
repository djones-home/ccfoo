#md-
# deprecated: data, with the default chef environment, providing node[:cidata]. At one time this recipe parsed ENV["CIDATA"], as follows:
# data = JSON.parse(File.read(ENV["CIDATA"] ))
# data.merge! = JSON.parse(File.read("/root/custom.json"))
#
# deprecated data["Name"]: replaced by node[:vhostname] which is set by include recipe common.
# data = { "Name" => "incubator2" }
#require "pry" if $stdout.tty?
#binding.pry if $stdout.tty?

#md+
# ## Http-gateway configuration
# 
# This script builds the httpd reverse-proxy configuration on the https-gateway.
# The catalog of vhosts (today) is kept in  ciData/ciStack.json under .Endpoints.Vhosts.
# 
# - Includes on the fnmoc_ci::common recipe
# - Recipe common should set node[:vhostname] to a fqhn (public name)
include_recipe "fnmoc_ci::common" 

# - Insure the packages are installed for  jq, httpd, wget, mod_ssl, ... 
package %w( wget jq httpd mod_ssl )  do
 options "--enablerepo=epel "
end

## /^7/ =~ node['platform_version']
# - Set node[:SSL] key/values that correspond to apache httpd SSL dirctives (for use in templates).
node.default[:SSL]['CipherSuite'] = 'HIGH:MEDIUM:!aNULL:!MD5:!SEED:!IDEA'
node.default[:SSL]['CertificateKeyFile'] = "/etc/pki/tls/private/#{node[:vhostname].split('.')[0]}.key"
node.default[:SSL]['CACertificateFile'] = "/etc/pki/tls/certs/dod-root-certs.pem"
node.default[:SSL]['CADNRequestFile'] = "/etc/pki/tls/certs/acceptableCAs"
node.default[:SSL]['CertificateFile'] = "/etc/pki/tls/certs/#{node[:vhostname].split('.')[0]}.crt"

directory '/etc/pki/tls/private' do
  owner 'root'
  group 'root'
  mode '0600'
end

# - Optionally install SSL Certificate Files, if they exists as cookbook_files.
# - Private Key files should NOT be in the cookbook, and are intentionally excluded to keep out of SCMa, - place by another means.
node[:SSL].keys.grep(/.*File$/).each { |k|
   n = File.basename( node[:SSL][k] )
   cookbook_file node[:SSL][k] do
      mode '0440'
      owner 'root'
      group 'root'
      only_if { run_context.has_cookbook_file_in_cookbook?(cookbook_name, "#{n}") }
   end
}
# - Optionally install conf/httpd.conf, if a template exists for "#{node[:vhostname]}_httpd.conf.erb"
template '/etc/httpd/conf/httpd.conf' do
  source "#{node[:vhostname].split('.')[0]}_httpd.conf.erb"
#  ignore_failure true
   only_if { run_context.has_template_in_cookbook?(cookbook_name, "#{node[:vhostname].split('.')[0]}_httpd.conf.erb") }
end

# - Optionally install conf.d/ssl.conf, if a template exists for "#{node[:vhostname]}_ssl.conf.erb"
template '/etc/httpd/conf.d/ssl.conf' do
   source "#{node[:vhostname].split('.')[0]}_ssl.conf.erb"
   mode '0440'
   owner 'root'
   group 'root'
 # the bindings include the variables parameter as shown in this example , and the node
   variables( {
     "data" => node[:cidata]
   })
   only_if { run_context.has_template_in_cookbook?(cookbook_name, "#{node[:vhostname].split('.')[0]}_ssl.conf.erb") }
end

# - Install vhost_all.conf, to redirect http to https.
file '/etc/httpd/conf.d/vhost_all.conf' do
  content <<-EOH
<VirtualHost *:80>
    ServerAdmin  webmaster@localhost
   RewriteEngine On
   RewriteRule ^(.*)$ https://%{HTTP_HOST}$1 [R=301,L,NC]
</VirtualHost>
  EOH
   notifies :run, "bash[restart_httpd]", :delayed
end

# selinux settings to allow forwarding, which allows scripts and modules (i.e. mod_proxy) to connect to the network.
if (`getsebool httpd_can_network_connect`.strip.split[-1] == "off")
   bash 'selinux_httpd' do
     code "setsebool -P httpd_can_network_connect 1"
   end
end

# restart httpd on configuration change
if ( /^7/ =~ node['platform_version'] )
    bash 'restart_httpd' do
      code "systemctl restart httpd"
      action :nothing
    end
else
    bash 'restart_httpd' do
      code "service httpd restart"
      action :nothing
    end
end
#md-
# - Install userdir.conf, to disable UserDir.
# This is default of Apache 2.4 - commenting it out, use the default
#file '/etc/httpd/conf.d/userdir.conf' do
#  content <<-EOH
#<IfModule mod_userdir.c>
#    UserDir disabled
#</IfModule>
#<Directory "/home/*/public_html">
#    AllowOverride FileInfo AuthConfig Limit Indexes
#    Options MultiViews Indexes SymLinksIfOwnerMatch IncludesNoExec
#    Require method GET POST OPTIONS
#</Directory>
#  EOH
#end
#md+

# Filter EC2 descibe-instances JSON output, for constucting the reverse-proxy (proxyPass) directives in Apache configuration files.
# Only instances with Keys of "AppContexts", "Name", and "Project" in the VM Instance Tags are concidered.
# To keep it simple, a short list of app contexts can given in the tag. Tags are limited to 255 characters. Longer list
# must be taken from a document,  in this case the URL or ARN should be given for a document.
## common.rb should ensure that the aws configuration has a region  
json = JSON.parse( `aws ec2 describe-instances`)["Reservations"].map{|h| h['Instances']}.flatten.select{|i| i.has_key?("Tags") && 
   i["Tags"].any?{|t| t['Key'] == "AppContexts"} &&
   i["Tags"].any?{|t| t['Key'] == "Name"} &&
   i["Tags"].any?{|t| t['Key'] == "Project"} 
  }

# Template a conf file for each vhost (YTBD: Certificate check for proper subject or SANs entry).
# - Assignment of Virtual-host name is by cidata.Endpoints.Vhosts.{Project}:{InstanceName}.
# - ProxyPass options will default to "nocanon", unless another is given for the AppContext.
proxyPassOpt = { :default => "nocanon" }
# - ProxyPass host-port will default 8080, in the future a proxyPassPort hash could be added it this veries to more ports.
# - ProxyPass forwarding protocol  will default http, in the future a proxyPassProto hash could be added it this veries to ajp or https.
lines = {}
node[:cidata]["Endpoints"]["Vhosts"].values.sort.uniq.each { |vhostname|
  shortName = vhostname.split(".")[0]
  lines[vhostname] = []
  node[:cidata]["Endpoints"]["Vhosts"].select{|k,v| v == vhostname && k =~ /:/}.map{ |k, v| 
      project = k.split(":")[0]
      instanceNm = k.split(":")[1]
      ijson = json.select{|i|
          i["Tags"].any?{|t| t['Key'] == "Name" && t['Value'] == instanceNm } &&
          i["Tags"].any?{|t| t['Key'] == "Project" && t['Value'] == project } }[0]

     next unless ijson
     # replace  URLs (YTBD), list of contexts document
     hostname = ijson["PrivateDnsName"]
     apps = ijson["Tags"].select{|h| h["Key"] == "AppContexts"}[0]["Value"]
     lines[vhostname] << "##   #{hostname} #{ijson["InstanceId"]} #{project} #{instanceNm} #{apps} "
     apps.split(/\s+/).map{ |s| s.sub(/^\//,"").sub(/\/$/,"") }.sort.each { |context|
       port = "8080"
       proto = "http"
       options = proxyPassOpt.has_key?(context) ? proxyPassOpt[context] : proxyPassOpt[:default]
       # in the template a loop, adds each line, made from the app-context, hostname, port, protocol, and option.
       lines[vhostname] << "ProxyPass /#{context} #{proto}://#{hostname}:#{port}/#{context}  #{options}"
       lines[vhostname] << "ProxyPassReverse  /#{context} http://#{hostname}:#{port}/#{context}"
       lines[vhostname] << "ProxyPassReverse  /#{context} http://#{vhostname}:#{port}/#{context}"
     }
  }
  template "/etc/httpd/conf.d/vhost_#{shortName}.conf" do
         source 'vhost_NAME.conf.erb'
         mode '0440'
         owner 'root'
         group 'root'
         variables({
             "serverName" => vhostname,
             "shortName"   => shortName,
             "proxyPassLines"   => lines[vhostname]
         })
       only_if { run_context.has_template_in_cookbook?(cookbook_name, "vhost_NAME.conf.erb") }
       notifies :run, "bash[restart_httpd]", :delayed
  end
}

#md+ This marks this file as having embedded Markdown, for the cookbookDoc function  
#  ### A recipe to provision a proxy InstanceRole
#
# You should replace this a with useful description of how a __proxy__ is provisioned.
# 
# Workflow: 
# 
#  - Interesting step
#  - Anonther interesting step in the setup
#
# Also See: [CIE Docs](https://incubator2.nps.edu/)
#
#md-  block  parsing comments for MD until the next #md+ commnet line.

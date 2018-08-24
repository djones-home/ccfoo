puts "dns: Hello World"

package %w{ bind bin-utils }

#chef (12.12.15)> node.keys.grep /pack/
# => ["chef_packages", "init_package", "packages"] 

instances = `aws ec2 describe-instances`

# my template variables, in addtion to "node" 
zones = { 
  "metnet.navy.mil" => "10.50.10.0/24",
  "app.local" => "10.50.10.0/24",
  "db.local" => "10.50.20.0/24",
  "web.local" => "10.50.30.0/24"
}

pivateIPs = {
}

publicIPs = {
}

# template the options: listen-on, allow-query, allow-transfer, SIG, SEC keys
# template zone statements for forward and reverse lookup of domain
template "/etc/named.conf" do
  source "named.conf.erb"
  owner 'root'
  group 'root'
  mode 0755
  notifies :restart, "serivce[named]"
  variables vars: { "zones" => zones }
end


zones.each_pair { | name, cidr |
  # Create forward Zone files
  template "/var/named/forward.#{name}" do
    source "forward.zone.erb"
    owner 'root'
    group 'root'
    mode 0755
    action :create_if_missing
    notifies :restart, "serivce[named]"
    variables vars: { "name" => name, "cidr" => cidr }
  end

  # Create reverse Zone files
  template "/var/named/reverse.#{name}" do
    source "reverse.zone.erb"
    owner 'root'
    group 'root'
    mode 0755
    action :create_if_missing
    notifies :restart, "serivce[named]"
    variables vars: { "name" => name, "cidr" => cidr }
  end
}


# Enable, and start named service, if notified (by bind package install)
service 'named' do
  action :nothing
  subscribes :enable, "yum_package[bind]"
  subscribes :start, "yum_package[bind]"
end

# Configure host firewall, before named service, when change of service state.
bash 'firewall_dns' do
  code <<-EOH
     firewall-cmd --permanent --add-port 53/tcp
     firewall-cmd --permanent --add-port 53/udp
     firewall-cmd --reload
  EOH
  action :nothing
  subscribes :run, 'service[named]', :before
end

# Permissions, Ownership, and SELinux
bash 'named_conf_attr' do
 code <<-EOH
    chgrp named -R /var/named
    chown -v root:named /etc/named.conf
    restorecon -rv /var/named
    restorecon /etc/named.conf
  EOH
  subscribes :run, 'service[named]', :before
  action :nothing
end


bash 'TestDNS' do
 code <<-EOH
  named-checkconf /etc/named.conf
  named-checkzone metnet.navy.mil /var/named/forward.metnet.navy.mil
  named-checkzone metnet.navy.mil /var/named/reverse.metnet.navy.mil
  dig masterdns.metnet.navy.mil
  EOH
  subscribes :run, 'service[named]', :before
  action :nothing
end

# Add DNS=ServerIp in network-scripts/ifcfg-* files
# adn nameserver to /etc/resolv.conf
# systemclt restart network
# setup  TSIG or SIG(0)
# setup  DNSSEC
# remove root.hints from the autoritative server to prevent recursion.
# 


w ../templates/default/named.conf.erb
w ../templates/default/forwardZone.erb
w ../templates/default/reverseZone.erb
$TTL 86400
@   IN  SOA     masterdns.unixmen.local. root.unixmen.local. (
        2011071001  ;Serial
        3600        ;Refresh
        1800        ;Retry
        604800      ;Expire
        86400       ;Minimum TTL
)
@       IN  NS          masterdns.unixmen.local.
@       IN  NS          secondarydns.unixmen.local.
@       IN  A           192.168.1.101
@       IN  A           192.168.1.102
@       IN  A           192.168.1.103
masterdns       IN  A   192.168.1.101
secondarydns    IN  A   192.168.1.102
client          IN  A   192.168.1.103

w ../templates/default/reverse.metnet.navy.mil.erb
$TTL 86400
<% masterdns = "foobar"
   domain = "my.domain"
   serialNo = `date +%Y%m%d%H%M`
%>
@   IN  SOA    <%= "#{masterdns}.#{domain}. root.#{domain}."%> (
        <%= serialNo %> ;Serial
        3600        ;Refresh
        1800        ;Retry
        604800      ;Expire
        86400       ;Minimum TTL
)
@       IN  NS          <%= "#{masterdns}.#{domain}."%>
@       IN  NS          <%= "#{secondarydns}.#{domain}."%>
@       IN  PTR         <%= "#{domain}."%>
<%= masterdns %>       IN  A   192.168.1.101
<%= secondarydns %>    IN  A   192.168.1.102
client          IN  A   192.168.1.103
101     IN  PTR         masterdns.unixmen.local.
102     IN  PTR         secondarydns.unixmen.local.
103     IN  PTR         client.unixmen.local.


# for the secondary servers, configure zone master, and security
yum_package bind bind-utils
named.conf option listen-on to secondarydns, allow-query, and the zone files

listen-on port 53 { 127.0.0.1; 192.168.1.102; };
allow-query     { localhost; 192.168.1.0/24; };


zone "unixmen.local" IN {
type slave;
file "slaves/unixmen.fwd";
masters { 192.168.1.101; };
};
zone "1.168.192.in-addr.arpa" IN {
type slave;
file "slaves/unixmen.rev";
masters { 192.168.1.101; };
};



# STIGs
# zone transfer protection, integrety of zone transfers by signing TSIG or SIG(0)
# DNSSEC on authoritative server, create ZSK, and KSK, registered KSK as the zone Delegation Signer DS
# setup key rollover
# setup syslog and audit for DNS events, priviledged access, login..
# centrial logging - forward syslogs, including  dns audit events

# derived from db-ks.cfg

# YTBD grow and mount filesytems as needed: home 2G, root 4G, /opt/McAfee 2G
#/tmp 500 2G <<<<<
#/opt/McAfee xx 2G <<<<<<<<<
#/home 2G
#/var/log/rsyslog 5G
#/var/lib/pgsql 4G


bash 'stage2_common-config.cfg' do

end

bash 'stage2_common-disks.cfg' do

end

bash 'stage2_common-packages.cfg' do
packages %w{ postgresql90-contrib
postgresql90-docs
postgresql90-devel
postgis90
postgis90-utils
postgis90-docs
postgresql90-server
unixODBC }


end
bash 'db-ks.cfg' do
 command <<-EOH
 usermod -Z guest_u postgres
 echo db > /opt/node
 chmod 444 /opt/node
 
 EOH
end


bash 'stage2_common-postinstall.cfg' do

end


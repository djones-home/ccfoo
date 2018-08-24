## djones: see my notes: ~/logs/1636w/workNotes.6964 for WIP.
# Original scripts a user-data deployment of GateOne and gauc derived from  
# http://thjones2.blogspot.com/2015/03/so-you-dont-want-to-byol.html

bash GateOne do
  code <<-EOH
  yum update -y
  yum install -y git
  pip install --upgrade pip
  pip install --upgrade tornado
  git clone https://github.com/liftoff/GateOne.git /tmp/GateOne
  (cd /tmp/GateOne ; python setup.py install)
  chkconfig gateone on
  service gateone start
  printf "Sleeping for 15s..."
  sleep 15
  echo "Done!"
  pkill gateone
  # default configuration of GateOne only allows LAN connections
  # set "origins" to "*", disable anonymouns logins, by setting it to "pam" to allow local users credentials
  sed -i -e '/"https_redirect"/s/: .*$/: true,/' \
      -e '/"origins":/s/:.*$/: ["*"],/' \
      $(readlink -f /etc/gateone/conf.d/10server.conf)
  sed -i '/"auth"/s/: .*$/: "pam",/' \
    $(readlink -f /etc/gateone/conf.d/20authentication.conf)
  service gateone restart
  EOH
  not_if { File.exists?("/etc/gateone/") }
end

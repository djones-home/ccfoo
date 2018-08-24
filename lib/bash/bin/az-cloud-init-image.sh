#!/bin/bash
### get one of the pubkey from my smartcard
pubkey=$(ssh-keygen -D $PKCS11 | head -1 )
# Pick an image, run:   az vm image list --offer CentOS --all --output table
# I pick this Centos-7 image because it has LVM
# The is alreadu a cloud-init instance (w/o LVM) :
#  OpenLogic:CentOS-CI:7-CI:7.4.20180124  is has Cloudinit.
image=OpenLogic:CentOS-LVM:7-LVM:7.5.20180524
rg=foobar
imageName="Centos7-cloud-init"

get_name_index() {
  local -i i
  local name="$1" json="$2" n
  i=0; n=$(echo $json | jq -r '.[].name' | sed -n s/^"${name}.*-"'\([0-9]*\)$/\1/p' | sort -n | tail -1)
  [ -n "$n" ] && let i+=$n && let i+=1
  name+="-$i"
  echo $name
}
json=$(az vm list)
vmName=ci-el7
vmName=$(get_name_index $vmName "$json")

json=$(az vm create --resource-group $rg --name el7-1 --image $image  --ssh-key-value "$pubkey" --admin-username $USER --size Standard_A2)
ip=$(echo $json | jq -r .publicIpAddress)

# Reference: 
# https://docs.microsoft.com/en-us/azure/virtual-machines/linux/cloudinit-prepare-custom-image


cat >setup-cloud-init.sh <<EOF
#!/bin/bash
echo  add the cloud-init package, gdisk 
yum install -y cloud-init gdisk

echo  disable waagent provisioning
sed -i 's/Provisioning.Enabled=y/Provisioning.Enabled=n/g' /etc/waagent.conf
sed -i 's/Provisioning.UseCloudInit=n/Provisioning.UseCloudInit=y/g' /etc/waagent.conf
echo  disable waagent ResourceDisk format and swap management
sed -i 's/ResourceDisk.Format=y/ResourceDisk.Format=n/g' /etc/waagent.conf
sed -i 's/ResourceDisk.EnableSwap=y/ResourceDisk.EnableSwap=n/g' /etc/waagent.conf

echo Install work-around for hostname setup issues: 
echo    1.  /etc/cloud/cloud.cfg.d/91-azrure_datasource.cfg
echo '# This configuration file is provided by the WALinuxAgent package.' > /etc/cloud/cloud.cfg.d/91-azure_datasource.cfg 
echo 'datasource_list: [ Azure ]' >> /etc/cloud/cloud.cfg.d/91-azure_datasource.cfg 

echo    2. /etc/cloud/hostnamectl-wrapper.sh
cat /dev/null >  /etc/cloud/hostnamectl-wrapper.sh
echo '#!/bin/bash -e'                  >> /etc/cloud/hostnamectl-wrapper.sh
echo 'if [[ -n "\$1" ]]; then '         >> /etc/cloud/hostnamectl-wrapper.sh
echo '    hostnamectl set-hostname \$1' >> /etc/cloud/hostnamectl-wrapper.sh
echo 'else'                            >> /etc/cloud/hostnamectl-wrapper.sh
echo 'hostname'                        >> /etc/cloud/hostnamectl-wrapper.sh
echo 'fi'                              >> /etc/cloud/hostnamectl-wrapper.sh
chmod 0755 /etc/cloud/hostnamectl-wrapper.sh

echo    3. /etc/cloud/cloud.cfg.d/90-hostnamectl-workaround-azure.cfg 
cat > /etc/cloud/cloud.cfg.d/90-hostnamectl-workaround-azure.cfg <<XXX
# local fix to ensure hostname is registered
datasource:
  Azure:
    hostname_bounce:
      hostname_command: /etc/cloud/hostnamectl-wrapper.sh
XXX

echo Update /etc/cloud/cloud.cfg
grep resizefs -A 3 /etc/cloud/cloud.cfg | grep disk_setup || {
   sudo sed -i '/resizefs/a \ - disk_setup' /etc/cloud/cloud.cfg
}
grep disk_setup -A 3 /etc/cloud/cloud.cfg | grep mount || {
   sudo sed -i '/disk_setup/a \ - mount' /etc/cloud/cloud.cfg
}

EOF
chmod +x setup-cloud-init.sh

scp -p -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null setup-cloud-init.sh $ip:
ssh -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null  $ip sudo ./setup-cloud-init.sh
ssh -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null  $ip sudo waagent -deprovision+user -force
az vm deallocate --resource-group $rg --name $vmName
az vm generalize --resource-group $rg --name $vmName


json=$(az image list -g $rg)
imageName=$(get_name_index $imageName "$json")
az image create --resource-group $rg --name $imageName --source $vmName

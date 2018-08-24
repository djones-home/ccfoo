# recipe for a node that generates configuration images
# AWS secuirty groups using the sgviz gem
# CIDATA is used to identify the target VpcName and vpcId

package %w{ gcc ruby-devel rubygems }

gem_package %w{ io-console agviz }

today = `date +%D`
vpcName = `jq -r .VpcName #{ENV["CIDATA"]}`
sgImage = '/root/ws/images/sgviz_#{vpcName}.png'
label = vpcName + " Security Groups " + today
vpcId = `jq -r .VpcId #{ENV["CIDATA"]}`

bash 'graph_security_groups' do
  not_if { File.exist?( sgImage ) }
  code <<-EOH
  sgviz generate --output-path #{sgImage} --global-label=#{label} --vpc-ids #{vpcId}
  EOH
end
 

#!/usr/bin/env ruby
# $HeadURL: https://svn.nps.edu/repos/metocgis/infrastructure/trunk/tools/devMapping.rb $
# $Id: devMapping.rb 61326 2017-05-25 18:42:18Z dljones@nps.edu $

###
#  Render the device mapping file used when launching an instance.
#  Requies CIDATA and templates.
#  * Loads the ciData Json, ENV['CIDATA']
#  * Construct inststanceData, from defaults merged with the specificed name
#  * Render the ERB template, with the current bindings
#  * The ERB template, is set by the DevMappingTemplateFile from CIDATA.


require 'yaml'
require 'rubygems'
require 'json'
require 'erb'
require "base64"


abort("ERROR: CIDATA environment variable is not set") unless ENV.has_key?("CIDATA")
abort("ERROR: CIDATA does not exists: " + ENV["CIDATA"])  unless File.exists?(ENV["CIDATA"])
abort("ERROR: Usage: #{File.basename(__FILE__)} {required_InstanceName} ...") unless( ARGV.length >= 1 )
data = JSON.parse(File.read(ENV["CIDATA"] ))
datadir = File.dirname(ENV["CIDATA"])
instanceName = ARGV[0]
# build instanceData hash for later use by any template.
# start with instance defaults, merge with named instance, and merge/flatten the instance-specific-cidata
abort("ERROR: No InstanceDefaults in CIDATA: " +  ENV["CIDATA"] ) unless ( instanceData = data["InstanceDefaults"] )
instanceData.merge!( data["Instances"].select{ |h| h["Name"] == instanceName }.first )
instanceData.merge!( instanceData["cidata"])
## downcase names that may double as file names, like roles and envrionments
instanceEnvironment=data["Name"].downcase
instanceEnvironment=instanceData["Environment"].downcase if instanceData.has_key?("Environment")
# if no Roles, then use the name as a default role.
instanceRoles = [ instanceName.downcase ]
instanceRoles=instanceData["Roles"] if instanceData.has_key?("Roles")
# run_list has highest precidence
unless instanceData.has_key?("run_list") 
  instanceData["run_list"] = instanceRoles.map { |s| "role[#{s}]" }
end

name = "DevMappingTemplateFile"
unless data.has_key?(name) 
   $stderr.puts( "WARNING: #{File.basename(__FILE__)}: CIDATA does not have a #{name} key,  in " + ENV["CIDATA"])  
   exit 0
end
file = data[name]
file = File.join(datadir, file) if (  File.dirname(file) == "." )
abort("ERROR: CIDATA #{name} file does not exists: #{file}") unless File.exists?(file)
renderer = ERB.new( File.read(file))
puts  renderer.result(binding)



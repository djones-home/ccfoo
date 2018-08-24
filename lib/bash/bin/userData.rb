#!/usr/bin/env ruby
#md+
#
# # Render user-data  for cloud-init
# 
# Version:
#
#     $HeadURL: https://svn.nps.edu/repos/metocgis/infrastructure/trunk/tools/userData.rb $
#     $Id: userData.rb 71547 2018-06-06 21:31:07Z dljones@nps.edu $
# 
# - This script is used to render user-data for cloud-init per CIDATA. 
# - Called by ciStack when launching an instance, given a JSON file of setting for the instance.
# -  Values for users, runcmd, and userdatatemplate can be inline or read from files.
# - Accepts files of  yaml, json, or erb.
# - If inlined in the cidata.json (rather than files) ERB is used only on the userdatatemplate.
#  
#  Typical used with CIDATE having the JSON keys like: "UsersFile", "RuncmdFile", "UserDataTemplateFile"
##  If both keys exists for example "users" and "UsersFile", the File takes precidence.
# 
# ````
# "UsersFile": "PROJECTusers.yaml",
# "RuncmdFile": "PROJECTruncmd.yaml",
# "UserDataTemplateFile": "templates/userdata.erb", 
# ````
# # Also See:
# __launch_instance__ function in [ciStack source]
# 
# [ciStack source]: https://svn.nps.edu/repos/metocgis/infrastructure/trunk/tools/ciStack.sh
#md- 

require 'yaml'
require 'rubygems'
require 'json'
require 'erb'
require "base64"


abort("ERROR: Usage: #{File.basename(__FILE__)} {Instance.json}") unless( ARGV.length == 1 )
jsonFile=ARGV[0]

abort("ERROR: CIDATA environment variable is not set") unless ENV.has_key?("CIDATA")
abort("ERROR: CIDATA does not exists: " + ENV["CIDATA"])  unless File.exists?(ENV["CIDATA"])
# The given json file maybe produced dynamicly by the ciStack.sh instanceData function.
abort("ERROR: Instance.json does not exists: " + jsonFile)  unless File.exists?(jsonFile)
data = JSON.parse(File.read(jsonFile))
# Although, nolong rendering from env CIDATA, this is still used for the base directory path to templates.
datadir = File.dirname(ENV["CIDATA"])
# 
# Note: The "Instance" object is deprecated, eventually it should go-away.
if data.has_key?("Instance")
   # Flatten instanceData into data, effectively  override any globals, with instances 
    instanceData = data["Instance"]
    data.merge!(instanceData)
end
data["jsonFile"]= jsonFile 

@rv=0
%w{ Environment RoleName Name }.each { |n|
 unless data.has_key?(n) 
    $stderr.puts "#{$0}: Error given JSON must have \"#{n}\" key." 
     @rv+=1
 end
}
exit( 1)  if ( @rv != 0 )

instanceRoles = [ data["RoleName"] ]
instanceEnvironment =  data["Environment"]
# keeping this simple, just supporting one role in the run_list.
unless data.has_key?("run_list") 
  data["run_list"] = instanceRoles.map { |s| "role[#{s}]" }
end


## The latter of these (UserFile, RuncmdFile, UserDataTemplate) takes precidence, since they are merged.
## In other words the UserDataTemplate can overwirte the content the others, making them superfluous.
%w{ UsersFile RuncmdFile UserDataTemplateFile }.each { |name|
   puts( "WARNING: CIDATA does not have a #{name} key,  in " + ENV["CIDATA"])  unless data.has_key?(name)
   if data.has_key?(name)
      file = data[name]
      file = File.join(datadir, file) 
      abort("ERROR: CIDATA #{name} file does not exists: #{file}") unless File.exists?(file)
      name = name.sub("File", "").downcase
      begin
        data[name] = JSON.parse(File.read(file)) if ( file =~ /.*\.json/ ) 
        data[name] = YAML.load(File.read(file)) if ( file =~ /.*\.yaml/ ) 
      rescue Exception => e
        puts "Could not parse #{name} #{file} \n #{e.message}"
      end
      h = Hash.new
      fr = { "roles" => instanceRoles, "environment" => instanceEnvironment }
      h["write_files"] = [ { "encoding" =>  "b64",
          "owner" =>  "root:root",
          "path" => "/root/setup/first_run.json",
          "permissions" => "0600",
          "content" =>  Base64.encode64( JSON.pretty_generate(fr)) 
      } ]
      data["write_files"] = h.to_yaml.sub(/^---/,"")
      if ( file =~ /.*\.erb/ ) 
         renderer = ERB.new(File.read(file), nil, "-")
$stderr.puts "rendering ERB #{file}"
         data[name] =  renderer.result(binding)
      end
   end
}

%w{ users runcmd userdatatemplate }.each { |name|
    abort("ERROR: could not make userdata for #{name} from CIDATA: " + ENV["CIDATA"])  unless data.has_key?(name)
}
###
# We need another pass of erb for the final data, for the case of template was inline CIDATA.
#
renderer = ERB.new( data["userdatatemplate"], nil, "-" )
userData =  renderer.result(binding)
begin
   # verify it still parses clean
   YAML.parse(userData)
rescue Exception => e
 $stderr.puts "Error templating ciData into userData for instance, invalid YAML."
 $stderr.puts e.message
 $stderr.puts e.backtrace.inspect
 @rv+=1
end
puts userData
exit @rv




#!/usr/bin/env ruby
#md+ 
# Version:
#
#     $HeadURL: https://svn.nps.edu/repos/metocgis/infrastructure/trunk/tools/userfile.rb $
#     $Id: userfile.rb 68700 2018-03-02 20:46:00Z dljones@nps.edu $
#
# Update the users.yaml file which used to creates Linux system accounts upon cloud-init.
#md-
abort("Usage: #{File.basename(__FILE__)} USERFILE.yaml LOGIN PUBKEY GECOS \n#{ARGV.size} != 3\n") unless( ARGV.size == 4 ) 

require 'yaml'
file = ARGV[0]
login = ARGV[1]
key = ARGV[2]
abort("Could not read userFile.yaml: \"#{file}\"") unless( File.readable?(file))
doc = YAML.load_file(file)
users = doc["users"].select{ |h| h['login'] != login }
user = doc["users"].select{ |h| h['login']==login}
if user.size == 0 
   user = users.last.dup 
   user["ssh-authorized-keys"] = []
end
user["name"]=login
# add to the list of key
user["ssh-authorized-keys"].unshift( key )
user["gecos"] = ARGV[3]
user["mail"] = ARGV[4]
doc["users"] = users
doc["users"] << user
# save comments from top/bottom of file
puts File.readlines(file).select{ |line| line[/^#/] }
puts doc.to_yaml.sub(/^---/,"")







                                

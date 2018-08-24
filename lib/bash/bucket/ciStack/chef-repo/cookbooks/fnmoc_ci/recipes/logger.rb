puts "logger: Hello World"
#md+
###
# ## Install ELK stack for streaming/centrailized logging.
# * Logstash: The server component of Logstash that processes incoming logs
# * Elasticsearch: Stores all of the logs
# * Kibana: Web interface for searching and visualizing logs, which will be proxied
#
# Client systems need to install a log shipper, setup to feed logstash
# * Filebeat: Installed on client servers 
# * Fluentd:


# 
## Reference:  https://www.digitalocean.com/community/tutorials/how-to-install-elasticsearch-logstash-and-kibana-elk-stack-on-centos-7

#  1. Install server package
#  #. ....

#
# ### Node["elk"][ _variables_ ]:
#

# -  __basedn__   LDAP context root, i.e. dc=example,dc=com
node.default["elk"]["basedn"] = "dc=ccs,dc=nps,dc=edu"
# -  __PW__      administrative password, defaults to "redhat"
node.default["elk"]["PW"] = "redhat"

#md+ This marks this file as having embedded Markdown, for the cookbookDoc function  
#  ### A recipe to provision a logger InstanceRole
#
# You should replace this a with useful description of how a __logger__ is provisioned.
# 
# Workflow: 
# 
#  - Interesting step
#  - Anonther interesting step in the setup
#
# Also See: [CIE Docs](https://incubator2.nps.edu/)
#
#md-  block  parsing comments for MD until the next #md+ commnet line.

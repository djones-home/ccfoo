# Rippledoc produces html docs from nested directories of markdown files using Pandoc.
# license GPL
# http://www.gnu.org/licenses/
# https://github.com/uvtc/rippledoc
# http://www.unexpected-vortices.com/sw/rippledoc/rationale-and-benefits.html
# There are a number of forks of an older perl version by the same name.
# This installs the clojure version

# requies pandoc Markdown
yum_package pandoc do
 options "--enablerepo=epel "
end

# this needs fixed it may only need to install into ~jenkins/bin
cookbook_file "/usr/local/bin/rippledoc.sh" do
  source "rippledoc.sh"
  owner 'root'
  group 'root'
  mode '0755'
    action :create_if_missing
end

execute 'extract_rippledoc' do
  command 'tar xzvf #{cookbook}/files/rippledoc-0.1.2-standalone.tar.gz'
  cwd '/usr/local/bin'
  not_if { File.exists?("/usr/local/bin/rippledoc.jar") }
end

cookbook_file "/var/lib/java/rippledoc.jar" do
    source "rippledoc-0.1.2-standalone.jar"
    mode '0645'
    action :create_if_missing
end



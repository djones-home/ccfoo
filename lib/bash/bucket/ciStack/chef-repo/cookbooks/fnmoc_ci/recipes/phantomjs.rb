bash "install_phantomjs" do
code <<-EOF
   install_phantom() {
      local version=2.1.1
      local dir=/opt/phantomjs
      [ -d $dir ] && echo ${FUNCNAME[0]} Install folder already exists: \"$dir\". Nothing to do. && return 0
      sudo yum install -y fontconfig freetype
      echo  https://bitbucket.org/ariya/phantomjs/downloads/phantomjs-${version}-linux-x86_64.tar.bz2
      wget https://bitbucket.org/ariya/phantomjs/downloads/phantomjs-${version}-linux-x86_64.tar.bz2 || return 1
      sudo mkdir -p $dir
      sudo  tar -xjvf `pwd`/phantomjs-${version}-*tar.bz2 --strip-components 1 --directory=$dir
    }
    install_phantom
   EOF
   not_if { File.exists?("/opt/phantomjs/bin/phantomjs" ) }
end

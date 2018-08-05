# ccfoo
Does this work? No.  __Foo__ is in the name for a good reason.  This repo is just a nonsense placeholder, for me while I am  experimenting with a new cloud provider, commander CLI, NodeJS,  NPM, oh and vsCode too.

The platform I'm runing on is Linux: 
* Xubuntu 14.4 LTS
* NodeJS v8.11.3
* NPM 6.2.0
* Azure-cli  2.0.32
* jq-1.5-1-a5b5cbe
* VS Code 1.25.1
  
I don't know that this  will work on a  Windows platform.

Commander.js is the framework for the CLI.  I have a git clone of this in my $workspace. I put a link as follows, in my HOME bin, to make it easy to invoke from bash. I have $HOME/bin in my PATH. 

# Setup and test:

````bash
[ ! -d $HOME/bin ] && mkdir $HOME/bin
echo $PATH | grep -q $HOME/bin || PATH+=:$HOME/bin
workspace=path/to/your/projects
 cd $workspace && 
git clone https://github.com/djones-home/ccfoo

cd ccfoo && npm install &&
ln -s `pwd`/bin/ccfoo.js  $HOME/bin/ccfoo
````

NPM is really interesting. I think it could do all the above  with it's features. 

To exercise the commander cli code, I will make the following bash function, which use  "ccfoo config" commands, and borrow settings from the azure-cli config.
Assuming you have been working with the "az" command, it
will have created the .azure folder and content.

````bash
setupConfig() {
  x=$(az account show)
  for n in environmentName id user.name tenantId id; do
     echo ccfoo config set ${n/./} $(echo $x | jq -r .${n})
     ccfoo config set ${n/./} $(echo $x | jq -r .${n})
  done 
   ccfoo config show
}
cleanConfig() {
    rm $(ccfoo config show | jq -r .localSettingsFile)
   ccfoo config show
}
````
Forexample, the first function removes my local ccfoo-config, and then showes defaults that are wired into the ccfoo node package ( in lib/settings.js).


````bash
dj@dj15:~$ cleanConfig
{
  "cert": "/home/jondoe/certs/admin.pem",
  "ca": "/home/jondoe/certs/ca-crt.pem",
  "passphrase": "redacted",
  "baseUrl": "https://ci10.example.com/app",
  "uri": "/widget",
  "localSettingsFile": "/home/jondoe/.config/ccfoo/config.json"
}
''''

Now take the settings from the azure-cli - just robbing it blind :-),

````bash
dj@dj15:~$ cleanConfig >/dev/null; setupConfig
ccfoo config set environmentName AzureUSGovernment
ccfoo config set id guid-gibbrish
ccfoo config set username jondoes@componay.onmicrosoft.com
ccfoo config set tenantId guid-gibbrish
ccfoo config set id gid-gibbrish
{
  "cert": "/home/jondoe/certs/admin.pem",
  "ca": "/home/jondoe/certs/ca-crt.pem",
  "passphrase": "redacted",
  "baseUrl": "https://ci10.eample.com/app",
  "uri": "/widget",
  "localSettingsFile": "/home/johndoe/.config/ccfoo/config.json",
  "environmentName": "AzureUSGovernment",
  "id": "guid-jibbirsh",
  "username": "jondoe@company.onmicrosoft.com",
  "tenantId": "{guid-gibbrish}"
}
dj@dj15:~$ cp ~/.azure/accessTokens.json ~/.config/ccfoo/
dj@dj15:~$ cp ~/.azure/az.json ~/.config/ccfoo/
dj@dj15:~$ ccfoo config set AZURE_PASSWORD redacted
dj@dj15:~$ vi ~/.config/ccfoo/config.json


````

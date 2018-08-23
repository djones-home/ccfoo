const path = require('path')
const fs = require('fs')
const shell = require('shelljs')
const platform = require("os").platform()
const home = platform == 'win32' ? process.env.USERPROFILE : process.env.HOME
const name = require('../package').name
const settings = path.join(home, ".config", name, 'config.json' )
const profileName = process.env[`${name.toUpperCase()}_PROFILE`]  || 'default' 
const cidata = require('../lib/cidata')


// Default settings, and example profiles for azGov, awsGov, ..
// the azGov is taken from 'az account show'
// 
const exampleConfig =  {
  default: {
    location: 'usgovarizona',
    envrionmentName: 'AzureUSGovernment', 
    id: "your-Subscription-uid",
    tenantId: "your-AAD-tenantID",
    user: {
      name: "jdoe@exmaple.onmicrosoft.com",
      type: "user"
    },
    localSettingsFile: settings,
    credentialsStore: { az : path.join( path.basename(settings), 'az-accessTokens.json') },
  },
  azure_profile_example: {
    location: 'usgovarizona',
    envrionmentName: 'AzureUSGovernment', 
    id: "your-Subscription-uid",
    tenantId: "your-AAD-tenantID",
    user: {
      name: "jdoe@exmaple.onmicrosoft.com",
      type: "user"
    },
    localSettingsFile: settings,
    credentialsStore: { az : path.join( path.basename(settings), 'az-accessTokens.json') },
  },
  aws_profile_example: {
    description: "use the default_sts profile that the aws-cli uses",
    env: { 
      AWS_PROFILE: 'default_sts',
      AWS_SDK_LOAD_CONFIG: true
    }
  }
}

// Load the profileName, or template a new when missing.
async function load(cloud = {} ) {
  if ( ! fs.existsSync(settings ))  { save( exampleConfig.default) } 
  c = JSON.parse(fs.readFileSync(settings, 'utf8'))
  if ( ! c[profileName] ) {
     // add a profile using exampleConfig.default to template a new profile
     c[profileName] = exampleConfig.default
     save( c[profileName] );
  }
  // expose the profileName for validate and show-action
  c[profileName].profileName = profileName
  let config = await validate(c[profileName], cloud)
  return config
}

function save(profile=null) {
  // Merge given profile settings into HOME/.config/PACKAGE_NAME/config.json
  // Force the localSettingFile property to tell the turth, user cannot change it.
  if ( ! fs.existsSync(settings) ) {
    // Make local settings for a new user.
    if (! fs.existsSync(path.dirname(settings)) ) shell.mkdir('-p', path.dirname(settings), (e)=> { console.error(e) }) 
    fs.writeFileSync( settings, JSON.stringify(exampleConfig, null, 2), 'utf8')
    fs.chmodSync(settings, '0600')
    fs.chmodSync(path.dirname(settings), '0700')
  }
  
  if ( profile ) {
      c = JSON.parse(fs.readFileSync(settings, 'utf8'))
      c[profileName] = profile 
      fs.writeFileSync( settings, JSON.stringify( c, null, 2))
  }
}

async function action( program, config, cmd, k , v) {
  program.debug && console.log('cmd:',cmd,'\nk: ', k,'\nv: ', v, '\noptions: ', options)
  let o = config
  let settings = o.localSettingsFile
  o.deleteSettingsFile
  switch (cmd) {
    case 'show' :
      await console.log(JSON.stringify(config, null,2))
      break;
    case 'set' :
      o[k] = v 
      save(o)
      break;
    case 'get' : 
      process.stdout.write(JSON.stringify(o[k]))
      break;
    case 'delete' :
      if (! config[k])  break;
      delete o[k]
      save(o)
      break;
// remove the validate for now, this cannot work here, as validate needs the cloud object
//    case 'validate' :
//      validate({config, cloud})
//      break
    default : 
      throw new Error(`unknown cmd: ${cmd}` )
  }
}

async function validate(config, cloud = {} ) {
  if ( ! cloud || Object.keys(cloud).length == 0 )  return config
  if ( Object.keys(cloud).filter(e => e == config.provider).length != 1 ) {
      throw new Error(
        `Please set provider in ${config.settings}` 
       +  `for profile-name: ${config.profileName}`
       + `for example, one of the known providers: ${ Object.keys(cloud) }\n`
       + '    config set provider aws\n'
       + '    config set provider azure\n'
      )
  }
  return await cloud[config.provider].validate(config)
}

module.exports = {
   save: save, 
   load: load,
   action: action
}

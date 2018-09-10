const path = require('path')
const fs = require('fs')
const shell = require('shelljs')
const platform = require("os").platform()
const home = platform == 'win32' ? process.env.USERPROFILE : process.env.HOME
const pkgName = require('../package').name
const settings = path.join(home, ".config", pkgName, 'config.json' )
const cidata = require('../lib/cidata')

// Parse argv for --profile, as commander will parse this too late.
const log = console.error;

function getProfileName(argv = process.argv, env = process.env, name = pkgName) {
  let i = argv.findIndex(v=> /-p|--profile/.test(v) )
  if ( i >=  0 ) return argv[i+1]
  return env[`${name.toUpperCase()}_PROFILE`]  || 'default' 
}


// Default settings, and example profiles for azGov, awsGov, ..
// the azGov is taken from 'az account show'
// 
const exampleConfig =  {
  default: {
    location: 'usgovarizona',
    envrionmentName: 'AzureUSGovernment', 
    id: "your-Subscription-uid",
    tenantId: "your-AAD-tenantID",
    username: "jdoe@exmaple.onmicrosoft.com",
    localSettingsFile: settings,
    credentialsStore:  path.join( path.basename(settings), 'az-accessTokens.json') 
  },
  azure: {
    description: 'Example azure settings',
    location: 'usgovarizona',
    envrionmentName: 'AzureUSGovernment', 
    id: "your-Subscription-uid",
    tenantId: "your-AAD-tenantID",
    localSettingsFile: settings,
    credentialsStore:  path.join( path.basename(settings), 'az-accessTokens.json') 
  },
  aws: {
    description: "Example AWS settings, to use the default_sts profile that the aws-cli uses",
    AWS_PROFILE: 'default_sts',
    AWS_SDK_LOAD_CONFIG: true
  }
}

// Load the profileName, or template a new when missing.
async function load(cloud = null ) {
  if ( ! fs.existsSync(settings ))  { save( exampleConfig.default) } 
  c = JSON.parse(fs.readFileSync(settings, 'utf8'))
  const pn = getProfileName() 

  if ( ! c[pn] ) {
     // add a profile using exampleConfig.default to template a new profile
     c[pn] = exampleConfig.default
     save( c[pn] );
  }
  // Only one profile is returned by load, for this program instance
  let profile = c[pn]
  // expose the profileName and path to file, for validate and show-action
  profile.profileName = pn
  profile.localSettingFile = settings
  Object.keys(profile).forEach(k=> {
    if ( k == k.toUpperCase() ) {
      if( process.env[k] && process.env[k] != profile[k] ) {
         console.error(`WARNING profile changing: ENV, from: ${k}=${process.env[k]}, to:${pn}.${k}=${profile[k]}`)
         // throw new Error("Configuration error")
      } 
      process.env[k] = profile[k] 
    }
  })
  profile = await validate(profile, cloud)
  // Load the settings shared accross a project (cidata), only if given cloud.
  if (cloud) profile.cidata = await cidata.load(profile)
  return profile
}
function save(profile=null) {
  const pn = getProfileName()
  // Merge given profile settings into HOME/.config/PACKAGE_NAME/config.json
  if ( ! fs.existsSync(settings) ) {
    // Make local settings for a new user.
    if (! fs.existsSync(path.dirname(settings)) ) shell.mkdir('-p', path.dirname(settings), (e)=> { console.error(e) }) 
    fs.writeFileSync( settings, JSON.stringify(exampleConfig, null, 2), 'utf8')
    fs.chmodSync(settings, '0600')
    fs.chmodSync(path.dirname(settings), '0700')
  }
  // Force the localSettingFile property 
  profile.localSettingFile = settings
  if ( profile ) {
      c = JSON.parse(fs.readFileSync(settings, 'utf8'))
      c[pn] = profile 
      fs.writeFileSync( settings, JSON.stringify( c, null, 2))
  }
}

const commandLookup = {

  show: (profile, k, v) => {
    log(JSON.stringify(profile, null, 2));
    return profile;
  },

  set: (profile, k, v) => {
    profile[k] = v;
    save(profile);
    log(JSON.stringify(profile, null, 2));
    return profile;
  },

  get: (profile, k, v) => {
    let result = profile[k];
    let cmd = JSON.stringify(result);
    process.stdout.write(cmd);
    return result;
  },

  delete: (profile, k, v) => {
    if (profile[k]) {
      delete profile[k];
      save(profile);
      return profile;
    }
  }
};


async function action(program, profile, cmd, k, v) {
  program.debug && log('cmd:', cmd, '\nk: ', k, '\nv: ', v);


  const funct = commandLookup[cmd];
  if (funct) {
    return funct && funct(profile, k, v);
  } else {
    log(`command ${cmd} not found`);
  }
}

// No validation is done unless an object for cloud is given.
// The 'config' sub-command does not pass the cloud, intentionally to NOT validate the config.
// Otherwise, the validation would thow an error and prevent the user from changing broken configurations.
async function validate(config, cloud  ) {
  if ( ! cloud )  return config
  if ( Object.keys(cloud).filter(e => e == config.provider).length != 1 ) {
      throw new Error(
        `Please run: ${pkgName} config set provider [${ Object.keys(cloud).join("|")}] -p  ${config.profileName}\n` 
       + `for example:\n  `
       + pkgName + ' config set provider aws -p yourProfileName\n  '
       + pkgName + ' config set provider azure -p yourProfileName\n'
      )
  }
  //Object.keys(config) { }
  return await cloud[config.provider].validate(config)
}

module.exports = {
   save: save, 
   load: load,
   action: action,
   getProfileName
}

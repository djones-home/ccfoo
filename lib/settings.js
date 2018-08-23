const path = require('path');
const fs = require('fs');
const shell = require('shelljs');
const platform = require('os').platform();
const home = platform == 'win32' ? process.env.USERPROFILE : process.env.HOME;
const packageName = require('../package').name;
const basePath = path.join(home, '.config', packageName);
const settings = path.join(basePath, 'config.json');
const profileEnv = `${packageName.toUpperCase()}_PROFILE`;

const log = console.log;

function defaultConfigPath() {
  if (!fs.existsSync(basePath)) {
    fs.mkdirSync(basePath);
  }
  return basePath;
}
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
const exampleConfig = {
  default: {
    name: 'default',
    location: 'usgovarizona',
    envrionmentName: 'AzureUSGovernment',
    id: 'your-Subscription-uid',
    tenantId: 'your-AAD-tenantID',
    user: {
      name: 'jdoe@exmaple.onmicrosoft.com',
      type: 'user'
    },
    localSettingsFile: settings,
    credentialsStore: {
      az: path.join(defaultConfigPath(), 'az-accessTokens.json')
    }
  },
  azure_profile_example: {
    name: 'azure_profile',
    location: 'usgovarizona',
    envrionmentName: 'AzureUSGovernment',
    id: 'b156ff74-abbe-49c8-bc92-b80e8a7bad23',
    tenantId: 'your-AAD-tenantID',
    user: {
      name: 'jdoe@exmaple.onmicrosoft.com',
      type: 'user'
    },
    localSettingsFile: settings,
    credentialsStore: {
      az: path.join(defaultConfigPath(), 'az-accessTokens.json')
    }
  },
  aws_profile_example: {
    name: 'aws_profile',
    description: 'use the default_sts profile that the aws-cli uses',
    env: {
      AWS_PROFILE: 'default_sts',
      AWS_SDK_LOAD_CONFIG: true
    }
  }
};



function currentProfile() {
  let profileName = process.env[profileEnv];
  //if I had the permission on this machine I would read it from the
  //the environment

  profileName = 'azure_profile_example';
  return profileName || 'default';
}

// Load the profileName, also create it when missing.
function load() {
  if (!fs.existsSync(settings)) {
    save(exampleConfig.default);
  }
  const config = JSON.parse(fs.readFileSync(settings, 'utf8'));
  const profileName = currentProfile();
  if (config[profileName]) {
    return config[profileName];
  }

  // add a profile using exampleConfig.default
  save(exampleConfig.default);
  return exampleConfig.default;
// Load the profileName, or template a new when missing.
function load(cloud = {} ) {
  if ( ! fs.existsSync(settings ))  { save( exampleConfig.default) } 
  c = JSON.parse(fs.readFileSync(settings, 'utf8'))
  if ( ! c[profileName] ) {
     // add a profile using exampleConfig.default to template a new profile
     c[profileName] = exampleConfig.default
     save( c[profileName] );
  }
  // expose the profileName for validate and show-action
  c[profilename].profileName = profileName
  return validate(c[profileName], cloud)
}

function save(profile = null) {
  // Merge given profile settings into HOME/.config/PACKAGE_NAME/config.json
  // Force the localSettingFile property to tell the turth, user cannot change it.
  if (!fs.existsSync(settings)) {
    // Make local settings for a new user.
    if (!fs.existsSync(path.dirname(settings)))
      shell.mkdir('-p', path.dirname(settings), e => {
        console.error(e);
      });
    fs.writeFileSync(settings, JSON.stringify(exampleConfig, null, 2), 'utf8');
    fs.chmodSync(settings, '0600');
    fs.chmodSync(path.dirname(settings), '0700');
  }

  if (profile) {
    const config = JSON.parse(fs.readFileSync(settings, 'utf8'));
    const profileName = currentProfile();

    config[profileName] = profile;
    fs.writeFileSync(settings, JSON.stringify(config, null, 2));
  }
}

const commandLookup = {
  name: (config, k, v) => {

    const result = `${profileEnv} := ${currentProfile()}`
    log(result);
    return currentProfile();
  },

  show: (config, k, v) => {
    log(JSON.stringify(config, null, 2));
    return config;
  },

  set: (config, k, v) => {
    config[k] = v;
    save(config);
    log(JSON.stringify(config, null, 2));
    return config;
  },

  get: (config, k, v) => {
    let result = config[k];
    let cmd = JSON.stringify(result);
    process.stdout.write(cmd);
    return result;
  },

  delete: (config, k, v) => {
    if (config[k]) {
      delete config[k];
      save(config);
      return config;
    }
  }
};

function doAction(program, profile, cmd, k, v) {
  program.debug && log('cmd:', cmd, '\nk: ', k, '\nv: ', v);


  const funct = commandLookup[cmd];
  if (funct) {
    return funct && funct(profile, k, v);
  } else {
    log(`command ${cmd} not found`);
  }
}

function initCommand(program) {
  program
    .command('config <cmd> [key] [value]')
    .description(
      'Configure local settings: config [show|name|get <key> |set <key value>|del <key>]'
    )
    .action((cmd, key, value, options) => {
      var profile = load();
      doAction(program, profile, cmd, key, value);
    });
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
  if ( ! cloud)  return config
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

module.exports = {
  initCommand: initCommand,
  currentProfile: currentProfile,
  defaultConfigPath: defaultConfigPath,
  save: save,
  load: load,
  action: doAction
};

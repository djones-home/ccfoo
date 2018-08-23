const path = require('path');
const fs = require('fs');
const shell = require('shelljs');
const platform = require('os').platform();
const home = platform == 'win32' ? process.env.USERPROFILE : process.env.HOME;
const packageName = require('../package').name;
const configPath = path.join(home, '.config');
const basePath = path.join(configPath, packageName);
const settings = path.join(basePath, 'config.json');
const profileEnv = `${packageName.toUpperCase()}_PROFILE`;

const log = console.log;

function defaultConfigPath() {
  if (!fs.existsSync(configPath)) {
    fs.mkdirSync(configPath);
  }
  if (!fs.existsSync(basePath)) {
    fs.mkdirSync(basePath);
  }
  return basePath;
}

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
  azure_profile: {
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
  aws_profile: {
    name: 'aws_profile',
    description: 'use the default_sts profile that the aws-cli uses',
    env: {
      AWS_PROFILE: 'default_sts',
      AWS_SDK_LOAD_CONFIG: true
    }
  }
};



function activeProfileName() {
  let profileName = process.env[profileEnv];
  //if I had the permission on this machine I would read it from the
  //the environment

  profileName = 'azure_profile';
  return profileName || 'default';
}

// Load the profileName, also create it when missing.
function load() {
  if (!fs.existsSync(settings)) {
    save(exampleConfig);
  }
  const config = JSON.parse(fs.readFileSync(settings, 'utf8'));
  const profileName = activeProfileName();
  if (config[profileName]) {
    return config[profileName];
  }

  // add a profile using exampleConfig.default
  return exampleConfig.default;
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
    const profileName = activeProfileName();

    config[profileName] = profile;
    fs.writeFileSync(settings, JSON.stringify(config, null, 2));
  }
}

const commandLookup = {
  name: (config, k, v) => {

    const result = `${profileEnv} := ${activeProfileName()}`
    log(result);
    return activeProfileName();
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
}

module.exports = {
  initCommand: initCommand,
  activeProfileName: activeProfileName,
  defaultConfigPath: defaultConfigPath,
  save: save,
  load: load,
  action: doAction
};

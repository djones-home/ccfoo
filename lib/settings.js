const path = require('path');
const fs = require('fs');
const shell = require('shelljs');
const platform = require('os').platform();
const home = platform == 'win32' ? process.env.USERPROFILE : process.env.HOME;
const name = require('../package').name;
const settings = path.join(home, '.config', name, 'config.json');
const profileName = process.env[`${name.toUpperCase()}_PROFILE`] || 'default';

const log = console.log;

// Default settings, and example profiles for azGov, awsGov, ..
// the azGov is taken from 'az account show'
//
const exampleConfig = {
  default: {
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
      az: path.join(path.basename(settings), 'az-accessTokens.json')
    }
  },
  azure_profile_example: {
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
      az: path.join(path.basename(settings), 'az-accessTokens.json')
    }
  },
  aws_profile_example: {
    description: 'use the default_sts profile that the aws-cli uses',
    env: {
      AWS_PROFILE: 'default_sts',
      AWS_SDK_LOAD_CONFIG: true
    }
  }
};

// Load the profileName, also create it when missing.
function load() {
  if (!fs.existsSync(settings)) {
    save(exampleConfig.default);
  }
  c = JSON.parse(fs.readFileSync(settings, 'utf8'));
  if (c[profileName]) return c[profileName];
  // add a profile using exampleConfig.default
  save(exampleConfig.default);
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
    c = JSON.parse(fs.readFileSync(settings, 'utf8'));
    c[profileName] = profile;
    fs.writeFileSync(settings, JSON.stringify(c, null, 2));
  }
}

const commandLookup = {

  show: (config, k, v) => {
    log(JSON.stringify(config, null, 2));
    return config;
  },

  set: (config, k, v) => {
      config[k] = v;
      save(config);
      return config;
  },

  get: (config, k, v) => {
    let result = config[k];
    let cmd = JSON.stringify(result);
    process.stdout.write(cmd);
    return result;
  },

  delete: (config, k, v) => {
    if ( config[k]){      
      delete config[k];
      save(config);
      return config;
    }
  },
}


function action(program, config, cmd, k, v) {
  program.debug && log('cmd:', cmd, '\nk: ', k, '\nv: ', v, '\noptions: ', options);

  const funct = commandLookup[cmd];
  if ( funct ) {
    return funct && funct(config,k,v)
  } else {
    log(`command ${cmd} not found`)
  }
}

module.exports = {
 // commandLookup: commandLookup,  
  save: save,
  load: load,
  action: action
};

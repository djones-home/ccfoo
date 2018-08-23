const azure = require('ms-rest-azure');
const files = require('./files');

const Configstore = require('configstore');
const pkg = require('../package.json');
const conf = new Configstore(pkg.name);

const log = console.log;
const out = process.stdout.write;

const openBrowser = require('opn');

let MyTokenCache = /** @class */ (function() {

  function MyTokenCache(profile) {
    this.profile = profile;
    this.tokens = [];
    this.load();
  }

  MyTokenCache.prototype.isSecureCache = function() {
    throw 'isSecureCache not implemented';
  };

  MyTokenCache.prototype.add = function(entries, cb) {
    this.tokens = this.tokens || [];
    var _a;
    (_a = this.tokens).push.apply(_a, entries);
    cb();
  };

  MyTokenCache.prototype.remove = function(entries, cb) {
    this.tokens = this.tokens && this.tokens.filter(function(e) {
      return !Object.keys(entries[0]).every(function(key) {
        return e[key] === entries[0][key];
      });
    });
    cb();
  };

  MyTokenCache.prototype.clear = function(cb) {
    this.tokens = [];
    cb();
  };

  MyTokenCache.prototype.find = function(query, cb) {
    var result = this.tokens && this.tokens.filter(function(e) {
      return Object.keys(query).every(function(key) {
        return e[key] === query[key];
      });
    });
    cb(null, result);
  };
  //
  // Methods specific to MyTokenCache
  //
  MyTokenCache.prototype.empty = function() {
    this.deleteOld();
    return !this.tokens || this.tokens.length === 0;
  };

  MyTokenCache.prototype.first = function() {
    return this.tokens && this.tokens[0];
  };


  MyTokenCache.prototype.filename = function() {
    const path = files.defaultPath()
    return path + `/${this.profile}.tokens.json`;
  };

  MyTokenCache.prototype.load = function() {

    files.getProfile(this.filename(), (err, result) => {
      if ( err ) {
        log(err);
        return;
      }

      this.tokens = result;
      this.tokens && this.tokens.map(function(t) {
        return (t.expiresOn = new Date(t.expiresOn));
      });
    });
  }

  MyTokenCache.prototype.save = function() {
    files.saveProfile(this.filename(), this.tokens);
  };

  MyTokenCache.prototype.deleteOld = function() {
    if ( this.tokens) {
      this.tokens = this.tokens.filter(function(t) {
        return t.expiresOn > Date.now() - 5 * 60 * 1000;
      });
    }
  };
  
  return MyTokenCache;
})();

let currentProfile = undefined;
let tokenCache = undefined;

function interactiveLogin(){
  const promise = new Promise((resolve, reject) => {

    openBrowser('https://microsoft.com/deviceloginus');

    const defaultEnv = azure.AzureEnvironment.AzureUSGovernment;
    const loginOptions = { environment: defaultEnv, tokenCache: tokenCache };

    azure.interactiveLogin(loginOptions, (err, credentials) => {
      if (err) {
        reject(err)
      } else {
        tokenCache.save();
        resolve(credentials);
      }
    });

  });
  log('returning promise interactiveLogin');
  return promise;
}

function useCasheCredentials(){
  const promise = new Promise((resolve, reject) => {
    if (!tokenCache && !tokenCache.first()) {
      reject({
        success: false,
        message: 'no credentials are cashed' 
      })
    }

    let token = tokenCache.first();
    const defaultEnv = azure.AzureEnvironment.AzureUSGovernment;

    let options = {
        username: token.userId,
        environment: defaultEnv,
        tokenCache: tokenCache
    };

    let credentials = new azure.DeviceTokenCredentials(options);
    resolve(credentials);
  });

  log('returning promise useCasheCredentials');
  return promise;
}

function getCredentials() {
    currentProfile = currentProfile || "Default";
    tokenCache = tokenCache || new MyTokenCache(currentProfile);

    if (tokenCache.empty()) {
      return interactiveLogin();
    } else {
      return useCasheCredentials();
    }
}

function clearProfile() {
  const promise = new Promise((resolve, reject) => {
    tokenCache = undefined;
    currentProfile = undefined;
    resolve(currentProfile);
  });

  log('returning promise clearProfile');
  return promise;
}

function setProfile(name, force=true) {
  const promise = new Promise((resolve, reject) => {
    if (currentProfile && !force) {
      reject({
        success: false,
        message: 'you must clear profile before it is set' 
      })
    } else {
      currentProfile = name;
      resolve(currentProfile);
    }
  });

  log('returning promise getProfile');
  return promise;
}

function getProfile() {
  const promise = new Promise((resolve, reject) => {
    if (currentProfile) {
      resolve(currentProfile);
    } else {
      reject({
        success: false,
        message: 'no current profile' 
      })
    }
  });

  log('returning promise getProfile');
  return promise;
}

exports.clearProfile = clearProfile;
exports.setProfile = setProfile;
exports.getProfile = getProfile;

exports.getCredentials = getCredentials;

exports.command = (repl) => {
  repl.command({
    cmd: 'profile',
    help: 'set profile',
    action: function(cmd, args, options) {
      log(cmd);
      log(args);
      log(options);
    }
  })

  repl.command({
    cmd: 'azp',
    help: 'login using azure profile',
    action: function(cmd, args, options) {
      const profile = args && args[0];
      setProfile(profile,true)
      .then(_ => {
        return getCredentials();
      })
      .then(cred => {
        log(cred);
      })
      .catch(err => log(err))
    }
  })

  // repl.command({
  //   cmd: 'getcreds',
  //   help: 'Try token cashe  https://microsoft.com/deviceloginus',
  //   action: function(cmd, args) {
  //     let profile = 'ClusterX';
  //     getCredentials(profile, (err, result) => {
  //       repl.context.getcreds = result;
  //       repl.commandComplete(err, cmd, result);
  //     });
  //   }
  // });
};

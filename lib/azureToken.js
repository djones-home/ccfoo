const path = require('path');
const fs = require('fs');
const shell = require('shelljs');

const azure = require('ms-rest-azure');
const settings = require('./settings')

const log = console.log;

const openBrowser = require('opn');

let MyTokenCache = (function() {
  function MyTokenCache(filename) {
    this.filename = filename;
    this.tokens = [];
    this.load();
  }

  MyTokenCache.prototype.isSecureCache = function() {
    throw 'isSecureCache not implemented';
  };

  MyTokenCache.prototype.add = function(entries, cb) {
    this.tokens = this.tokens || [];
    this.tokens.push.apply(this.tokens, entries);
    cb();
  };

  MyTokenCache.prototype.remove = function(entries, cb) {
    this.tokens =
      this.tokens &&
      this.tokens.filter(function(e) {
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
    var result =
      this.tokens &&
      this.tokens.filter(function(e) {
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

  MyTokenCache.prototype.getFilename = function() {
    return this.filename;
  };

  MyTokenCache.prototype.load = function() {
    try {
      const data = fs.readFileSync(this.getFilename());
      this.tokens = JSON.parse(data);

      this.tokens && this.tokens.forEach( t =>  {
        t.expiresOn = new Date(t.expiresOn);
      });
    } catch (ex) {
    }
  };

  MyTokenCache.prototype.save = function(done) {
    const filename = this.getFilename();

    var writeOptions = {
      encoding: 'utf8',
      mode: 384, // Permission 0600 - owner read/write, nobody else has access
      flag: 'w'
    };

    fs.writeFileSync(filename, JSON.stringify(this.tokens), writeOptions, done);
  };

  MyTokenCache.prototype.deleteOld = function() {
    if (this.tokens) {
      this.tokens = this.tokens.filter(function(t) {
        return t.expiresOn > Date.now() - 5 * 60 * 1000;
      });
    }
  };

  return MyTokenCache;
})();


function interactiveLogin(tokenCache) {
  const promise = new Promise((resolve, reject) => {
    openBrowser('https://microsoft.com/deviceloginus');

    const defaultEnv = azure.AzureEnvironment.AzureUSGovernment;
    const loginOptions = { environment: defaultEnv, tokenCache: tokenCache };

    azure.interactiveLogin(loginOptions, (err, credentials) => {
      if (err) {
        reject(err);
      } else {
        tokenCache.save();
        resolve(credentials);
      }
    });
  });
  log('returning promise interactiveLogin');
  return promise;
}

function useCasheCredentials(profile,tokenCache) {
  const promise = new Promise((resolve, reject) => {
    if (!tokenCache && !tokenCache.first()) {
      reject({
        success: false,
        message: 'no credentials are cashed'
      });
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

function getCredentials(profile) {
  let name = profile.name;
  let subscriptionId = profile.id;
  let filename = profile.credentialsStore;
<<<<<<< HEAD
  let tokenCache = new MyTokenCache(filename);
=======
  tokenCache = tokenCache || new MyTokenCache(name, filename);
>>>>>>> dbc85cc80db14a753687fb3aaa1d108ed0f1cc4c

  if (tokenCache.empty()) {
    return interactiveLogin(tokenCache);
  } else {
    return useCasheCredentials(profile, tokenCache);
  }
}

function clearCashe() {
  const promise = new Promise((resolve, reject) => {
    tokenCache = undefined;
    resolve(activeProfileName());
  });

  log('returning promise clearCashe');
  return promise;
}



function initCommand(program) {
  program
    .command('azlogin [name]')
    .description(
      'login to azure, use current token if possable'
    )
    .action((name, options) => {
      const profile = settings.load();

      getCredentials(profile)
        .then(cred => {
          log(cred);
        })
        .catch(err => log(err));
    });
}

module.exports = {
  MyTokenCache,
  initCommand,
  clearCashe,
  getCredentials,
  MyTokenCache
};

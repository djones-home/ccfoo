const fs = require('fs');
const path = require('path');

const config = '/.profile'

function defaultProfilePath() {
  return process.env.HOME + config;
};

module.exports = {
  defaultPath:() => {
    return defaultProfilePath();
  },

  getCurrentDirectoryBase : () => {
    return path.basename(process.cwd());
  },

  directoryExists : (filePath) => {
    try {
      return fs.statSync(filePath).isDirectory();
    } catch (err) {
      return false;
    }
  },

  saveProfile: (filename, token, done) => {
    const path = defaultProfilePath();
    if (!fs.existsSync(path)) {
      fs.mkdirSync(path);
    }
    var writeOptions = {
      encoding: 'utf8',
      mode: 384, // Permission 0600 - owner read/write, nobody else has access
      flag: 'w'
    };

    fs.writeFileSync(filename, JSON.stringify(token), writeOptions, done);
  },

  getProfile: (filename, done) => {
    try {
      const token = fs.readFileSync(filename);
      result = JSON.parse(token);
      done(null, result);
    } catch (ex) {
      if (ex.code !== 'ENOENT') {
        done(ex);
      }
    }
  }




};

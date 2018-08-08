// JSON document cache management

const package = require('../package')
const fs = require('fs')
const path = require('path')
var shell = require('shelljs')

const appCache = path.join(process.env.HOME, '.cache', package.name)

function clear() {
  fs.rmdirSync(appCache)
}

function init(ttl=null) {
  if (! fs.existsSync(path.dirname(appCache)) ) shell.mkdir('-p', appCache, (e)=> { console.error(e) }) 
  fs.chmodSync(appCache, '0700')
  if (typeof(ttl) == 'number' ) {
    let stale  = Math.trunc(Date.now() - (ttl * 1000) )
    fs.readdirSync(appCache).forEach(e => {
      var p = path.join(appCache,e)
      var mtimeMs = fs.statSync(p).mtimeMs
       if ( mtimeMs  < stale ) fs.unlinkSync( p )
    });
  }
}
// cGet( idString, TTL-in-seconds)
function cGet( cmdId, ttl=3600 ) {
    let fp = path.join(appCache, encodeURI(cmdId))
    if (fs.existsSync(fp) && (((Date.now() - fs.statSync('fooo').mtimeMs)/1000) < ttl) ) {
      return JSON.parse(fs.readFileSync(fp))
    }
}
// cPut( idString, object )
function cPut(cmdId, o ) {
   let fp = path.join(appCache, encodeURI(cmdId))
   fs.writeFileSync(JSON.stringify(o))
}

function clean( ttl=3600 ) {
  init(ttl)
}

function info() {
  return {
    appCache: appCache,
    stat: fs.statSync(appCache),
    entries: fs.readdirSync(appCache)
  }
}

module.exports = {
  clear: clear,
  init: init,
  cGet: cGet,
  cPut: cPut,
  clean: clean,
  info: info
}
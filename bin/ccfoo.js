#!/usr/bin/env node
"use strick"
const fs = require('fs'); 
const path = require("path");
var config = require('../lib/settings');
//var cidata = require('../lib/cidata')
//var cache = require('../lib/cache')
var inquirer =  require('inquirer-promise')

var basePath,  program

// path to the package install folder, or cwd if repl
// later.. I will  move to a module, where __filename is alway defined by wrapper function.
var basePath = (typeof __filename === 'undefined') ?  process.cwd() : path.dirname(fs.realpathSync(__filename));


// Define the program options,  action-based sub-commands, and exec (serached for) sub-command.
var program = require('commander') 
 .version('0.1.0')
 .option('-p --profile <Name>', 'provider profile name', process.env.CCFOO_PROFILE)
 .option('-d --ciData <dataFile>', 'CIDATA project settings', process.env.CIDATA)
 .option('-c --config <path>', 'Config', config.path )
 .option('-D --debug', 'Debug messages')

// exec (external) commands
var execCmds = [ "network", "vm", "storage", "security", 'bash-completion' ]
execCmds.sort().forEach( n=>{
  // name an exec command, like: ./bin/ccfoo-$n.js 
  program.command(n, `Run sub-command ${n} (sloppy help line.. I know, sorry)`)
})  

// action (built-in) commands 
program.command('config <cmd> [key] [value]')
  .description( "Configure local settings: config [show|set <key value>|del <k>]")
  .action( (cmd, k, v, options)=>{
    program.debug && console.log('cmd:',cmd,'\nk: ', k,'\nv: ', v, '\noptions: ', options)
    let o = config
    let settings = o.localSettingsFile
    o.deleteSettingsFile
    switch (cmd) {
      case 'show' :
        console.log(JSON.stringify(config, null,2))
        break;
      case 'set' :
        o[k] = v 
        fs.writeFileSync( settings, JSON.stringify(o, null, 2), 'utf8')
        break;
      case 'delete' :
        if (! config[k])  break;
        delete o[k]
        fs.writeFileSync( settings, JSON.stringify(o, null, 2), 'utf8')
        break;
      default : 
        console.error("ERROR: unknown cmd: " + cmd )
        process.exit(1)
    }
  })
program.parse(process.argv);


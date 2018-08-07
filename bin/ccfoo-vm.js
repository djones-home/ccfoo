#!/usr/bin/env node
// console.log(`${__filename} hello ${process.env.USER || 'world'}\n`) 
"use strick"
const fs = require('fs'); 
const path = require("path");
var config = require('../lib/settings');
const package = require('../package')
const subject = __filename.split('-').pop()

// Define the program globals
var program = require('commander') 
 .version(require(package.version)
 .option('-p --profile <Name>', 'provider profile name', 
    process.env[package.name.toUpperCase() + "_PROFILE"]
 .option('-D --debug', 'Debug messages')
 .option(`-n --name <${subject}Name>`, `Specify ${subject}-[name|id|tag|role|filterRE]`, "None")
 .option(`-u --unit <${subject}Unit>`, 'Organizational parent-[container|filterRE|id|tag]', config.id)
 .option('-N --noop', 'No operations that effect cloud changes.')

 // exec (external) commands
var execCmds = [ "show", "terminate", "stop", "start", "launch" ]
execCmds.sort().forEach( n=>{
  program.command(n, `${n} ${subject}`)
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
        throw new Error(`unknown cmd: cmd}` )
    }
  })
program.parse(process.argv);

#!/usr/bin/env node
"use strick"
const fs = require('fs'); 
const path = require("path");
var config = require('../lib/settings');
//var cidata = require('../lib/cidata')
//var cache = require('../lib/cache')
//var inquirer =  require('inquirer-promise')
const package = require('../package')
const subject = __filename.split('-').pop()

// Define the program globals
// const program = require('..lib/commanderGlobals')
var program = require('commander') 
 .version(package.version)
 .option('-p --profile <Name>', 'provider profile name', 
    process.env[package.name.toUpperCase() + "_PROFILE"])
 .option('-d --ciData <dataFile>', 'CIDATA project settings', process.env.CIDATA)
 .option('-c --config <path>', 'Config', config.path )
 .option('-D --debug', 'Debug messages')
 .option('-B --bash-completions', 'Generate bash-completion functions')

// exec (external) commands
var execCmds = [ "network", "vm", "storage", "security",  'user' ]
execCmds.sort().forEach( n=>{
  // name an exec command, like: ./bin/ccfoo-$n.js 
  program.command(n, `Act on ${n} subjects`)
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
        throw new Error(`unknown cmd: ${cmd}` )
    }
  })

// Hide dev/test command with an environment variable.
if (process.env.DEVTEST) {
   process.env.DEVTEST.trim().split(" ").forEach( n=>{
   // name an exec command, like: ./bin/ccfoo-$n.js 
   program.command(n, `Act on ${n} subjects`)
  })  
  program.command('test <task> [arg]')
   .description( "Test/developer function")
   .action( (task, arg, options)=>{
      let tasks = [ "login" ]
      program.debug && console.log('task:',task,'\narg: ', arg,'\noptions: ', options)
      let o = config
      let settings = o.localSettingsFile
      o.deleteSettingsFile
      switch (task) {
        case 'login' :
          console.log(JSON.stringify(config, null,2))
          break;
        default : 
          throw new Error(`unknown task: ${task}\n select from: ${tasks.join(", ")}`)
      }
    })
}
program.parse(process.argv);


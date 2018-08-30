#!/usr/bin/env node
"use strick"
const fs = require('fs'); 
const path = require("path");
const cfg = require('../lib/settings')
const package = require('../package')
const token = { aws: require('../lib/awsToken'), azure: require('../lib/azureToken')}
const cloud = { aws: require('../lib/aws'), azure: require('../lib/azure')}
global.__basedir = __dirname;
var program = require('commander') 
.version(package.version)

// inorder to validate settings, on load, it needs to be in an Async functions, hence main.
async function main() {
   config = await cfg.load( )
   
  // exec (external) commands
  var execCmds = [ "network", "vm", "storage", "security",  'user' ]
  execCmds.sort().forEach( n => {
    // name an exec command, like: ./bin/ccfoo-$n.js 
    program.command(n, `Act on ${n} subjects`)
  })  
  
  // action (built-in) commands 
  program.command('config <cmd> [key] [value]')
    .description( "Configure local settings: config [show|set <key value>|del <k>]")
    .option( '-p --profile <name>', 'Settings profile name')
    .action( (cmd, k, v, options) => cfg.action(program, config, cmd, k, v) )
  
  program.command('token <cmd> [lifetime]')
    .description( "Session token [show|get [lifetime]|del]")
    .option( '-p --profile <name>', 'Settings profile name')
    .action((cmd, lifetime, options) => {
      // load the profile again, this time with cloud providers.
       cfg.load(cloud).then(profile=> {
        token[config.provider].action({program, config: profile, cmd, lifetime})
       })
    })

  program.parse(process.argv);
}
main( ).catch((err) => {
  console.error("Error: %O", err);    
})


#!/usr/bin/env node
"use strick"
const fs = require('fs'); 
const path = require("path");
var cfg = require('../lib/settings')
var config = cfg.load()
const package = require('../package')
//const subject = __filename.split('-').pop()

var program = require('commander') 
 .version(package.version)
 

// exec (external) commands
var execCmds = [ "network", "vm", "storage", "security",  'user' ]
execCmds.sort().forEach( n=>{
  // name an exec command, like: ./bin/ccfoo-$n.js 
  program.command(n, `Act on ${n} subjects`)
})  

// action (built-in) commands 
program.command('config <cmd> [key] [value]')
  .description( "Configure local settings: config [show|set <key value>|del <k>]")
  .action( (cmd, k, v, options) => cfg.action(program, config, cmd, k, v) )

program.parse(process.argv);


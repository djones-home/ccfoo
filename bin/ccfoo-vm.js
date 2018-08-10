#!/usr/bin/env node
"use strick"
const package = require('../package')
const subject = __filename.split('-').pop().split('.')[0]

var program = require('commander') 
 .version(package.version)
 
// exec (external) commands
var execCmds = [ "show", "terminate", "stop", "start", "launch" ]
execCmds.sort().forEach( n=>{
  program.command(n, `${n} ${subject}`)
})  

program.parse(process.argv);

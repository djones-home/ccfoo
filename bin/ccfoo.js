#!/usr/bin/env node
"use strick"

const chalk = require('chalk');
const clear = require('clear');
const figlet = require('figlet');

const util = require('util');
const fs = require('fs'); 
const path = require("path");
const settings = require('../lib/settings')
const azureToken = require('../lib/azureToken')

const package = require('../package')
const log = console.log;
const out = process.stdout.write;


var program = require('commander') 
 .version(package.version)

 function banner() {
  log(
    chalk.white('FNMOC') +
      ' | ' +
      chalk.blue(package.name) +
      ' | ' +
      chalk.green(package.version) +
      ' | ' +
      chalk.red('profile: ' + settings.activeProfileName())
  );
  log(chalk.green(figlet.textSync('Cloud CLI', { horizontalLayout: 'full' })));
}
 

// exec (external) commands
// var execCmds = [ "network", "vm", "storage", "security",  'user' ]
// execCmds.sort().forEach( n=>{
//   // name an exec command, like: ./bin/ccfoo-$n.js 
//   program.command(n, `Act on ${n} subjects`)
// })  

// action (built-in) commands 
settings.initCommand(program);
azureToken.initCommand(program);

if ( process.argv.length <= 2) {
  banner();
  program.outputHelp();
}

program.parse(process.argv);


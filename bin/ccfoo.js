#!/usr/bin/env node
"use strick"
const fs = require('fs');
const path = require("path");
const cfg = require('../lib/settings')
const package = require('../package')
const token = { aws: require('../lib/awsToken'), azure: require('../lib/azureToken') }
const cloud = { aws: require('../lib/aws'), azure: require('../lib/azure') }
global.__basedir = __dirname;
var program = require('commander-completion')(require('commander'))
program.version(package.version)

// inorder to validate settings, on load, it needs to be in an Async functions, hence main.
async function main() {
  config = await cfg.load()

  // exec (external) commands
  var execCmds = ["network", "vm", "storage", "security", 'user']
  execCmds.sort().forEach(n => {
    // name an exec command, like: ./bin/ccfoo-$n.js 
    program.command(n, `Act on ${n} subjects`)
  })

  // action (built-in) commands 
  program.command('config <cmd> [key] [value]')
    .description("Configure local settings: config [show|get|set <key value>|del <k>]")
    .option('-p --profile <name>', 'Settings profile name')
    .action((cmd, k, v, options) => cfg.action(program, config, cmd, k, v))
    .completion((info,cb) => {
      let cl = (info.words.value[2] != 'show') ? ['show', 'set', 'get'] : Object.keys(config)
      let subcl = cl.filter(c => { return info.words.partialLeft === c.substr(0, info.words.partialLeft.length) });
      cb(null, subcl)
    });

  program.command('token <cmd> [lifetime]')
    .description("Session token [show|get [lifetime]|del]")
    .option('-p --profile <name>', 'Settings profile name')
    .action((cmd, lifetime, options) => {
      // load the profile again, this time with cloud providers.
      cfg.load(cloud).then(profile => {
        token[config.provider].action({ program, config: profile, cmd, lifetime })
      })
    });
  program
    .command('completion')
    .action(function () {
      program.completion({
        line: process.env.COMP_LINE || 'ccfoo config se',
        cursor: process.env.COMP_POINT || 15,
        
      });
     // progam.complete()
    });
  program.parse(process.argv);
}
main().catch((err) => {
  console.error("Error: %O", err);
})


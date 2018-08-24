#!/usr/bin/env node
"use strick"
const package = require('../package')
const subject = __filename.split('-').pop().split('.')[0]
const {show, terminate, stop, start, launch} = require('../lib/vm')
const { incVerbose } = require('../lib/common')
const cfg = require('../lib/settings')
const config = cfg.load()

async function main() {
  var program = require('commander') 
   .version(package.version)
   .option(`-n --Name <${subject}Name>`, `Specify ${subject} name`)
   .option(`-u --unit <regexp-filter>`, 'RegExp filter on Id')
   .option('-v, --verbose [1]', 'Verbose log level', incVerbose)
   .option('-t --ttl <seconds>', 'Cache  Time-To-Live ', config.ttl || 600)
   .option('-o --output <table|json>', 'Type of output', config.output || 'json')
  
   program.command('launch')
   .description('Launch VM instance')
   .action( () => {
     launch({subject: 'vm', program, config})
   })
   program.command('show')
   .description('Show VM instances')
   .action( () => {
     show({subject: 'vm', program, config})
   })
   program.command('stop')
   .description('Stop VM instance')
   .action( () => {
     stop({subject: 'vm', program, config})
   })
   program.command('start')
   .description('Start VM instance')
   .action( () => {
     start({subject: 'vm', program, config})
   })
   program.command('terminate')
   .description('Teriminate VM instance')
   .action( () => {
     terminate({subject: 'vm', program, config})
   })
  
   // exec (external) commands
  
  ////var execCmds = [ "show", "terminate", "stop", "start", "launch" ]
  //execCmds.sort().forEach( n=>{
  //  program.command(n, `${n} ${subject}`)
  //})  
  
  program.parse(process.argv);
}
main().catch(e => { console.error(e); process.exit(1) })

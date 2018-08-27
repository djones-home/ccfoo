#!/usr/bin/env node
"use strick"
const package = require('../package')
//const subject = __filename.split('-').pop().split('.')[0]
const subject = 'network'
const {networkShow, networkCreate, networkDelete } = require('../lib/network')
const { incVerbose } = require('../lib/common')
const cfg = require('../lib/settings')

async function main() {
  const config = await cfg.load()

  var program = require('commander') 
   .version(package.version)
   .option(`-n --Name <${subject}Name>`, `Specify ${subject} name`)
   .option(`-u --unit <regexp-filter>`, 'RegExp filter on Id')
   .option('-v, --verbose [1]', 'Verbose log level', incVerbose)
   .option('-t --ttl <seconds>', 'Cache  Time-To-Live ', config.ttl || 600)
   .option('-o --output <table|json>', 'Type of output', config.output || 'json')
  
  program.command('create')
  .description('create Network instance')
  .action( () => {
    networkCreate({subject, program, config})
  })
  program.command('show')
  .description('Show Nework instances')
  .action( () => {
    networkShow({subject: 'network', program, config})
  })
  //program.command('stop')
  //.description('Stop network instance')
  //.action( () => {
  //  stop({subject, program, config})
  //})
  //program.command('start')
  //.description('Start network instance')
  //.action( () => {
  //  start({subject, program, config})
  //})
  program.command('delete')
  .description('Delete network instance')
  .action( () => {
    networkDelete({subject, program, config})
  })
  
   // exec (external) commands
  
  ////var execCmds = [ "show", "terminate", "stop", "start", "launch" ]
  //execCmds.sort().forEach( n=>{
  //  program.command(n, `${n} ${subject}`)
  //})  
  
  program.parse(process.argv);
}

main().catch(e => { console.error(e); process.exit(1) })

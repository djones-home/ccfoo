#!/usr/bin/env node
"use strick"
const package = require('../package')
const { incVerbose } = require('../lib/common')
const cfg = require('../lib/settings')
const cidata = require('../lib/cidata')
const subject = 'vm'
const cloud = { azure: require('../lib/azure'), aws: require('../lib/aws') }
async function main() {
  // cfg.load looks for a -p or --profile option, now, before commander kicks in.
  const config = await cfg.load(cloud)

  var program = require('commander') 
   .version(package.version)
   .option(`-n --Name <${subject}Name>`, `Specify ${subject} name`)
   .option(`-p --profile <settingsKeyName>`, `Specify ${subject} name`, config.profileName)
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
     cloud[config.provider].show({subject: 'vm', program, config})
   })
   program.command('stop')
   .description('Stop VM instance')
   .action( () => {
     cloud[config.provider].stop({subject: 'vm', program, config})
   })
   program.command('start')
   .description('Start VM instance')
   .action( () => {
     cloud[config.provider].start({subject: 'vm', program, config})
   })
   program.command('terminate')
   .description('Teriminate VM instance')
   .action( () => {
     cloud[config.provider].terminate({subject: 'vm', program, config})
   })
  
   // exec (external) commands
  
  ////var execCmds = [ "show", "terminate", "stop", "start", "launch" ]
  //execCmds.sort().forEach( n=>{
  //  program.command(n, `${n} ${subject}`)
  //})  
  
  program.parse(process.argv);
}
main().catch(e => { console.error(e); process.exit(1) })

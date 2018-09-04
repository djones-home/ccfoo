#!/usr/bin/env node
"use strick"
const package = require('../package')
//const subject = __filename.split('-').pop().split('.')[0]
const subject = 'network'
const cfg = require('../lib/settings')
const cidata = require('../lib/cidata')
const cloud = { azure: require('../lib/azure/network'), aws: require('../lib/aws/network') }

async function main() {
  const config = await cfg.load(cloud)
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
    cloud[config.provider].networkShow({subject: 'network', program, config})
  })
  program.command('delete')
  .description('Delete network instance')
  .action( () => {
    cloud[config.provider].networkDelete({subject, program, config})
  })
  
  
  program.parse(process.argv);
}
function incVerbose(v, total) {
  return total + 1;
}
main().catch(e => { console.error(e); process.exit(1) })

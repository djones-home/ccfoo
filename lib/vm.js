const cloud = {}
cloud['azure'] = require('../lib/azure')
cloud['aws'] = require('../lib/aws')
var subject = 'vm'

const fs = require('fs')

async function launch({subject,config,program,...rest}) {
     return cloud[config.provider].launch({subject,config,program, ...rest})
}
async function stop({subject,config,program,...rest}) {
  return await cloud[config.provider].stop({subject,config,program, ...rest})
}
async function start({subject,config,program,...rest}) {
  return await cloud[config.provider].start({subject,config,program, ...rest})
}
async function terminate({subject,config,program,...rest}) {
  return await cloud[config.provider].terminate({subject,config,program, ...rest})
}
async function show({subject, config, program, ...rest}) {
  console.log(__filename, 'show')
  let res =  await cloud[config.provider].show({subject,config,program, ...rest})
  console.log( 
    cloud[config.provider].output({program,data:res,config,subject})
  )
}
// read project data, or settings share by all members of the project (no creds in cidata)
if (process.env.CIDATA) {
  var cidata = JSON.parse(fs.readFileSync(process.env.CIDATA))
} else {
  var cidata = require('../tests/data/projectSettings')
}

//config.group = {  name: "FOOBAR", properties: {}}

module.exports = {
  launch:  launch,
  terminate: terminate,
  stop: stop,
  start: start,
  show: show
}

const cloud = {}
cloud['azure'] = require('../lib/azure/network')
cloud['aws'] = require('../lib/aws/network')

const fs = require('fs')

async function networkCreate({subject,config,program,...rest}) {
     return cloud[config.provider].networkCreate({subject,config,program, ...rest})
}
//async function stop({subject,config,program,...rest}) {
//  return await cloud[config.provider].stop({subject,config,program, ...rest})
//}
//async function start({subject,config,program,...rest}) {
//  return await cloud[config.provider].start({subject,config,program, ...rest})
//}
async function networkDelete({subject,config,program,...rest}) {
  return await cloud[config.provider].networkDelete({subject,config,program, ...rest})
}
async function networkShow({subject, config, program, ...rest}) {
  let res =  await cloud[config.provider].networkShow({subject,config,program, ...rest})
  //console.log( 
  //  cloud[config.provider].output({program,data:res,config,subject})
  //)
}
// read project data, or settings share by all members of the project (no creds in cidata)
if (process.env.CIDATA) {
  var cidata = JSON.parse(fs.readFileSync(process.env.CIDATA))
} else {
  var cidata = require('../test/data/projectSettings')
}


module.exports = {
  networkCreate:  networkCreate,
  networkDelete: networkDelete,
  networkShow: networkShow
}

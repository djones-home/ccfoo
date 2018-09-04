const AWS = require('aws-sdk');
const cache = require('../lib/cache')
async function ytbd({program,subject,config,...rest}) { console.log("YTBD")}
async function launch({program,subject,config,...rest}) { console.log("YTBD")}
async function stop({program,subject,config,...rest}) { console.log("YTBD")}
async function start({program,subject,config,...rest}) { console.log("YTBD")}
async function terminate({program,subject,config,...rest}) { console.log("YTBD")}
//async function listVMs({program,subject,config,...rest}) { console.log("YTBD")}
async function listResources({program,subject,config,...rest}) { console.log("YTBD")}
async function output({program,subject,config,data,...rest}) { console.log(data)}
async function validateConfig(config) { return config}
// reminder me to set these or
//if(! process.env.AWS_SDK_LOAD_CONFIG  ||  ! process.env.AWS_PROFILE ) {
//  console.error( "export AWS_SDK_LOAD_CONFIG=true ")
//  console.error( "export AWS_PROFILE=default_sts ")
//  process.exit(1)
//}
async function getVMs({program,config}) {
  let cId = cache.id('getVMs',config)
  let d = cache.cGet(cId, program.ttl )
  if ( ! d ) {    
    d = await loadVMs({program,config})
    cache.cPut(cId, d)
  }
  return d
}
async function loadVMs() {
 // let request = new AWS.EC2().describeInstances({IncludeAllInstances: true})
  let request = new AWS.EC2().describeInstances()
  let d = await request.promise();
  return d
}
async function showVMs({program,config}) {
  d = await getVMs({program,config})
  process.stdout.write(JSON.stringify(d))
}

async function listVMs({program,subject,config,...rest}) {

}
// Create a promise on S3 service object
//var bucketPromise = new AWS.S3({apiVersion: '2006-03-01'}).createBucket({Bucket: bucketName}).promise();

async function validateConfig(config) {
  if(! process.env.AWS_SDK_LOAD_CONFIG  ||  ! process.env.AWS_PROFILE ) {
    console.error('ERROR: env missing:\n  export AWS_SDK_LOAD_CONFIG=ture AWS_PROFILE=yourProfileName')
    process.exit(1)
  }
  // cache.id uses: id, location,so set them to the 
  config.location = AWS.config.region.toString() 
  config.id = AWS.config.accessKeyId
  return(config)
}

module.exports = {
  listResources, listVMs,
  show: showVMs,
  launch: launch,
  stop: stop,
  start: start, output,
  terminate: terminate,
  validate: validateConfig
}
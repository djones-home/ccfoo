const msRestAzure = require("ms-rest-azure");
const { ComputeManagementClient } = require("azure-arm-compute");
const resourceManagement = require('azure-arm-resource')
const cache = require('../lib/cache')
//const domain = process.env.DOMAIN || config.DOMAIN || "";
//const subscriptionId = process.env.AZURE_SUBSCRIPTION_ID || config.AZURE_SUBSCRIPTION_ID || config.id ||"";
const AzureEnvironment = msRestAzure.AzureEnvironment;
// Returns credential, added to config.
async function getCreds( config  ) {
  const loginOptions = { environment: AzureEnvironment[config.environmentName] };
  const username =  process.env.AZURE_USERNAME || config.AZURE_USERNAME || config.username || "";
  const password = process.env.AZURE_PASSWORD || config.AZURE_PASSWORD || config.password || "";

  //let creds = await tokens.get(loginOptions)
  config.creds = await msRestAzure.loginWithUsernamePassword(username, password, loginOptions );
  //console.log(JSON.stringify(config.creds,null,2))
  return config.creds
}
async function getVMlist(program,config) {
  let ep = msRestAzure.AzureEnvironment[config.environmentName].resourceManagerEndpointUrl
  const creds = await getCreds(config)
  const client = new ComputeManagementClient(creds, config.id, 
    AzureEnvironment.AzureUSGovernment.resourceManagerEndpointUrl);
  return await client.virtualMachines.listAll()
}


async function getResourcesList(program,config) {
  let ep = msRestAzure.AzureEnvironment[config.environmentName].resourceManagerEndpointUrl
  const creds = await getCreds(config)
  let  client = new resourceManagement.ResourceManagementClient(creds, config.id, ep)
  return await client.resources.list()
}

// for Azure filter by name match
// for Azure filter the id by RegExp(program.unit)
function  filterResources(program, d) {
  if ( program.Name )  d = d.filter(e =>  e.name == program.Name )
  if ( program.unit ) d =  d.filter(e => (new RegExp(program.unit).test(e.id)))
  return d
}
async function listResources({program, config}) {
  // make an id (cmdId) for indexing cashe.
  let cmdId = cache.id(`az.rm.res.list`)
  let d = cache.cGet(cmdId, program.ttl )
  if ( ! d ) {    
    d = getResourcesList(program,config)
    cache.cPut(cmdId, d)
  }
  let df = filterResources(program, d)
  console.log(JSON.stringify(df,null,2));

  if(program.verbose > 0 )  console.error(
     `level-${program.verbose}: ${subject} count: ${df.length} of ${d.length} ${subject}s W/ filter :`,
      (program.unit ? ` id by regexp /${program.unit}/,` : ''),
      (program.Name ? ` name == ${program.Name}\n` : ''),
      (program.verbose > 1 ? program : "")
    )
}

async function listVMs({program,config}) {  
  let d = await getVMlist( program,config)
  console.log(JSON.stringify(d,null,2));
}
async function show({program,subject,config,...rest}) { console.log("YTBD")}
async function launch({program,subject,config,...rest}) { console.log("YTBD")}
async function stop({program,subject,config,...rest}) { console.log("YTBD")}
async function start({program,subject,config,...rest}) { console.log("YTBD")}
async function terminate({program,subject,config,...rest}) { console.log("YTBD")}

module.exports = {
  listResources, listVMs,
  show: show,
  launch: launch,
  stop: stop,
  start: start,
  terminate: terminate
}
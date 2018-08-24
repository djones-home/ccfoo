const msRestAzure = require("ms-rest-azure");
const { ComputeManagementClient } = require("azure-arm-compute");
const resourceManagement = require('azure-arm-resource')
const cache = require('../lib/cache')
const Table = require('easy-table')

//const domain = process.env.DOMAIN || config.DOMAIN || "";
//const subscriptionId = process.env.AZURE_SUBSCRIPTION_ID || config.AZURE_SUBSCRIPTION_ID || config.id ||"";
const AzureEnvironment = msRestAzure.AzureEnvironment;
// Returns credential, added to config.
async function getCreds({ config}  ) {
  const loginOptions = { environment: AzureEnvironment[config.environmentName] };
  const username =  process.env.AZURE_USERNAME || config.AZURE_USERNAME || config.username || "";
  const password = process.env.AZURE_PASSWORD || config.AZURE_PASSWORD || config.password || "";

  //let creds = await tokens.get(loginOptions)
  config.creds = await msRestAzure.loginWithUsernamePassword(username, password, loginOptions );
  //console.log(JSON.stringify(config.creds,null,2))
  return config.creds
}
async function loadVMs({program,config}) {
  let ep = msRestAzure.AzureEnvironment[config.environmentName].resourceManagerEndpointUrl
  const creds = await getCreds({config})
  const client = new ComputeManagementClient(creds, config.id, 
    AzureEnvironment.AzureUSGovernment.resourceManagerEndpointUrl);
  return await client.virtualMachines.listAll()
}

async function getVMs({program,config}) {
  let cId = cache.id(`az.getVMs`)
  let d = cache.cGet(cId, program.ttl )
  if ( ! d ) {    
    d = await loadVMs({program,config})
    cache.cPut(cId, d)
  }
  return d
}

async function loadResource({program,config}) {
  let ep = msRestAzure.AzureEnvironment[config.environmentName].resourceManagerEndpointUrl
  const creds = await getCreds({config})
  let  client = new resourceManagement.ResourceManagementClient(creds, config.id, ep)
  return await client.resources.list()
}

// for Azure filter by name match
// for Azure filter the id by RegExp(program.unit)

async function filterResources({program, config, ...rest}) {
  let d = await listResources({program, config})
  if ( program.Name )  d = d.filter(e =>  e.name == program.Name )
  if ( program.unit ) d =  d.filter(e => (new RegExp(program.unit).test(e.id)))
  if(program.verbose > 0 )  console.error(
    `level-${program.verbose}: ${subject} count: ${df.length} of ${d.length} ${subject}s W/ filter :`,
     (program.unit ? ` id by regexp /${program.unit}/,` : ''),
     (program.Name ? ` name == ${program.Name}\n` : ''),
     (program.verbose > 1 ? program : "")
   )
  return d
}

async function getResources({program, config}) {
  // make a better cache id (cId) for indexing cashe, this is sure to break
  // The id should include more unique-ness, but this will do for now.
  let cId = cache.id(`az.rm.res.list`)
  let d = cache.cGet(cId, program.ttl )
  if ( ! d ) {    
    d = await loadResources({program,config})
    cache.cPut(cId, d)
  }
  return d
}
function outputVMs({d, program}) {
  if ( program.output == 'json') {
     console.log(JSON.stringify(d,null,2)) 
  } else {
    let t = new Table
    let i =1
    d.forEach( e => {
      let {hardwareProfile: hp, storageProfile: sp, osProfile: op,
          networkProfile: np, diagnosticsProfile: dp} = e
    
      t.cell('##', i )
      let { publisher: p, offer: o, sku: s, version: v   } = sp.imageReference
      t.cell('name', e.name )
      t.cell('location', e.location )
      t.cell('vmSize', hp.vmSize) 
      t.cell('image', [p,o,s,v].join('-'))
      t.cell('GB', sp.osDisk.diskSizeGB)
      if (sp.osDisk.managedDisk)
        t.cell("storType", sp.osDisk.managedDisk.storageAccountType);
        t.newRow()
      i++;
    })
    console.log(t.toString())
  }
}

async function showVMs({program,config}) {  
  let d = await getVMs( {program,config})
  outputVMs({d, config, program})
    
}
async function show({program,subject,config,...rest}) { console.log("YTBD")}
async function launch({program,subject,config,...rest}) { console.log("YTBD")}
async function stop({program,subject,config,...rest}) { console.log("YTBD")}
async function start({program,subject,config,...rest}) { console.log("YTBD")}
async function terminate({program,subject,config,...rest}) { console.log("YTBD")}
async function output({program,subject,config,data,...rest}) { 
  console.log(program.output != 'json' ? tableOuput({data}) : data)
}
async function validateConfig({config}) { return config}

module.exports = {
  show: showVMs,
  launch: launch,
  stop: stop,
  start: start,
  output,
  terminate: terminate,
  validate: validateConfig
}

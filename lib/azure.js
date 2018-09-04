const msRestAzure = require("ms-rest-azure");
const { ComputeManagementClient } = require("azure-arm-compute");
const resourceManagement = require('azure-arm-resource')
const { NetworkManagementClient } = require('azure-arm-network')
const cache = require('../lib/cache')
const Table = require('easy-table')
const AzureEnvironment = msRestAzure.AzureEnvironment;
const cidata = require('../lib/cidata')
const token = require('./azureToken')
const fs = require('fs')

//# Common functions for an Azure cloud provider
// getCreds Returns azure credential, from however pw, access_token, ....
async function getCreds({config}) {
  const tok = new token.MyTokenCache(config.credentialsStore)
  
  const loginOptions = { 
    environment: AzureEnvironment[config.environmentName], 
    tokenCache: tok
  };
  
 if ( config.devlogin && !tok.empty()) {
   loginOptions.username = token.userId;

   config.creds = new msRestAzure.DeviceTokenCredentials(loginOptions);

 } else {
    const username =  process.env.AZURE_USERNAME || config.AZURE_USERNAME || config.username || "";
    const password = process.env.AZURE_PASSWORD || config.AZURE_PASSWORD || config.password || "";
  
    config.creds = await msRestAzure.loginWithUsernamePassword(username, password, loginOptions );
    tok.save();
  }
  
  return config.creds
}

// listAll, then get instanceView to obtain the runState
async function loadVMs({program,config}) {
  let ep = msRestAzure.AzureEnvironment[config.environmentName].resourceManagerEndpointUrl
  const creds = await getCreds({config})
  const client = new ComputeManagementClient(creds, config.id, 
    AzureEnvironment.AzureUSGovernment.resourceManagerEndpointUrl);
    // listAll() options
  let l =  await client.virtualMachines.listAll()
  //ref: https://stackoverflow.com/questions/43760323/node-js-azure-sdk-getting-the-virtual-machine-state
  // This is going to be slow - going back to get the state of each VM, one at at a time could be painful.
  // Just for few crutial properties like the run state
  return await Promise.all(  l.map( vm=> client.virtualMachines.get(vm.id.split('/')[4], vm.name, 
     {expand: 'instanceView'})) )
}

async function getNetwork({program,config}) {
  let cId = cache.id('az.getnetwork', config)
  let d = cache.cGet(cId, program.ttl )
  if ( ! d ) {    
    d = await loadNetwork({program,config})
    cache.cPut(cId, d)
  }
  return d
}


async function getVMs({program,config}) {
  let cId = cache.id('az.getVMs',config)
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
async function deploy({program,config,template, parameters, resource_group}) {
  let ep = msRestAzure.AzureEnvironment[config.environmentName].resourceManagerEndpointUrl
  const creds = await getCreds({config})
  let  client = new resourceManagement.ResourceManagementClient(creds, config.id, ep)
  //return await client.resources.list()
  console.log("arm client")
  //await client.resource_groups.create_or_update(resource_group, { location: config.location})
  // let deployment = Azure::ARM::Resources::Models::Deployment.new
  // deployment = Azure::ARM::Resources::Models::Deployment.new
  // deployment.properties = Azure::ARM::Resources::Models::DeploymentProperties.new
  // deployment.properties.template = JSON.parse(template)
  // deployment.properties.mode = Azure::ARM::Resources::Models::DeploymentMode::Incremental

  // # build the deployment template parameters from Hash to {key: {value: value}} format
  // deploy_params = File.read(File.expand_path(File.join(__dir__, 'parameters.json')))
  // deployment.properties.parameters = JSON.parse(deploy_params)["parameters"]

  // # put the deployment to the resource group
  // @client.deployments.create_or_update(@resource_group, 'azure-sample', deployment)
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
      let ps = null
      let {hardwareProfile: hp, storageProfile: sp, osProfile: op,
          networkProfile: np, diagnosticsProfile: dp, instanceView: iv } = e
      if (iv) {
        ps = iv.statuses.filter(status => /PowerState/.test(status.code))[0].code.split('/')[1]
      }
      t.cell('##', i )
      let { publisher: p='', offer: o='', sku: s='', version: v=''   } = sp.imageReference
       console.log('p,o,s,v=',typeof(p),p.substring,o,s,v)
      t.cell('name', e.name )
      t.cell('State', ps || "unknown")
      t.cell('location', e.location )
      t.cell('vmSize', hp.vmSize) 
      t.cell('image', [p,o,s,v].map(s =>s.substring(0,4)).join('-'))
      //t.cell('image', [p,o,s,v].join('-'))
      t.cell('GB', sp.osDisk.diskSizeGB)
      if (sp.osDisk.managedDisk)
        t.cell("storeType", sp.osDisk.managedDisk.storageAccountType);
        t.newRow()
      i++;
    })
    console.log(t.toString())
  }
}

async function loadNetwork({program,config}) {
  let ep = msRestAzure.AzureEnvironment[config.environmentName].resourceManagerEndpointUrl
  const creds = await getCreds({config})
  const client = new NetworkManagementClient(creds, config.id, 
    AzureEnvironment.AzureUSGovernment.resourceManagerEndpointUrl);
  let network = {}
  network.networks = await client.virtualNetworks.listAll()
  network.interfaces =  await client.networkInterfaces.listAll()
  network.networkSecurityGroups =  await client.networkSecurityGroups.listAll()
  //console.log(JSON.stringify(network,null,2))
  return network
}
async function showVMs({program,config}) {  
  let d = await getVMs( {program,config})
  outputVMs({d, config, program})
    
}
async function launch({program,subject,config,...rest}) { 
    // get the settings for program.Name
   if (! program.Name ) {
     console.log("Name ?: ", cidata.listVm({data: config.cidata}).join(' '))
     return
   }
   let roleData = cidata.getVm({data: config.cidata, name: program.Name})
   console.log("Paramters ", program.Name, roleData)
   
   let template = fs.readFileSync( role.template ) || require(`../templates/${config.provider}/vm`)
   await deploy({program,config,template, parameters, resource_group})

   
}
async function show({program,subject,config,...rest}) { console.log("YTBD")}

async function stop({program,subject,config,...rest}) { console.log("YTBD")}
async function start({program,subject,config,...rest}) { console.log("YTBD")}
async function terminate({program,subject,config,...rest}) { console.log("YTBD")}
async function output({program,subject,config,data,...rest}) { 
  console.log(program.output != 'json' ? tableOuput({data}) : data)
}
async function validateConfig(p) { 
  // Insure there is a credentialsStore path.
  if (! p.credentialsStore) 
    p.credentialsStore = path.join( path.basename(p.localSettingsFile), 'az-accessTokens.json') 
  if (! p.location ) p.location = 'usgovarizona'
  if (! p.environmentName ) environmentName = 'AzureUSGovernment'
  if (! p.tenantId ) p.tenantId = 'Your-Azure-ADD-tenantId'
  if (! p.id ) p.id = 'Your-Azure-SubscriptionId'
  if (! p.username ) p.username = 'jdoe@exmaple.onmicrosoft.com'
  return p
}

module.exports = {
  getCreds: getCreds,
  show: showVMs,
  launch: launch,
  stop: stop,
  start: start,
  output,
  terminate: terminate,
  validate: validateConfig,
  getNetwork
}

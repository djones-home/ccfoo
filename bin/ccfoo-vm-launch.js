#!/usr/bin/env node
const config = require('../lib/settings').load()
const msRestAzure = require("ms-rest-azure");
const { ComputeManagementClient } = require("azure-arm-compute");
const resourceManagement = require('azure-arm-resource')
const cache = require('../lib/cache')
const package = require('../package')
const profile = process.env[`${package.name.toUpperCase()}_PROFILE`] || config.profile || "default"
const domain = process.env.DOMAIN || config.DOMAIN || "";
const subscriptionId = process.env.AZURE_SUBSCRIPTION_ID || config.AZURE_SUBSCRIPTION_ID || config.id ||"";
const profiles = require('../lib/profiles')
const program = require('commander')
const tokens = require('../lib/accessTokens')
const fs = require('fs')

var subject = __filename.split('-')[1]
// read project data, or settings share by all members of the project (no creds in cidata)
if (process.env.CIDATA) {
  var cidata = JSON.parse(fs.readFileSync(process.env.CIDATA))
} else {
  var cidata = require('../tests/data/projectSettings')
}
async function listResource() {
  // make an id (cmdId) for indexing cashe.
  let cmdId = `${(profiles.env|| "az") + subject}.rm.res.list`
  let d = cache.cGet(cmdId, program.ttl )
  if ( ! d ) {
    const loginOptions = { environment: AzureEnvironment.AzureUSGovernment };
    //const creds = await msRestAzure.loginWithServicePrincipalSecret(clientId, secret, domain, loginOptions);
    let creds = await msRestAzure.loginWithUsernamePassword(username, password, loginOptions );
    const client = new resourceManagement.ResourceManagementClient(creds, subscriptionId, AzureEnvironment.AzureUSGovernment.resourceManagerEndpointUrl);
    d = await client.resources.list( );
    cache.cPut(cmdId, d)
  }
  let total = d.length
  // for Azure filter by name match
  if ( program.Name )  d = d.filter(e =>  e.name == program.Name )
  // for Azure filter the id by RegExp(program.unit)
  if ( program.unit ) d = d.filter(e => (new RegExp(program.unit).test(e.id)))
  
  console.log(JSON.stringify(d,null,2));
  if(program.verbose > 0 )  console.error(
     `level-${program.verbose}: ${subject} count: ${d.length} of ${total} ${subject}s W/ filter :`,
      (program.unit ? ` id by regexp /${program.unit}/,` : ''),
      (program.Name ? ` name == ${program.Name}\n` : ''),
      (program.verbose > 1 ? program : "")
    )
}

config.group = {  name: "FOOBAR", properties: {}}

async function getCreds( config  ) {
  //let cloudName = 'AzureUSGovernment'
  const loginOptions = { environment: msRestAzure.AzureEnvironment[config.cloudName] };
  const username =  process.env.AZURE_USERNAME || config.AZURE_USERNAME || config.username || "";
  const password = process.env.AZURE_PASSWORD || config.AZURE_PASSWORD || config.password || "";

    //let creds = await tokens.get(loginOptions)
  config.creds = await msRestAzure.loginWithUsernamePassword(username, password, loginOptions );
  return creds
}
async function rmDeploy( config, creds ) {
  //const creds = await msRestAzure.loginWithServicePrincipalSecret(clientId, secret, domain, loginOptions);
  // config.id = subscriptionId
  let endpoint = msRestAzure.AzureEnvironment[config.cloudName].resourceManagerEndpointUrl
  const client = new resourceManagement.ResourceManagementClient(creds, config.id, endpoint );

  await client
    .resourceGroups
    .createOrUpdate(config.group.name, config.group.properties)

  var deploymentParameters = {
              "properties": {
                  "parameters": {},
                  "template": getAzTemplate(config, 'vm', program.Name ),
                  "mode": "Incremental"
              }
          };
  // list resource, see if rg exist, or create. Determine roleName-index
  // Define a unique deployment name
  var deploymentName = `${cidata.Project.Name}-${program.Name}-${i}`;
  // Render template YTBD, so just take it from the file
  // var template = await renderTemplate(config, subject, roleName )
  var template = JSON.parse(fs.readFileSync(config.template.sharedResourcesPath, 'utf8'));
       
  await client.resourceGroups.createOrUpdate(cidata.Project.Name, config.group.properties)
  await client.deployments.createOrUpdate(rgName, deploymentName, deploymentParameters)
}

function getAzTemplate(config, subj, name ){
    profile
}
function increaseVerbosity(v, total) {
  return total + 1;
}

program
  .version(package.version)
  .option(`-n --Name <${subject}Name>`, `Specify ${subject} name`)
  .option(`-u --unit <regexp-filter>`, 'RegExp filter on Id')
  .option('-v, --verbose [1]', 'Verbose log level', increaseVerbosity)
  .option('-t --ttl <seconds>', 'Cache  Time-To-Live ', config.ttl || 600)

  program.parse(process.argv)

rmDeploy( ).catch((err) => {
      console.error("An error occurred: %O", err);    
})

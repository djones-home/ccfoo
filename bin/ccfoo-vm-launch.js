#!/usr/bin/env node
const config = require('../lib/settings')
const msRestAzure = require("ms-rest-azure");
const { ComputeManagementClient } = require("azure-arm-compute");
const resourceManagement = require('azure-arm-resource')
const cache = require('../lib/cache')
const package = require('../package')
const AzureEnvironment = msRestAzure.AzureEnvironment;
const clientId = process.env.CLIENT_ID || config.CLIENT_ID || "";
const secret = process.env.APPLICATION_SECRET || config.APPLICATION_SECRET || "";
const domain = process.env.DOMAIN || config.DOMAIN || "";
const username =  process.env.AZURE_USERNAME || config.AZURE_USERNAME || config.username || "";
const password = process.env.AZURE_PASSWORD || config.AZURE_PASSWORD || config.password || "";
const subscriptionId = process.env.AZURE_SUBSCRIPTION_ID || config.AZURE_SUBSCRIPTION_ID || config.id ||"";
const profiles = require('../lib/profiles')
const program = require('commander')
const tokens = require('../lib/accessTokens')

async function main() {
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
  if ( program.unit) d = d.filter(e => (new RegExp(program.unit).test(e.id)))
  
  console.log(JSON.stringify(d,null,2));
  if(program.verbose > 0 )  console.error(
     `level-${program.verbose}: ${subject} count: ${d.length} of ${total} ${subject}s W/ filter :`,
      (program.unit ? ` id by regexp /${program.unit}/,` : ''),
      (program.Name ? ` name == ${program.Name}\n` : ''),
      (program.verbose > 1 ? program : "")
    )
}

async function resourcDeploy(client, config, subject, roleName ) {
  const loginOptions = { environment: AzureEnvironment.AzureUSGovernment };
  //const creds = await msRestAzure.loginWithServicePrincipalSecret(clientId, secret, domain, loginOptions);
  //let creds = await tokens.get(loginOptions)
  let creds = await msRestAzure.loginWithUsernamePassword(username, password, loginOptions );
  const client = new resourceManagement.ResourceManagementClient(creds, subscriptionId, AzureEnvironment.AzureUSGovernment.resourceManagerEndpointUrl);

  await client
            .resourceGroups
            .createOrUpdate(config.group.name, config.group.properties)

  var deploymentParameters = {
              "properties": {
                  "parameters": {},
                  "template": template,
                  "mode": "Incremental"
              }
          };
  // list resource, see if rg exist, or create. Determine roleName-index
  // Define a unique deployment name
  var deploymentName = `${config.group.prefix}-${roleName}-${i}`;
  // Render template YTBD, so just take it from the file
  // var template = await renderTemplate(config, subject, roleName )
  var template = JSON.parse(fs.readFileSync(config.template.sharedResourcesPath, 'utf8'));
       
  await client.resourceGroups.createOrUpdate(config.group.name, config.group.properties)
  await client.deployments.createOrUpdate(rgName, deploymentName, deploymentParameters)

var subject = __filename.split('-')[1]

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

main( ).catch((err) => {
      console.error("An error occurred: %O", err);    
})


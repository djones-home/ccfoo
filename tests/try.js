#!/usr/bin/env node
const config = require('../lib/settings').load()
const msRestAzure = require("ms-rest-azure");
const { ComputeManagementClient } = require("azure-arm-compute");
const cache = require('../lib/cache')
const package = require('../package')
const AzureEnvironment = msRestAzure.AzureEnvironment;
const clientId = process.env.CLIENT_ID || config.CLIENT_ID || '';
const secret =
  process.env.APPLICATION_SECRET || config.APPLICATION_SECRET || '';
const domain = process.env.DOMAIN || config.DOMAIN || '';
const username =
  process.env.AZURE_USERNAME || config.AZURE_USERNAME || config.username || '';
const password =
  process.env.AZURE_PASSWORD || config.AZURE_PASSWORD || config.password || '';
const subscriptionId =
  process.env.AZURE_SUBSCRIPTION_ID ||
  config.AZURE_SUBSCRIPTION_ID ||
  config.id ||
  '';
const profiles = require('../lib/profiles');
async function main() {
  let cmdId = `${(profiles.env || 'az') + subject}listAll`;
  let vms = cache.cGet(cmdId, 600);
  if (!vms) {
    const loginOptions = { environment: AzureEnvironment.AzureUSGovernment };
    //const creds = await msRestAzure.loginWithServicePrincipalSecret(clientId, secret, domain, loginOptions);
    let creds = await msRestAzure.loginWithUsernamePassword(
      username,
      password,
      loginOptions
    );
    const client = new ComputeManagementClient(
      creds,
      subscriptionId,
      AzureEnvironment.AzureUSGovernment.resourceManagerEndpointUrl
    );
    vms = await client.virtualMachines.listAll();
    cache.cPut(cmdId, vms);
  }
  let total = vms.length;
  // for Azure filter by name match
  if (program.Name) vms = vms.filter(e => e.name == program.Name);
  // for Azure filter the id by RegExp(program.unit)
  if (program.unit)
    vms = vms.filter(e => e.id && new RegExp(program.unit).test(e.id));

  console.log(JSON.stringify(vms, null, 2));
  if (program.verbose > 0)
    console.error(
      `level-${program.verbose}: vm count: ${
        vms.length
      } of ${total} ${subject}s W/ filter :\n`,
      program.unit ? `, id by regexp /${program.unit}/\n` : '',
      program.Name ? `, Name == ${program.Name}\n` : '',
      program.verbose > 1 ? program : ''
    );
}
var subject = 'vm';
function increaseVerbosity(v, total) {
  return total + 1;
}

const program = require('commander');
program
  .version(package.version)
  .option(`-n --Name <${subject}Name>`, `Specify ${subject} Name`)
  .option(
    `-u --unit <${subject}Unit>`,
    'Organizational parent-container|filterRE|id'
  )
  .option(
    '-v, --verbose',
    'Verbose, repeat to increase log level',
    increaseVerbosity,
    0
  );

//program.command("xx*").action( (c,o)=> {
//  console.error('Unknown command parameter: ', c)
//  process.exit(1)
//})
program.parse(process.argv);

main().catch(err => {
  console.error('An error occurred: %O', err);
});

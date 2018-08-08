const config = require('../lib/settings')
const msRestAzure = require("ms-rest-azure");
const { ComputeManagementClient } = require("azure-arm-compute");
const cache = require('../lib/cache')

const AzureEnvironment = msRestAzure.AzureEnvironment;
const clientId = process.env.CLIENT_ID || config.CLIENT_ID || "";
const secret = process.env.APPLICATION_SECRET || config.APPLICATION_SECRET || "";
const domain = process.env.DOMAIN || config.DOMAIN || "";
const username =  process.env.AZURE_USERNAME || config.AZURE_USERNAME || config.username || "";
const password = process.env.AZURE_PASSWORD || config.AZURE_PASSWORD || config.password || "";
const subscriptionId = process.env.AZURE_SUBSCRIPTION_ID || config.AZURE_SUBSCRIPTION_ID || config.id ||"";

async function main() {
  let cmdId = "listAll"
  let vms = cache.cGet(cmdId, 600 )
  if ( ! vms ) {
    const loginOptions = { environment: AzureEnvironment.AzureUSGovernment };
    //const creds = await msRestAzure.loginWithServicePrincipalSecret(clientId, secret, domain, loginOptions);
    let creds = await msRestAzure.loginWithUsernamePassword(username, password, loginOptions );
    const client = new ComputeManagementClient(creds, subscriptionId, AzureEnvironment.AzureUSGovernment.resourceManagerEndpointUrl);
    vms = await client.virtualMachines.listAll( );
    cache.cPut(cmdId, vms)
  }
  console.log(JSON.stringify(vms,null,2));
}
 

main().catch((err) => {

  console.log("An error occurred: %O", err);

});


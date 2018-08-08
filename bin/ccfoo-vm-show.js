const config = require('../lib/settings')
const msRestAzure = require("ms-rest-azure");
const { ComputeManagementClient } = require("azure-arm-compute");

const AzureEnvironment = msRestAzure.AzureEnvironment;
const clientId = process.env.CLIENT_ID || config.CLIENT_ID || "";
const secret = process.env.APPLICATION_SECRET || config.APPLICATION_SECRET || "";
const domain = process.env.DOMAIN || config.DOMAIN || "";
const username =  process.env.AZURE_USERNAME || config.AZURE_USERNAME || config.username || "";
const password = process.env.AZURE_PASSWORD || config.AZURE_PASSWORD || config.password || "";
const subscriptionId = process.env.AZURE_SUBSCRIPTION_ID || config.AZURE_SUBSCRIPTION_ID || config.id ||"";

async function main() {
  const loginOptions = { environment: AzureEnvironment.AzureUSGovernment };
  //const creds = await msRestAzure.loginWithServicePrincipalSecret(clientId, secret, domain, loginOptions);
  let creds = await msRestAzure.loginWithUsernamePassword(username, password, loginOptions );

  const client = new ComputeManagementClient(creds, subscriptionId, AzureEnvironment.AzureUSGovernment.resourceManagerEndpointUrl);

  const vms = await client.virtualMachines.listAll( );

  console.log(JSON.stringify(vms,null,2));

}
msRestAzure.UserTokenCredentials
 

main().catch((err) => {

  console.log("An error occurred: %O", err);

});


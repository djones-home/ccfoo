const config = require('../lib/settings')

// See Steve Strong email: this code will work, Thu 8/2/2018 12:48 PM
const msRestAzure = require("ms-rest-azure");

const { ComputeManagementClient } = require("azure-arm-compute");

const AzureEnvironment = msRestAzure.AzureEnvironment;

const clientId = process.env.CLIENT_ID || config.CLIENT_ID || "";

const secret = process.env.APPLICATION_SECRET || config.APPLICATION_SECRET || "";

const domain = process.env.DOMAIN || config.DOMAIN || "";

const subscriptionId = process.env.AZURE_SUBSCRIPTION_ID || config.AZURE_SUBSCRIPTION_ID || "";

async function main() {

  const loginOptions = { environment: AzureEnvironment.AzureUSGovernment };

  const creds = await msRestAzure.loginWithServicePrincipalSecret(clientId, secret, domain, loginOptions);

  const client = new ComputeManagementClient(creds, subscriptionId, AzureEnvironment.AzureUSGovernment.resourceManagerEndpointUrl);

  const vms = await client.virtualMachines.list();

  console.log("List of vms: %j", vms);

}

 

main().catch((err) => {

  console.log("An error occurred: %O", err);

});


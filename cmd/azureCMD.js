
const Azure = require('azure');

const util = require('util');
const path = require('path');
const async = require('async');

const azureProfile = require('./azureTokenCashe');
//const creds = require('./azureCredentials');

const azure = require('ms-rest-azure');
const ComputeManagementClient = require('azure-arm-compute');
const StorageManagementClient = require('azure-arm-storage');
const NetworkManagementClient = require('azure-arm-network');
const ResourceManagementClient = require('azure-arm-resource').ResourceManagementClient;
const SubscriptionManagementClient = require('azure-arm-resource').SubscriptionClient;

const log = console.log;
const out = process.stdout.write;



function listAllVMs() {
  const promise = new Promise((resolve, reject) => {

    azureProfile.getCredentials()
    .then(credentials => {

      const defaultSubscription = 'b156ff74-abbe-49c8-bc92-b80e8a7bad23';
      const envAzure = azure.AzureEnvironment.AzureUSGovernment;
      const client = new ComputeManagementClient(credentials, defaultSubscription, envAzure.resourceManagerEndpointUrl);
  
      return client.virtualMachines.listAll()
    })
    .then( result => {
      resolve(result);
    })


  });

  log('returning promise listAllVMs');
  return promise;
}


exports.listAllVMs = listAllVMs;
exports.command = (repl) => {

  repl.command({
    cmd: 'vms',
    help: 'List all the vm in current subscription',
    action: function (cmd, args, options) {
      listAllVMs()
      .then(result => {
        log(result);
        repl.commandComplete(null, cmd, result);
      })
      .catch( err => {
        log(err);
        repl.commandComplete(err, cmd);
      })
    }
  });
}
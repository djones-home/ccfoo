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

function incVerbose(v, total) {
  return total + 1;
}


var result = getCreds(config).catch((err)=> { console.error("ErroR: %O", err); })

result.then( foo => {
   console.log("getCreds returned:", foo)
})

module.exports = {
   incVerbose:  incVerbose
}
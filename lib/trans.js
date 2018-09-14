#!/usr/bin/env node
const cache = require('../lib/cache')
const Table = require('easy-table')
const cloud = { aws: require('../lib/aws'), azure: require('../lib/azure') }
const cfg = require('../lib/settings')
//const AzureEnvironment = msRestAzure.AzureEnvironment;
const cidata = require('../lib/cidata')
const token = require('./azureToken')
const fs = require('fs')
const rl = require('../test/data/azure/resourceList')
const t = require('../templates/arm/vm/template')
const d = require('../test/data/projectSettings')
const package = require('../package')
const log = console.error;

async function main(name = 'bastion', subject = 'vm') {
  let config = await cfg.load(cloud)
  let roleData = cidata.getVm({data: config.cidata, name, config})
  log(config, roleData)
  log(foo({ config }))
  log(JSON.stringify(mkTemplate( {subject, roleData, config}),null , 3))
}
const typeMap = { 
  as: 'Microsoft.Compute/availabilitySets',
  Disk: 'Microsoft.Compute/disks',
  Image: 'Microsoft.Compute/images',
  VMSS: 'Microsoft.Compute/virtualMachineScaleSets',
  VM: 'Microsoft.Compute/virtualMachines',
  vmext: 'Microsoft.Compute/virtualMachines/extensions',
  AppSG: 'Microsoft.Network/applicationSecurityGroups',
  NetIf: 'Microsoft.Network/networkInterfaces',
  NetSG: 'Microsoft.Network/networkSecurityGroups',
  PublicIP: 'Microsoft.Network/publicIPAddresses',
  Network: 'Microsoft.Network/virtualNetworks',
  StorageAcc: 'Microsoft.Storage/storageAccounts' 
};


// get existing Instance names, given list of resources (rl), role name, subject, rg
function getInstances( { rl, name, subject, rg } ) {
  let resType = typeMap[subject.toUpperCase()]
  let nameRE = RegExp(`^${name}-\\d*\$`)
  return rl.filter( e => { return e.type == resType && nameRE.test(e.name) && e.resourceGroup == rg })
}

// get the next available Instance name, given list of resources (rl), role name, subject, rg
function getNextName( { rl, name, subject, rg } ) {
  n = name.length + 1
  i = parseInt(getInstances( { rl, name, subject, rg } ).map(e=> e.name.slice(n)).sort().pop()) + 1
  if(  isNaN(i) )  i = 0;
 return `${name}-${i}`
}

// resourceGroups name pattern, use the CIDATA Project.Name, as a prefix, i.e project names should be uniq or this will break.
function rgName({subject, config, program}) {
  return config.cidata.Project.Name + subject
}

// This function can be called many times, to merge into a template, or just filter unwanted.
function skeletonTemplate({template = {}, config, program, subject, ...rest}={}) {
  typeof(template) == 'string'  && /.json$/.test(template) && ( template = require(template.replace(/.json$/,'')));
  typeof(template) != 'object'  &&  ( () => {throw "ERROR parsing skeleton from given template"});
  // shallow merge any template data up one level W/ given args. 
  let args = { ...template, ...rest,  ...config, ...program, subject }
  // parse args into an ARM template
  let {
     $schema = "http://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#",
     location = 'None',
     contentVersion = "1.0.0.0",
     parameters   = {},
     variables = {},
     resources = [],
     outputs = {}
  } = args;
  config && ( parameters.location =  { default: config.location, type: "string" })
 
  return { $schema, contentVersion, parameters, variables, resources, outputs }
}



function mkTemplate({ subject, roleData, config, ...args }) {
  let { VMapiVersion = '2018-04-01' } = roleData
  let isVM = subject == 'vmx'
  let isStoreAcc = true
  return {
    '$schema':
      'http://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#',
    contentVersion: '1.0.0.0',
    parameters: {},
    resources: [
      { ...( isVM && {
        isVM
      })},
      { ...( isVM && {
        name: roleData.Name,
        apiVersion: VMapiVersion,
        type: 'Microsoft.Compute/virtualMachines'
      })},
      { ...(isStoreAcc && {
        name: '[parameters(\'diagnosticsStorageAccountName\')]',
        type: 'Microsoft.Storage/storageAccounts',
        apiVersion: '2015-06-15',
        location: '[parameters(\'location\')]',
        properties:
          { accountType: '[parameters(\'diagnosticsStorageAccountType\')]' }
      })}
  ]
  }
}
function foo({ config }) {
  let { location } = config;
  return {
    ...(location && { location })
  }
} 
function networkInterfaceProperties( ) {
  ipConfigurations: [
    {
      name: 'ip-0',
      properties: {
        subnet : { id: ""}
      },
      privateIPAllocataionMethod: "Dynamic",
      ...(publicIpAddress && { publicIpAddress: { id: ""}})
    }
  ],
  networkSecurityGroup: {
    id: ""
  }
}

function sgRule() {
   return {
     name: "",
     properties: {
        priority: 100,
        protocol: 'TCP',
        access: "Allow",
        direction: "Inbound",
        sourceApplicationSecurityGroups: [],
        destinationApplicationSecurityGroups: [],
        sourceAddressPrefix: "76.102.9.94/32",
        sourcePortRange: "*",
        destinationAddressPrefix: "*",
        destinationPortRange : "22"
    }


     }

   }
}
function sgProperties() {
  "securityRules": [
  ]
}
function VMproperties( ) {
   return {
     osProfile: { 
     },
     hardwareProfile: {

     },
     StorageProfile: {

     },
     networkProfile: {

     },
     diagnosticProfile: {

     }
   }
}
function parseEpisode({
  guid,
  title,
  description,
  pubDate,
  itunesImageHref,
  enclosureUrl,
  enclosureType,
  enclosureLength,
  itunesEpisodeType,
  itunesExplicit,
  itunesDuration,
  itunesSummary
}) {
  return {
    ...(title && { title }),
    ...(guid && { guid }),
    ...(description && { description: blocksToHtml({ blocks: description }) }),
    ...(pubDate && { pubDate: new Date(pubDate).toUTCString() }),
    custom_elements: [
      enclosureUrl ? {
        enclosure: [
          {
            _attr: {
              url: enclosureUrl,
              length: enclosureLength,
              type: enclosureType
            }
          }
        ]
      } : '',
      itunesSummary ? { 'itunes:summary': itunesSummary } : '',
      itunesEpisodeType ? { 'itunes:episodeType': itunesEpisodeType } : '',
      itunesDuration ? { 'itunes:duration': itunesDuration } : '',
      { 'itunes:explicit': itunesExplicit ? 'yes' : 'no' },
      itunesImageHref ? {
        'itunes:image': [
          {
            _attr: {
              href: itunesImageHref
            }
          }
        ]
      } : ''
    ].filter(notFalse => notFalse)
  }
}

if ( require.main === module )  main().catch(e => console.error(e));

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

async function main() {
  let config = await cfg.load(cloud)
  let roleData = cidata.getVm({data: config.cidata, name: "bastion"})
  log(config)
  log(foo({ config }))
  log(JSON.stringify(mkTemplate( {subject: 'vm', roleData, config}),null , 3))
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


const fs = require('fs')
const log = console.log
const profiles = require('../lib/profiles')
const currentSchema = '20180812'
let dataFile = process.env.CIDATA || '../test/data/projectSettings.json'

async function load(config) {
  if ( process.env.CIDATA ) {
     data = JSON.parse(fs.readFileSync(dataFile))
  } else {
      data = require('../test/data/projectSettings')
  }
  return normalize({config, data})
}
// validate, may not be needed, this is not doing anything now, that normalize does not.
function validate({config, data, ...opt}) {
   return data.Schema && (data.Schema == currentSchema) || (data.Schema == '20170226')
}

//  console.log("YTBD") deal with camelCase, Schema version translations
function normalize({data, config, ...opt}) {
   validate({config, data})
   switch(data.Schema) {
     case  currentSchema :
       return data
     case '20170226':
       return (normalize( {data: translate20170226(data)} ))
     default :
        throw new Error("Unknown Schema.")
   }
}

function getVm({data, name, ...opt}) {
  return profiles.getRole({ subject: 'Vm', data: normalize({data}), name })
} 

function listVm({data, ...opt}) {
 return Object.keys(normalize({data}).Vm.Roles)
}

function translate20170226({data}) {
  throw new Error(`Sorry translation YTBD`)
//  data.Schema = 20180812
//  return {
//    {InstanceRoles Vm.Roles}
//  }
}
module.exports = {
   validate: validate,
   normalize: normalize,
   listVm: listVm,
   getVm: getVm,
   load
}

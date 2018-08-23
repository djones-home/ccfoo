const fs = require('fs')
const log = console.log
const profiles = require('../lib/profiles')
const currentSchema = '20180812'

function validate({config, data, ...opt}) {
   //log("config:", config)
   //log("data:", data) 
   return data.Schema && (data.Schema == currentSchema) || (data.Schema == '20170226')
}

//  console.log("YTBD") deal with camelCase, Schema version translations
function normalize({data, ...opt}) {
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
   getVm: getVm
}

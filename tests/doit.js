var a = require('../lib/azure')
const cfg = require('../lib/settings')
const config = cfg.load()
var program = {}
async function main() {
 // a.listVMs({program,config})
  a.listResources({program,config})
}

main().catch(e => console.log(e))
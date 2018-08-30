async function ytbd({program,subject,config,...rest}) { console.log("YTBD")}
async function launch({program,subject,config,...rest}) { console.log("YTBD")}
async function stop({program,subject,config,...rest}) { console.log("YTBD")}
async function start({program,subject,config,...rest}) { console.log("YTBD")}
async function terminate({program,subject,config,...rest}) { console.log("YTBD")}
async function listVMs({program,subject,config,...rest}) { console.log("YTBD")}
async function listResources({program,subject,config,...rest}) { console.log("YTBD")}
async function output({program,subject,config,data,...rest}) { console.log(data)}
async function validateConfig(config) { return config}

module.exports = {
  listResources, listVMs,
  show: ytbd,
  launch: launch,
  stop: stop,
  start: start, output,
  terminate: terminate,
  validate: validateConfig
}
async function show({program,subject,config,...rest}) { console.log("YTBD")}
async function launch({program,subject,config,...rest}) { console.log("YTBD")}
async function stop({program,subject,config,...rest}) { console.log("YTBD")}
async function start({program,subject,config,...rest}) { console.log("YTBD")}
async function terminate({program,subject,config,...rest}) { console.log("YTBD")}
async function listVMs({program,subject,config,...rest}) { console.log("YTBD")}
async function listResources({program,subject,config,...rest}) { console.log("YTBD")}

module.exports = {
  listResources, listVMs,
  show: show,
  launch: launch,
  stop: stop,
  start: start,
  terminate: terminate
}
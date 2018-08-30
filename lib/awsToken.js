const child_process = require('child_process')

// Leverage the exising bash function for aws
// Eventually upgrade them as time allows.
function action({program, config, cmd, lifetime = '8h'}) {
  child_process.execSync(`${__basedir}/token.sh ${cmd} ${lifetime}`,{stdio: 'inherit', env: process.env },(err) => {
       err &&  process.exit(1) || process.exit(0)
  })
}

module.exports = {
  action
}
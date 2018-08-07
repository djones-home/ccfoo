const fs = require('fs')

// getRole( "vm", "bastion")
function getRole( subject, name, d = null) {
  if (! d)  d = JSON.parse(fs.readFileSync(process.env.CIDATA))
  let profiles = d.Profiles
  let roles =  d[`${subject}Roles`] || d.InstanceRoles
  if (typeof(roles) == 'undefined' || (! roles[name]) ) 
    throw new Error(`No ${subject}Roles found in settings by name of: ${name}`);
  
  let profileNames = getEffectiveProfiles( roles[name], profiles )
  if(profiles.default) profileNames.push('default')
  let rv = profileNames.reduce( (acc, cv)=>{ return Object.assign(profiles[cv], acc)}, roles[name])
  //return Object.assign( d, rv)
  return rv
}

function getEffectiveProfiles(role,profiles,acc=[]) {
  let l= [] 
  getNewProfiles(role, acc).forEach( n => {
    acc.push(n)
    if ( ! profiles[n] ) throw new Error(`No such profile: ${n}`)
    l = getEffectiveProfiles(profiles[n],profiles,acc)
    acc = acc.concat(l)
  })
  return acc
}

// return a list of new profile names (not in accumulatedProfiles)
function getNewProfiles( obj, acc=[]) {
  let pl = (obj.Profiles ||  obj.Profile)
  if (typeof(pl) == 'string') pl = pl.replace(/,/g," ").trim().split(/\s+/)
  if (typeof(pl) == 'undefined' ) return []
  // reject/filter-out the accumulated from or return value
  return pl.filter(x => (! acc.includes(x) ))
}
//console.log(getRole( "vm", "bastion"))
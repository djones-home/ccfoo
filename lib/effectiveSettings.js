const fs = require('fs')
// 
// getRole( "vm", "bastion")
// => {}
function getRole( subject, name, d = "CIDATA") {
  if ( typeof d == 'string' ) {
    try { 
      if ( process.env[d] ) {
        d = JSON.parse(fs.readFileSync(process.env[d]))
      } else {
        d = JSON.parse( d)
      } 
    } catch(e) {
      console.error(`Not a valid data source JSON string, or No and ENV.${d.slice(0,20)}\n`)
      throw e
    }
  }
  let profiles = d.Profiles
  let roles =  d[`${subject}Roles`] || d.InstanceRoles
  if (typeof(roles) == 'undefined' || (! roles[name]) ) 
    throw new Error(`No ${subject}Roles found in settings by name of: ${name}`);
  
  let profileNames = getEffectiveProfiles( roles[name], profiles )
  if(profiles.default) profileNames.push('default')
  let rv = profileNames.reduce( (acc, cv)=>{ return Object.assign(profiles[cv], acc)}, roles[name])
  delete rv.Profile
  rv.Profiles = profileNames
  //return Object.assign( d, rv)
  return  rv
}

// Return a list of profile names which effect given role-object
// Resolve nested profiles into the return list, in the order of presetence,
// If given Accumulator (acc), it is appended to, to make the return list.
function getEffectiveProfiles(role,profiles,acc=[]) {
  getProfileNames(role, acc).forEach( n => {
    if (! acc.includes(n) ) acc.push(n)
    if ( ! profiles[n] ) throw new Error(`No such profile: ${n}`)
    getEffectiveProfiles(profiles[n],profiles,acc).forEach( pn => {
       if (!acc.includes(pn)) acc.push(pn)
    })
  })
  return acc
}

// return a list of  profile names (not in accumulator), from given obj.Profiles (or obj.Profile )
function getProfileNames( obj, acc=[]) {
  let pl = (obj.Profiles ||  obj.Profile)
  if (typeof(pl) == 'string') pl = pl.replace(/,/g," ").trim().split(/\s+/)
  if (typeof(pl) == 'undefined' ) return []
  // reject/filter-out the accumulated from or return value
  return pl.filter(x => (! acc.includes(x) ))
}
//console.log(JSON.stringify(getRole( "vm", "bastion"),null,2))
var path = require('path')
function showMeRoles() {
  el =[]
  fs.readdirSync(`${process.env.WORKSPACE}/ciData`).filter(fn=> /.*\.json$/.test(fn)).forEach( n => {
    let j = JSON.parse(fs.readFileSync(path.join(process.env.WORKSPACE, 'ciData', n)))
    if (j.Project && j.Profiles && ( j.vm || j.InstanceRoles)) {
      Object.keys(j.InstanceRoles).forEach( rn => { 
        try { console.log(JSON.stringify(getRole('vm', rn, j),null, 2)) }
        catch(e) { el.push({ e:e, n: n, p: j.Project }) }
      })
      el.forEach( e => console.error( 'Error in file:%s, Project %s\n', e.n, e.p, e.e ) )

    }
  })
}
module.exports = {
  getEffectiveProfiles: getEffectiveProfiles,
  getProfileNames: getProfileNames,
  getRole: getRole,
  showMeRoles: showMeRoles
}

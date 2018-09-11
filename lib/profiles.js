const fs = require('fs');
//
// getRole( {subject: "vm", name: "bastion", data: fs.readFileSync(process.env.CIDATA, config: {provider:'foo'}})})
// => {}
function getRole({ subject, name, data: d, config = {provider: 'None'}, ...opt }) {
  let profiles = d.Profiles;
  let roles = d[subject].Roles || d.InstanceRoles;
  if (typeof roles == 'undefined' || !roles[name])
    throw new Error(
      `No ${subject}.Roles found in settings by name of: ${name}`
    );

  let profileNames = getEffectiveProfiles(roles[name], profiles);
  if (profiles.default) profileNames.push('default');
  let rv = profileNames.reduce((acc, cv) => {
    return Object.assign(scopeData({obj: profiles[cv], config}), acc);
  }, scopeData({obj: roles[name], config}));
  rv.ResolvedProfiles = profileNames;
  //return Object.assign( d, rv)
  return rv;
}

// Return a list of profile names which effect given role-object
// Resolve nested profiles into the return list, in the order of presetence,
// If given Accumulator (acc), it is appended to, to make the return list.
function getEffectiveProfiles(role, profiles, acc = []) {
  getProfileNames(role, acc).forEach(n => {
    if (!acc.includes(n)) acc.push(n);
    if (!profiles[n]) throw new Error(`No such profile: ${n}`);
    getEffectiveProfiles(profiles[n], profiles, acc).forEach(pn => {
      if (!acc.includes(pn)) acc.push(pn);
    });
  });
  return acc;
}

// return a list of  profile names (not in accumulator), from given obj.Profiles (or obj.Profile )
function getProfileNames(obj, acc = []) {
  let pl = obj.Profiles || obj.Profile;
  if (typeof pl == 'string')
    pl = pl
      .replace(/,/g, ' ')
      .trim()
      .split(/\s+/);
  if (typeof pl == 'undefined') return [];
  // reject/filter-out the accumulated from or return value
  return pl.filter(x => !acc.includes(x));
}
var path = require('path');
function showJsonFileRoles(file, subject = 'subject', config) {
  showRoles({ data: JSON.parse(fs.readFileSync(file)), subject, config });
}

function showRoles({ data, subject, config }) {
  Object.keys(data[subject].Roles).forEach(name => {
    console.log(JSON.stringify(getRole({ subject, name, data, config }), null, 2));
  });
}
// Flatten (or shallow merge up) obj data that is scoped by a provider or location
//> scopeData({ obj: { a: 1, provider: { aws: { a: 2, }}}, config: { provider: 'x' , location: 'A' } });
// expect { a: 1 }
//> scopeData({ obj: { a: 1, provider: { aws: { a: 2, }}}, config: { provider: 'aws' , location: 'A' } });
// expect { a: 2 }
//> scopeData({ 
//    obj: { a: 1, provider: { aws: { a: 2, location: { A: { a: 3 }}} }}, 
//    config: { provider: 'aws' , location: 'A' } 
//  });
// expect { a: 3 }
function scopeData({obj, config}) {
  let { provider = {}, ...data }  = obj
  data = { ...data, ...provider[config.provider]}
  let { location = {}, ...rd }  = data
  rd = { ...rd, ...location[config.location] }
  return rd
}
module.exports = {
  getEffectiveProfiles: getEffectiveProfiles,
  getProfileNames: getProfileNames,
  getRole: getRole,
  showRoles: showRoles,
  showJsonFileRoles: showJsonFileRoles,
  scopeData
};

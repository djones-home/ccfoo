const fs = require('fs');
//
// getRole( {subject: "vm", name: "bastion", data: fs.readFileSync(process.env.CIDATA)})
// => {}
function getRole({ subject, name, data: d, ...opt }) {
  let profiles = d.Profiles;
  let roles = d[subject].Roles || d.InstanceRoles;
  if (typeof roles == 'undefined' || !roles[name])
    throw new Error(
      `No ${subject}.Roles found in settings by name of: ${name}`
    );

  let profileNames = getEffectiveProfiles(roles[name], profiles);
  if (profiles.default) profileNames.push('default');
  let rv = profileNames.reduce((acc, cv) => {
    return Object.assign(profiles[cv], acc);
  }, roles[name]);
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
//console.log(JSON.stringify(getRole( "vm", "bastion"),null,2))
var path = require('path');
function showJsonFileRoles(file, subject = 'subject') {
  showRoles({ data: JSON.parse(fs.readFileSync(file)), subject });
}

function showRoles({ data, subject }) {
  Object.keys(data[subject].Roles).forEach(name => {
    console.log(JSON.stringify(getRole({ subject, name, data }), null, 2));
  });
}

module.exports = {
  getEffectiveProfiles: getEffectiveProfiles,
  getProfileNames: getProfileNames,
  getRole: getRole,
  showRoles: showRoles,
  showJsonFileRoles: showJsonFileRoles
};

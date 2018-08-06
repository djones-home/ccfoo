const effectiveSettings = function ( what, who, where, config) {
    let rv, profileList
    rv = config[what] || return {}
    rv = config[what][who] || return {}
    profileList = [ rv.Profile ] || rv.Profiles
profileList =  ( rv.Profiles || [rv.Profile] )


}

function effSettingsTest(name) {
  const fs = require('fs')
  var  config = JSON.parse(fs.readFileSync(process.env.CIDATA))
  var what = "InstanceRoles"
  var who = name
  return effectiveSettings(what, who, null, data)
}
//  Nested Objects
Object.keys(data.InstanceRoles).forEach( n => { 
    console.log( data.InstanceRoles[n])
    var pl = ( data.InstanceRoles[n].Profiles || [data.InstanceRoles[n].Profile])
    console.log(`name ${n}, pl ${ps}`) 

})

// combine a list of select proiles to one effective profile
function effectiveProfile(pl,ob,cirular =[] ){
    pl.reject(circular).Map(n => { })
}
function getNestedProfiles(n,ob, circular = []) {
    pl = ob.Profiles[n] || return circular
    circular.push(n)

    pl.reject(circular).forEach( x => {
         circular = getNextedProfiles(x,ob,circular)
    })
    return circular
    
}
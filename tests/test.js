// Require the built in 'assertion' library
var assert = require('assert');
var data = require('../tests/projectSettings')
var es = require('../lib/effectiveSettings')
process.env.CIDATA='/home/djones/ws/ciData/ciStack.json'
es.getRole('vm','bastion')
showMeRoles()

// Create a test suite (group) called Math
describe('Profile Settings', function() {
    // Test getRole: 
    it('should return a list', function(){
      // Our actual test: 3*3 SHOULD EQUAL 9
      assert.equal(es.getRole("vm",data), 3*3);
    });
    // Test Two: A string explanation of what we're testing
    it('should return Profiles list', function(){
      // Our actual test: (3-4)*8 SHOULD EQUAL -8
      assert.equal(-8, (3-4)*8);
    });
});

function showMeRoles() {
  fs.readdirSync(`${process.env.WORKSPACE}/ciData`).filter(fn=> /.*\.json$/.test(fn)).forEach( n => {
    let j = JSON.parse(fs.readFileSync(n))
    if (j.Project && j.Profiles && j.InstanceRoles) {
      console.log('file:%s, Project %s\n', n, j.Project)

      Object.keys(j.InstanceRoles).forEach( rn => { 
        console.log(JSON.stringify(es.getRole('vm', rn, j),null, 2))})

    }
  })
}
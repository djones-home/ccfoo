// Require the built in 'assertion' library
var assert = require('assert');
var prof = require('../lib/profiles')
var data = require('../test/profiles')

// Create a test suite (group) called Math
describe('Roles x,y,z Profile Settings', function() {
    // Test getRole x: 
    it('x should return Profiles: default', function(){
      assert.equal(prof.getRole('subject','x',data).ResolvedProfiles.join(), 'default');
      });
    // Test role y
    it('y should return Profiles: b,c,d,default', function(){
        assert.equal(prof.getRole('subject','y',data).ResolvedProfiles.join(), 'b,c,d,default');        assert.equal(prof.getRole('subject','y',data).ResolvedProfiles.join(), 'b,c,d,default');
    });
        // Test role z
    it('z should return Profiles: c,b,default', function(){
        assert.equal(prof.getRole('subject','z',data).ResolvedProfiles.join(), 'c,b,default');

    });

});


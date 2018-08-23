const assert = require("assert");

const log = console.log;
const out = process.stdout.write;

var settings = require('../lib/settings')
var profile = settings.load();

var program = require('commander');


describe('test you can run config commands.. ', () => {
    //define the commands with the module

  describe('you can get current profile', () =>  {

    program.debug = false;

    it('call to config Show...', () => {
      const result =  settings.action(program, profile, "show");
      assert(result);
    });

    it('call to config Set...', () => {
      const result =  settings.action(program, profile, "set", "Age", 25);
      assert(result);
    });

    it('call to config Get...', () => {
      const result =  settings.action(program, profile, "get", "Age");
      assert(result == 25);
    });

    it('call to config Delete...', () => {
      const result =  settings.action(program, profile, "delete", "Age");
      assert(result['Age'] == null);
    });

    it('call to config garbage...', () => {
      const result =  settings.action(program, profile);
      assert(result == null);
    });

  });
});
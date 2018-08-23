const assert = require("assert");

const log = console.log;
const out = process.stdout.write;

var cfg = require('../lib/settings')
var config = cfg.load();

var program = require('commander');


describe('test you can run config commands.. ', () => {
    //define the commands with the module

  describe('you can get current profile', () =>  {

    program.debug = false;

    it('call to config Show...', () => {
      const result =  cfg.action(program, config, "show");
      assert(result);
    });

    it('call to config Set...', () => {
      const result =  cfg.action(program, config, "set", "Age", 25);
      assert(result);
    });

    it('call to config Get...', () => {
      const result =  cfg.action(program, config, "get", "Age");
      assert(result == 25);
    });

    it('call to config Delete...', () => {
      const result =  cfg.action(program, config, "delete", "Age");
      assert(result['Age'] == null);
    });

    it('call to config garbage...', () => {
      const result =  cfg.action(program, config);
      assert(result == null);
    });

  });
});
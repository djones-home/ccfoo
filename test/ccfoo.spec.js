const assert = require("assert");

const log = console.log;
const out = process.stdout.write;

var cfg = require('../lib/settings')
var config = cfg.load();

var program = require('commander') 
 .version(package.version)


describe('test you can run config commands.. ', () => {
    //define the commands with the module

  describe('you can get current profile', () =>  {

    program.debug = true;
    it('call to config Show...', () => {
      const result =  cfg.action(program, config, "show");
      assert(result);
    });

  });
});
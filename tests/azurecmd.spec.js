const assert = require("assert");

const log = console.log;
const out = process.stdout.write;

const azureCMD = require("../cmd/azureCMD");


describe('test to call azure commands.. ', () => {
    //define the commands with the module

  describe('call for VM list', () =>  {

    it('get a list of vms...', () => {
      //this assume you can login
      azureCMD.listAllVMs()
      .then(result => {
        log(result);
        assert(result);
      })
      .catch(err => {
        log(err);
      })
    });

  });
});
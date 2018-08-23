const assert = require("assert");

const log = console.log;

const settings = require('./settings')
const tokenCashe = require("../lib/azureToken");


describe('Test commands of azureToken.. ', () => {
    //define the commands with the module

  describe('the azure token cashe', () =>  {


    it('should get azure creds for current profile...', () => {
      const profile = settings.load();

      tokenCashe.getCredentials(profile)
      .then(credentials => {
        assert(credentials);
      })
      .catch(err => {
        log(err)
      })
    });

  });
});
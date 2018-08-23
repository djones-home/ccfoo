const assert = require("assert");

const log = console.log;
const out = process.stdout.write;

const tokenCashe = require("../cmd/azureTokenCashe");


describe('Test commands of azureTokenCash.. ', () => {
    //define the commands with the module

  describe('the azure token cashe', () =>  {

    // it('should report if profile is empty...', () => {
    //   tokenCashe.clearProfile().then(_ =>
    //   {
    //     return tokenCashe.getProfile();
    //   })
    //   .then(profile => {
    //     assert(profile);
    //   })
    //   .catch(err => {
    //     //log(err)
    //     assert(err.success = false);
    //   })
    // });

    // it('should report the current profile...', () => {
    //   tokenCashe.clearProfile().then(_ =>
    //   {
    //     return tokenCashe.setProfile('steve');
    //   })
    //   .then(profile => {
    //     assert(profile === 'steve');
    //   })
    //   .catch(err => {
    //     //log(err)
    //     assert(err.success = false);
    //   })
    // });

    it('should get azure creds for profile steve...', () => {
      tokenCashe.setProfile('steve', true).then(_ =>
      {
        return tokenCashe.getCredentials();
      })
      .then(credentials => {
        assert(credentials);
      })
      .catch(err => {
        log(err)
      })
    });

  });
});
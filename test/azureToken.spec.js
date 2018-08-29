#!/usr/bin/env node
const assert = require("assert");

const log = console.log;

const cfg = require('../lib/settings')
const azureToken = require("../lib/azureToken");


describe('Test commands of azureToken.. ', () => {
    //define the commands with the module

  describe('the azure token cashe', () =>  {


    it('should get azure creds for current profile...', () => {
      const config = await cfg.load();

      azureToken.getCredentials(config)
      .then(credentials => {
        assert(credentials);
      })
      .catch(err => {
        log(err)
      })
    });

  });
});
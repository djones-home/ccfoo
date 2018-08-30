#!/usr/bin/env node
const assert = require("assert");

const log = console.log;

const cfg = require('../lib/settings')
const azure = require("../lib/azure");


describe('Test commands of azure login.. ', () => {
    //define the commands with the module

  describe('the azure login token cashe', () =>  {


    it('should get azure creds for current profile...', () => {
      cfg.load().then(config => {
        azure.getCreds(config)
        .then(credentials => {
          assert(credentials);
        })
        .catch(err => {
          log(err)
        })

      })

    });

  });
});
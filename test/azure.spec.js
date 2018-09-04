#!/usr/bin/env node
const assert = require("assert");

const log = console.log;

const cfg = require('../lib/settings')
const azure = require("../lib/azure");
const cloud = { azure: azure }


describe('Test commands of azure login.. ', () => {
  //define the commands with the module

  describe('the azure login token cashe', () => {


    it('should get azure creds for current profile...', () => {
      cfg.load(cloud).then(config => {
        azure.getCreds({ config })
          .then(credentials => {
            assert(credentials);
          })
          .catch(err => {
            log(err)
          })

      })

    });

    // it('should get create a resource group...', () => {
    //   let client;


    //   cfg.load(cloud).then(config => {
    //     assert(config);
    //     azure.getCreds({ config })
    //       .then(credentials => {
    //         assert(credentials);
    //         return azure.establishResourceGroup(credentials, config, "vm")
    //       }).then(result => {
    //         assert(result.group);
    //       })
    //       .catch(err => {
    //         log(err)
    //       })

    //   })

    // });




    it('should deploy a template VM to  resource group...', () => {

      cfg.load(cloud).then(config => {
        assert(config);
        azure.getCreds({ config })
          .then(credentials => {
            assert(credentials);
            return azure.establishResourceGroup(credentials, config, "vm")
          }).then(result => {
            let { client, group } = result;
            let template = require('../templates/arm/vm/template');
            let parameters = {}
            return azure.deployTemplate({ client, group, parameters, template });
          })
          .then(result => {
            assert(result);
          })
          .catch(err => {
            log(err)
          })

      })

    });

  });


});
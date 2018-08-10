var fs = require('fs');
var path = require('path');
var msRestAzure = require('ms-rest-azure');
var resourceManagement = require("azure-arm-resource");
var Converter = require("csvtojson").Converter;
var converter = new Converter({});
var config = require('./config/config');
var _ = require('lodash');

console.log(`Starting deployment`);

// Login to Azure 
login()
    .then(function (client) {

        // Execute in parallel all deployent preparation tasks
        Promise
            .resolve(client)
            .then(createRG)
            .then(deploySharedTemplate)
            .then(getParameters)
            .then(function (parameters) {
                return ([client, parameters]);
            })
            .then(deployTemplate)
            .then(function (values) {

                console.log(`Deployed ARM Template to Azure`);

            });

    });

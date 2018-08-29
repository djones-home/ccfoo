const { getNetwork } = require('../azure');
const Table = require('easy-table');

async function networkShow({ program, subject, config, ...rest }) {
  console.log(__filename, ' WIP', await getNetwork({ program, config }));
}

async function ytbd({ program, subject, config, ...rest }) {
  console.log(__filename, ' YTBD');
}

module.exports = {
  networkCreate: ytbd,
  networkDelete: ytbd,
  networkShow: networkShow
};

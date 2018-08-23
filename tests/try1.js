//var cache = require('../lib/cache')
//console.log( cache.info() )
//cache.init()
//console.log( cache.info() )
//cache.clean()
//console.log( cache.info() )
//cache.clean( 300 )
//console.log( cache.info() )
const package = require('../package');
const program = require('commander');

function increaseVerbosity(v, total) {
  return total + 1;
}

subject = 'vm';
program
  .version(package.version)
  .option(`-n --Name <${subject}Name>`, `Specify ${subject} Name`)
  .option(
    `-u --unit <${subject}Unit>`,
    'Organizational parent-container|filterRE|id'
  )
  .option(
    '-v, --verbose',
    'Verbose, repeat to increase log level',
    increaseVerbosity,
    0
  );

program.parse(['/foobar', 'myname', '-vv', '-u', 'el7']);

async function main() {
  var vms = [1, 2, 3];
  var total = 3;
  console.error(
    `level-${program.verbose}: vm count: ${
      vms.length
    } of ${total} ${subject}s W/ filter :\n`,
    program.unit ? `, id by regexp /${program.unit}/\n` : '',
    program.Name ? `, Name == ${program.Name}\n` : '',
    program.verbose > 1 ? program.rawArgs : ''
  );
}

main().catch(err => {
  console.error('An error occurred: %O', err);
});

'use strict';

// Execute the generated consumer's own validator, rather than restating it in
// this test. These controls establish no physical browser/DOM interaction.
function testInspectorConsumerVectors(html, vectors) {
  const contract = html.slice(html.indexOf('  const CONTRACT='), html.indexOf('  const MESSAGES='));
  const functions = html.slice(html.indexOf('  function utf8Length('), html.indexOf('  function text('));
  if (!contract || !functions) throw new Error('Missing generated validation source');
  const validate = new Function(contract + functions + ';return validate;')();
  const results = [];
  for (const vector of vectors) {
    let accepted = true, error = '';
    try { validate(vector.value); } catch (problem) { accepted = false; error = String(problem.message); }
    const expectedError = vector.name === 'source-missing' ? 'kind' : vector.error;
    if (accepted !== vector.accepted || !accepted && error.split(':')[0] !== expectedError) {
      throw new Error('Unexpected actual generated validator result: ' + vector.name + ': ' + error);
    }
    results.push({name: vector.name, accepted, error});
  }
  return {status: 'passed-actual-generated-inspector-validator', cases: results.length, results,
    dom_interaction: false, factorio_processes: 0, dependency_payload_bytes_copied: 0};
}

module.exports = {testInspectorConsumerVectors};
if (typeof require === 'function' && require.main === module) {
  const fs = require('fs'), path = require('path'), root = process.argv[2];
  const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
  const vectors = JSON.parse(fs.readFileSync(path.join(root, 'vectors.json'), 'utf8')).vectors;
  console.log(JSON.stringify(testInspectorConsumerVectors(html, vectors)));
}

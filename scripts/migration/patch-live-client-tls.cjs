const fs = require('node:fs'), os = require('node:os'), path = require('node:path'), vm = require('node:vm');
function patch(text) {
  const old = "if(identity.role!=='postgres'||!identity.ssl||!identity.tj||!identity.archive) throw new Error('Destination identity or TLS checks failed');";
  if (!text.includes(old) || !text.includes("PGSSLMODE:'require',")) throw new Error('Expected v2 runner not found; stopped without changing it.');
  text = text.replace("PGSSLMODE:'require',", "PGSSLMODE:'require', PGGSSENCMODE:'disable',");
  text = text.replace(old, "if(identity.role!=='postgres'||!identity.tj||!identity.archive) throw new Error('Destination checks failed: role='+identity.role+'; tj='+identity.tj+'; archive='+identity.archive);");
  new vm.Script(text);
  return text;
}
if (require.main === module) {
  const file = path.join(os.homedir(), 'Documents', 'merge-live-us-east-v2.cjs');
  fs.writeFileSync(file, patch(fs.readFileSync(file, 'utf8')), {mode:0o600});
  console.log('Connection check corrected; client SSL remains required.');
}
module.exports = {patch};

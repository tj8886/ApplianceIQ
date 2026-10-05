import {readFileSync,mkdirSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
const root=resolve(import.meta.dirname,'../..');
const {functions:names}=JSON.parse(readFileSync(resolve(root,'docs/migration/us-runtime-api-map.json'),'utf8'));
const suites=['test-platform-runtime.sql','test-business-dashboard-runtime.sql','test-coaching-dashboard-runtime.sql','test-coaching-academy-batch.sql','test-command-centre-batch.sql','test-crm-contact-workflows.sql','test-floor-analytics.sql','test-management-batch.sql'];
const out=process.argv[2];
if(!out)throw new Error('Usage: node build-bulk-api-tests.mjs OUTPUT_DIRECTORY');
mkdirSync(out,{recursive:true});
for(const suite of suites){let sql=readFileSync(resolve(root,'scripts/migration',suite),'utf8');for(const name of names)sql=sql.replace(new RegExp('\\btj\\.'+name+'\\(', 'g'),'public.tj_runtime_'+name+'(');writeFileSync(resolve(out,suite),sql);}
console.log(`Prepared ${suites.length} rollback suites for ${names.length} reviewed API aliases`);

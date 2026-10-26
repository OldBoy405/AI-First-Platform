const fs=require('fs'),cp=require('child_process'),crypto=require('crypto'),path=require('path');
const [label,previous]=process.argv.slice(2);
const container='stdd-aifi45-20261022-pg';
const i=JSON.parse(cp.execFileSync('docker',['inspect',container],{encoding:'utf8'}))[0];
const e=Object.fromEntries(i.Config.Env.map(s=>[s.slice(0,s.indexOf('=')),s.slice(s.indexOf('=')+1)])),p=i.HostConfig.PortBindings['5432/tcp'][0];
if(!i.Id.startsWith('666bfec52ac3')||i.Config.Labels['stdd.change']!=='2026-10-22-aifi-45-authorized-execution'||!i.State.Running||p.HostIp!=='127.0.0.1'||p.HostPort!=='55432'||e.POSTGRES_DB!=='stdd_aifi45_20261022'||e.POSTGRES_USER!=='stdd')throw Error('wrong DB');
const sql=`BEGIN READ ONLY; SELECT json_build_object('history',COALESCE((SELECT json_agg(row_to_json(a) ORDER BY id) FROM approval_record a),'[]'::json),'locks',(SELECT count(*) FROM pg_locks WHERE locktype='advisory'),'sessions',(SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND pid<>pg_backend_pid() AND backend_type='client backend'),'migrations',(SELECT count(*) FROM schema_migrations),'latest',(SELECT max(version) FROM schema_migrations),'identity',current_database()||'/'||current_user); COMMIT;`;
const r=cp.spawnSync('docker',['exec','-i',container,'psql','-X','-q','-A','-t','-v','ON_ERROR_STOP=1','-U','stdd','-d','stdd_aifi45_20261022'],{input:sql,encoding:'utf8'});if(r.status!==0)throw Error(r.stderr);
const s=JSON.parse(r.stdout.trim());const rows=s.history.map(a=>({id:a.id,workspace_id:a.workspace_id,cr_id:a.cr_id,sha256:crypto.createHash('sha256').update(JSON.stringify(a)).digest('hex')}));
const proof={schema:'aifi45-revoke-db/v1',at:new Date().toISOString(),container_id:i.Id,identity:s.identity,rows,history_count:rows.length,locks:s.locks,sessions:s.sessions,migrations:s.migrations,latest:s.latest};
if(previous){const b=JSON.parse(fs.readFileSync(previous,'utf8'));proof.compared_to=path.basename(previous);proof.identical=JSON.stringify(b.rows)===JSON.stringify(rows);}
const out='C:/Users/GOBAO/Downloads/AI/AI First Platform/projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/revoke-'+label+'-'+Date.now()+'.json';fs.writeFileSync(out,JSON.stringify(proof,null,2)+'\n',{flag:'wx'});console.log(JSON.stringify({...proof,rows:undefined,file:out}));if(proof.identical===false)process.exitCode=1;

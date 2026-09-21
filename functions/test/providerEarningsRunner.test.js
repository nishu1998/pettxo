const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {spawnSync}=require('node:child_process');
function fixture(fn) {
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'earnings-runner-'));
  const preload=path.join(dir,'fetch.cjs');
  fs.writeFileSync(preload,`const fs=require('node:fs');
    global.fetch=async(url,args)=>{
      fs.appendFileSync(process.env.RUNNER_REQUESTS,args.body+'\\n');
      const pages=JSON.parse(fs.readFileSync(process.env.RUNNER_RESPONSES,'utf8'));
      const page=pages.shift(); fs.writeFileSync(process.env.RUNNER_RESPONSES,JSON.stringify(pages));
      return {ok:page.status===200,status:page.status,json:async()=>({result:page.result})};
    };`);
  const token=path.join(dir,'token');fs.writeFileSync(token,'SECRET');
  const cp=path.join(dir,'checkpoint.json'),report=path.join(dir,'report.jsonl');
  const requests=path.join(dir,'requests'),responses=path.join(dir,'responses');
  const result=(more=false, retries=[])=>({migrationVersion:2,counts:{scanned:1},summary:{wouldUpdate:1},
    breakdown:{issues:{'MISSING:earningsStatus':1}},hasMore:more,nextCursor:more?'a':null,retryIds:retries});
  const run=(args=[],pages=[{status:200,result:result()}])=>{
    fs.writeFileSync(responses,JSON.stringify(pages));
    return spawnSync(process.execPath,['-r',preload,path.resolve(__dirname,'../scripts/provider_earnings_reconcile.cjs'),
      '--url','https://example.invalid','--firebase-token-file',token,'--iam-token-file',token,
      '--checkpoint',cp,'--report',report,...args],{encoding:'utf8',env:{...process.env,RUNNER_REQUESTS:requests,RUNNER_RESPONSES:responses}});
  };
  try {fn({run,result,cp,report,requests});} finally {fs.rmSync(dir,{recursive:true,force:true});}
}
test('runner dry-run pages and aggregate checkpoint, no raw credentials logged',()=>fixture(({run,result,cp,requests})=>{
  const r=run(['--all'],[{status:200,result:result(true)},{status:200,result:result()}]);
  assert.equal(r.status,0,r.stderr); assert.ok(!r.stdout.includes('SECRET'));
  const calls=fs.readFileSync(requests,'utf8').trim().split('\n').map(JSON.parse);
  assert.equal(calls.length,2); assert.equal(calls[0].data.dryRun,true); assert.equal(calls[1].data.cursor,'a');
  assert.equal(JSON.parse(fs.readFileSync(cp)).totals.counts.scanned,2);
}));
test('runner refuses unattended writes before making a request',()=>fixture(({run,requests})=>{
  assert.equal(run(['--apply','--all']).status,1); assert.equal(fs.existsSync(requests),false);
}));
test('targeted apply interrupted before response resumes exact IDs, never global scan',()=>fixture(({run,cp,requests})=>{
  assert.equal(run(['--apply','--ids','reviewed-1'],[{status:503}]).status,1);
  assert.ok(fs.existsSync(cp));
  assert.equal(run(['--apply','--resume']).status,0);
  const calls=fs.readFileSync(requests,'utf8').trim().split('\n').map(JSON.parse);
  assert.deepEqual(calls.map(c=>c.data.ids),[['reviewed-1'],['reviewed-1']]);
}));
test('runner retries failed IDs before continuing a scan cursor',()=>fixture(({run,result,requests})=>{
  assert.equal(run([],[{status:200,result:result(true,['failed-id'])}]).status,1);
  assert.equal(run(['--resume','--all'],[{status:200,result:result()},{status:200,result:result()}]).status,0);
  const calls=fs.readFileSync(requests,'utf8').trim().split('\n').map(JSON.parse);
  assert.deepEqual(calls[1].data.ids,['failed-id']); assert.equal(calls[2].data.cursor,'a');
}));

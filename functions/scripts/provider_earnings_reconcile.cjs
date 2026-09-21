#!/usr/bin/env node
'use strict';
// Operator-driven client for the existing private callable. No Admin SDK bypass.
const fs = require('node:fs');
const {parseArgs} = require('node:util');
async function main() {
  const {values: v} = parseArgs({options: {
    url: {type:'string'}, 'firebase-token-file': {type:'string'}, 'iam-token-file': {type:'string'},
    checkpoint: {type:'string'}, report: {type:'string'}, resume: {type:'boolean'},
    apply: {type:'boolean'}, all: {type:'boolean'}, limit: {type:'string',default:'10'},
    scan: {type:'string',default:'providerEarnings'}, ids: {type:'string'}, cursor: {type:'string'},
  }});
  if (!v.url || !v['firebase-token-file'] || !v['iam-token-file'] || !v.checkpoint || !v.report ||
      !['bookings','providerEarnings'].includes(v.scan) || !/^https:\/\/[^/]+(?:\/[^?#]*)?$/.test(v.url) ||
      !Number.isInteger(Number(v.limit)) || Number(v.limit)<1 || Number(v.limit)>20 ||
      (v.apply && v.all) || (v.ids && (v.cursor || v.all || v.resume))) {
    throw Error('Invalid options. HTTPS URL, token files, checkpoint/report required; apply is one batch only.');
  }
  const lockPath=v.checkpoint+'.lock';
  const lock=fs.openSync(lockPath,'wx',0o600);
  fs.closeSync(lock);
  process.on('exit',()=>{try {fs.unlinkSync(lockPath);} catch {}});
  const config={url:v.url,scan:v.scan,dryRun:!v.apply,limit:Number(v.limit)};
  const ids=v.ids?.split(',');
  if (ids && (!ids.length || ids.length>20 || ids.some(id=>!id || id.includes('/')))) throw Error('Invalid IDs');
  let checkpoint={...config,cursor:v.cursor??null,retryIds:[],done:false,ids:ids??null,totals:{counts:{},summary:{},breakdown:{}}};
  if (v.resume) {
    checkpoint=JSON.parse(fs.readFileSync(v.checkpoint,'utf8'));
    for(const key of Object.keys(config)) if(checkpoint[key]!==config[key]) throw Error('Checkpoint configuration mismatch');
    if(checkpoint.done && !checkpoint.retryIds.length) {console.log('Scan already complete. Use new output files for another sweep.'); return;}
  } else if(fs.existsSync(v.checkpoint)||fs.existsSync(v.report)) throw Error('Output exists; use --resume or fresh paths');
  const save=()=>{fs.writeFileSync(v.checkpoint+'.tmp',JSON.stringify(checkpoint,null,2),{mode:0o600});fs.renameSync(v.checkpoint+'.tmp',v.checkpoint);};
  if(!v.resume) save();
  do {
    const retrying=checkpoint.retryIds.length>0;
    const input={dryRun:config.dryRun,scan:config.scan,limit:config.limit,
      ...(retrying?{ids:checkpoint.retryIds}:checkpoint.ids?{ids:checkpoint.ids}:checkpoint.cursor?{cursor:checkpoint.cursor}:{})};
    const token=path=>fs.readFileSync(path,'utf8').trim();
    const response=await fetch(v.url,{method:'POST',signal:AbortSignal.timeout(310000),headers:{
      'Content-Type':'application/json',
      Authorization:`Bearer ${token(v['firebase-token-file'])}`,
      'X-Serverless-Authorization':`Bearer ${token(v['iam-token-file'])}`,
    },body:JSON.stringify({data:input})});
    if(!response.ok) throw Error(`Callable HTTP ${response.status}; checkpoint retained. Refresh credentials/check server logs.`);
    const body=await response.json();
    if(body.error || !body.result || body.result.migrationVersion!==2) throw Error('Callable failed or wrong deployment version; checkpoint retained');
    const result=body.result;
    fs.appendFileSync(v.report,JSON.stringify({input,result})+'\n',{mode:0o600});
    if(!retrying) {checkpoint.cursor=result.nextCursor;checkpoint.done=!result.hasMore;}
    checkpoint.retryIds=result.retryIds;
    for(const group of ['counts','summary']) {
      for(const [key,value] of Object.entries(result[group])) checkpoint.totals[group][key]=(checkpoint.totals[group][key]??0)+value;
    }
    for(const [group,entries] of Object.entries(result.breakdown)) {
      checkpoint.totals.breakdown[group]??={};
      for(const [key,value] of Object.entries(entries)) checkpoint.totals.breakdown[group][key]=(checkpoint.totals.breakdown[group][key]??0)+value;
    }
    save();
    console.log(JSON.stringify({counts:result.counts,summary:result.summary,nextCursor:checkpoint.cursor,hasMore:!checkpoint.done,retryIds:checkpoint.retryIds,totals:checkpoint.totals}));
    if(checkpoint.retryIds.length) throw Error('Batch has failures; inspect report, then --resume retries these IDs first');
    if(!v.all || (checkpoint.done && !retrying) || checkpoint.ids) break;
    if(checkpoint.done) break;
  } while(true);
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});

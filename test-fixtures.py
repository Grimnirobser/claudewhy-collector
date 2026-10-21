import json, pathlib, subprocess, tempfile, hashlib
root=pathlib.Path(__file__).resolve().parent
exe=root/'build/溯因采集器.app/Contents/MacOS/collector'
with tempfile.TemporaryDirectory(prefix='suyin-fixtures-') as temp:
    d=pathlib.Path(temp); logs=d/'logs'; logs.mkdir()
    record={'type':'assistant','timestamp':'2026-10-20T10:00:00Z','sessionId':'12345678-1234-1234-1234-123456789abc','uuid':'23456789-1234-1234-1234-123456789abc','status_code':403,'isApiErrorMessage':True,'cwd':'SECRET_PATH','message':{'id':'msg_fixture','role':'assistant','content':'SECRET_CHAT','tool_result':'SECRET_TOOL','usage':{'input_tokens':120,'output_tokens':8,'secret':'SECRET_USAGE'}}}
    extra=[{'type':'system','subtype':'api_error','requestId':'req_fixture','isSidechain':True,'error':{'status':429},'content':'SECRET_ERROR'}, {'type':'api_error','content':'HTTP 503 SECRET_FAILURE'}, {'type':'assistant','isApiErrorMessage':True,'message':{'content':[{'text':'HTTP 401 SECRET_BLOCK'}]}}, {'type':'assistant','message':{'status_code':403}}, {'type':'user','content':'401 should not count'}]
    raw=('\n'.join(json.dumps(x) for x in [record]+extra)+'\ninvalid JSON\n').encode(); (logs/'a.jsonl').write_bytes(raw)
    (logs/'settings.json').write_text('SECRET_SETTINGS'); (logs/'credentials.json').write_text('SECRET_TOKEN')
    (logs/'large.jsonl').write_bytes(b'x'*(20*1024*1024+1))
    (logs/'link.jsonl').symlink_to(logs/'a.jsonl')
    out=d/'report.json'; subprocess.run([str(exe),'--fixture-test',str(logs),str(out)],check=True)
    text=out.read_text(); r=json.loads(text)
    assert r['schemaVersion']=='1.0' and r['kind']=='ban-evidence-diagnostic'
    assert r['system']['status']=='skipped' and r['network']['status']=='skipped'
    assert len(r['sessions']['records'])==6
    assert r['sessions']['filesScanned']==1 and r['sessions']['skippedFiles']==2 and r['sessions']['invalidLines']==1
    assert r['sessions']['records'][0]['message']['usage']=={'input_tokens':120,'output_tokens':8}
    errors=r['sessions']['records']
    assert errors[1]['subtype']=='api_error' and errors[1]['status_code']==429 and errors[1]['requestId']=='req_fixture' and errors[1]['isSidechain'] is True
    assert errors[2]['status_code']==503 and errors[3]['status_code']==401 and errors[4]['status_code']==403
    assert 'status_code' not in errors[5]
    assert r['sessions']['readErrors']==0
    assert r['sources'][0]['sha256']==hashlib.sha256(raw).hexdigest()
    assert r['sources'][0]['bytes']==len(raw)
    for secret in ['SECRET_ERROR','SECRET_FAILURE','SECRET_BLOCK','SECRET_CHAT','SECRET_PATH','SECRET_TOOL','SECRET_USAGE','SECRET_SETTINGS','SECRET_TOKEN',str(logs)]: assert secret not in text
    evidence=root/'test-evidence'; evidence.mkdir(exist_ok=True); (evidence/'synthetic-diagnostic.json').write_text(text)
    empty=d/'empty'; empty.mkdir(); subprocess.run([str(exe),'--fixture-test',str(empty),str(out)],check=True)
    assert json.loads(out.read_text())['sessions']['records']==[]
    subprocess.run([str(exe),'--fixture-test',str(d/'missing-directory'),str(out)],check=True)
    missing=json.loads(out.read_text())['sessions']; assert missing['status']=='error' and missing['readErrors']>0
    (evidence/'results.txt').write_text('PASS: nested error.status, system/subtype api_error, requestId, isSidechain, marked-error content status extraction, ordinary content not parsed, missing directory readErrors; synthetic JSONL metadata, 403 status, usage, SHA256 manifest, malformed line counting, >20MB skip, symlink skip, empty directory. PASS: no chat, tool results, local paths, config or credential content exported. System/network skipped for all tests; no real user logs read.\n')
print('PASS: synthetic fixtures and privacy assertions')

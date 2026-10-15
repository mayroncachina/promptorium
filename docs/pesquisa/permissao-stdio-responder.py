import json,subprocess,sys,time
p=subprocess.Popen([sys.argv[1],"-p","--model","haiku","--strict-mcp-config","--input-format","stream-json","--output-format","stream-json","--verbose","--permission-mode","default","--permission-prompt-tool","stdio","--tools","Bash"],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True,cwd=sys.argv[2])
p.stdin.write(json.dumps({"type":"user","message":{"role":"user","content":"Use the Bash tool to run exactly: curl -s https://example.com -o /dev/null && echo OK . Do nothing else."}})+"\n");p.stdin.flush()
for line in p.stdout:
    m=json.loads(line)
    if m.get("type")=="control_request":
        print("REQ",line[:300].strip()); time.sleep(5)
        r=m["request"]
        p.stdin.write(json.dumps({"type":"control_response","response":{"subtype":"success","request_id":m["request_id"],"response":{"behavior":"allow","updatedInput":r["input"]}}})+"\n");p.stdin.flush()
    elif m.get("type")=="user":
        print("TOOLRESULT",json.dumps(m["message"]["content"])[:200])
    elif m.get("type")=="result":
        print("RESULT",m.get("subtype"),str(m.get("result"))[:100]); p.stdin.close(); break

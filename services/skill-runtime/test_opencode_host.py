"""验证接入桥只暴露当前验证入口，认证失败不执行。无需调用云端。"""
import json,tempfile,unittest,urllib.request,urllib.error,threading,time
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
from opencode_host import Host

class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.count=0
        def verify():self.count+=1;return {'passed':False,'reason':'fixture'}
        self.host=Host(Path(self.tmp.name),'unused',{'url':'https://example.invalid','key':'not-sent'},verify)
        self.host.thread.start();self.addCleanup(self.host.close)
    def request(self,message,token=True):
        headers={'Content-Type':'application/json'}
        if token:headers['Authorization']='Bearer '+self.host.token
        req=urllib.request.Request('http://127.0.0.1:'+str(self.host.server.server_port)+'/mcp',data=json.dumps(message).encode(),headers=headers)
        with urllib.request.urlopen(req) as response:return json.loads(response.read())
    def test_only_verify_tool_is_exposed(self):
        result=self.request({'jsonrpc':'2.0','id':1,'method':'tools/list'})
        self.assertEqual([t['name'] for t in result['result']['tools']],['verify_skill'])
        self.request({'jsonrpc':'2.0','id':2,'method':'tools/call','params':{'name':'verify_skill','arguments':{}}})
        self.assertEqual(self.count,1)
    def test_completed_event_ends_bridge_without_waiting_for_upstream_eof(self):
        stop=threading.Event()
        class Upstream(BaseHTTPRequestHandler):
            protocol_version='HTTP/1.1'
            def log_message(self,*args):pass
            def do_POST(self):
                self.rfile.read(int(self.headers['Content-Length']))
                self.send_response(200);self.send_header('Content-Type','text/event-stream');self.end_headers()
                self.wfile.write(b'data: {"type":"response.completed","response":{"status":"completed"}}\n\n');self.wfile.flush()
                stop.wait(4)
                self.close_connection=True
        server=ThreadingHTTPServer(('127.0.0.1',0),Upstream);server.daemon_threads=True
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        self.host.provider['url']='http://127.0.0.1:'+str(server.server_port)
        req=urllib.request.Request('http://127.0.0.1:'+str(self.host.server.server_port)+'/v1/responses',data=b'{}',headers={'Authorization':'Bearer '+self.host.token})
        try:
            start=time.monotonic()
            with urllib.request.urlopen(req,timeout=2) as response:body=response.read()
            self.assertIn(b'response.completed',body);self.assertLess(time.monotonic()-start,2)
        finally:stop.set();server.shutdown();server.server_close()

    def test_no_auth_or_extra_arguments_cannot_execute(self):
        with self.assertRaises(urllib.error.HTTPError) as error:self.request({'id':1,'method':'tools/list'},False)
        self.assertEqual(error.exception.code,401)
        result=self.request({'id':2,'method':'tools/call','params':{'name':'verify_skill','arguments':{'path':'../other'}}})
        self.assertIn('error',result);self.assertEqual(self.count,0)

if __name__=='__main__':unittest.main()

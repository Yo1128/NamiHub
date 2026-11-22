"""Exercise the Windows binary, the public SDK and a real network media decoder."""
import argparse
import hashlib
import http.client
import http.server
import json
from pathlib import Path
import queue
import shutil
import ssl
import subprocess
import tempfile
import threading

PROJECT = Path(__file__).resolve().parents[1]


def require(condition, description):
    if not condition:
        raise AssertionError(description)


class RunningHub:
    def __init__(self, binary, root, state, launch=None):
        self.process = subprocess.Popen(
            launch or [str(binary), "--root", str(root), "--state", str(state), "--port", "0", "--trace-reads", "--operator-pipe"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, encoding="utf-8", errors="replace", bufsize=1)
        self.queue = queue.Queue()
        self.reads = []
        def collect():
            for line in self.process.stdout:
                if line.startswith("{"):
                    value = json.loads(line)
                    if value["event"] == "read":
                        self.reads.append(value)
                    else:
                        self.queue.put(value)
            self.queue.put({"event": "exit", "code": self.process.wait()})
        threading.Thread(target=collect, daemon=True).start()
        self.ready = self.event("ready")
        self.code = self.event("pairCode")["code"]
        self.origin = "https://127.0.0.1:" + str(self.ready["port"])
        self.cert = (state / "tls.pem").read_text("ascii").split("-----END CERTIFICATE-----")[0] + "-----END CERTIFICATE-----\n"
        self.context = ssl.create_default_context(cadata=self.cert)

    def event(self, kind):
        value = self.queue.get(timeout=20)
        require(value["event"] == kind, f"Expected {kind}, got {value['event']}")
        return value

    def command(self, line, kind):
        self.process.stdin.write(line + "\n")
        self.process.stdin.flush()
        return self.event(kind)

    def stop(self):
        if self.process.poll() is None:
            self.process.stdin.write("quit\n")
            self.process.stdin.flush()
            self.process.wait(timeout=15)
        require(self.process.returncode == 0, "Hub exited with an error")

    def request(self, method, path, status, token=None, headers=None, body=None):
        connection = http.client.HTTPSConnection("127.0.0.1", self.ready["port"], context=self.context, timeout=10)
        fields = dict(headers or {})
        if token:
            fields["Authorization"] = "Bearer " + token
        if body is not None:
            fields["Content-Type"] = "application/json"
        try:
            connection.request(method, path, json.dumps(body) if body is not None else None, fields)
            res = connection.getresponse()
            data = res.read()
            require(res.status == status, f"{method} {path}: expected {status}, received {res.status}")
            return dict((name.lower(), value) for name, value in res.getheaders()), data
        finally:
            connection.close()

    def pair(self, code, status):
        return json.loads(self.request("POST", "/v1/pair", status, body={"clientName":"Interop verifier","code":code})[1])


def verify(binary, work):
    media, state = work / "media", work / "state"
    shutil.copytree(PROJECT / "fixtures/media", media)
    subprocess.run(["powershell","-NoProfile","-ExecutionPolicy","Bypass","-File",str(PROJECT/"tool/init_tls.ps1"),"-StateDirectory",str(state)], check=True)
    hub = RunningHub(binary, media, state)
    try:
        require(hub.ready["resources"] == 5, "Wrong sample count")
        require(hub.ready["certificateSha256"] == hashlib.sha256(ssl.PEM_cert_to_DER_cert(hub.cert)).hexdigest(), "Displayed pin differs")
        hub.request("GET","/v1/resources",401)
        require(hub.pair("invalid",403)["error"]=="invalid_pair_code", "Pair failure")
        session = hub.pair(hub.code,201)
        token = session["accessToken"]
        require(hub.pair(hub.code,403)["error"]=="pairing_closed", "Reused code")
        code = hub.command("pair","pairCode")["code"]
        dart = shutil.which("dart")
        # Drop the first HTTPS body mid-file. The second request must seek past those bytes.
        payload = next(media.glob("*.txt")).read_bytes()
        offsets = []
        class InterruptedDownload(http.server.BaseHTTPRequestHandler):
            def log_message(self, *_): pass
            def do_GET(self):
                offset = int(self.headers.get("Range", "bytes=0-")[6:-1])
                offsets.append(offset)
                self.send_response(206 if offset else 200)
                self.send_header("ETag", '"'+hashlib.sha256(payload).hexdigest()+'"')
                self.send_header("Content-Length", str(len(payload)-offset))
                if offset: self.send_header("Content-Range", f"bytes {offset}-{len(payload)-1}/{len(payload)}")
                self.end_headers()
                self.wfile.write(payload[offset:] if len(offsets)>1 else payload[:8192])
        with http.server.ThreadingHTTPServer(("127.0.0.1",0),InterruptedDownload) as fault:
            tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            tls.load_cert_chain(state/"tls.pem")
            fault.socket = tls.wrap_socket(fault.socket,server_side=True)
            thread = threading.Thread(target=fault.serve_forever,daemon=True)
            thread.start()
            try:
                sdk = subprocess.run([dart,"run","tool/check_sdk.dart",hub.origin,hub.ready["certificateSha256"],str(work/"downloads"),str(PROJECT/"fixtures/catalog.json"),f"https://127.0.0.1:{fault.server_port}"],input=code+"\n",text=True,cwd=PROJECT,check=True,capture_output=True,timeout=90)
            finally: fault.shutdown()
        require(offsets == [0,8192], "SDK did not retry a truncated response at the correct byte")
        result = json.loads(sdk.stdout.strip().splitlines()[-1])
        require(result["sdk"]=="passed","SDK result")
        require(any(r["start"]==4096 and r["status"]==206 for r in hub.reads), "SDK did not resume using Range")
        records = json.loads(hub.request("GET","/v1/resources",200,token)[1])["items"]
        video = next(r for r in records if r["type"]=="video")
        content = "/v1/resources/"+video["resourceId"]+"/content"
        original = (media/video["displayName"]).read_bytes()
        for field, selected in [("bytes=12-29", original[12:30]), ("bytes=-16", original[-16:]), ("bytes=250-",original[250:])]:
            headers, data = hub.request("GET",content,206,token,{"Range":field})
            require(data==selected and headers["etag"]=='"'+video["contentVersion"]+'"',"Range differs")
        headers, data = hub.request("HEAD",content,206,token,{"Range":"bytes=2-8"})
        require(not data and headers["content-length"]=="7","HEAD")
        headers,_ = hub.request("GET",content,416,token,{"Range":f"bytes={len(original)}-"})
        require(headers["content-range"]==f"bytes */{len(original)}","416 size")
        hub.request("POST",content,405,token)
        hub.request("GET","/v1/resources?limit=0",400,token)
        hub.request("GET","/v1/resources/no-such-resource",404,token)

        # Decode the same frame locally and over authenticated HTTPS after a 23-second seek.
        ca = Path(hub.ready["publicCertificatePath"])
        require(ca.read_text("ascii").strip()==hub.cert.strip(),"Public certificate export")
        def decode(source, tls=()):
            cmd = ["ffmpeg","-v","error",*tls,"-ss","23","-i",source,"-map","0:v:0","-frames:v","1","-f","hash","-hash","sha256","-"]
            run = subprocess.run(cmd,capture_output=True,text=True,timeout=25)
            if run.returncode: raise RuntimeError(run.stderr.replace(token,"[redacted]"))
            return run.stdout.strip()
        local = decode(str(media/video["displayName"]))
        trace_start = len(hub.reads)
        remote = decode(hub.origin+content,["-tls_verify","1","-ca_file",str(ca),"-headers","Authorization: Bearer "+token+"\r\n"])
        require(remote==local and local.startswith("SHA256="),"Remote seek returned another frame")
        seek_reads = [r["start"] for r in hub.reads[trace_start:] if r["start"] > 0]
        require(seek_reads, "Decoder did not issue a nonzero range")

        book = next(r for r in records if r["displayName"].endswith(".txt"))
        book_path = "/v1/resources/"+book["resourceId"]+"/content"
        file = media/book["displayName"]
        file.write_bytes(file.read_bytes()+b"\nversion 2")
        hub.request("GET",book_path,409,token)
        hub.command("rescan","scanned")
        hub.request("GET",book_path,412,token,{"If-Match":'"'+book["contentVersion"]+'"'})
        file.rename(media/"renamed.txt")
        hub.request("GET",book_path,404,token)
        hub.command("relink "+book["resourceId"]+" renamed.txt","relinked")
        hub.request("GET",book_path,200,token)
        hub_id = hub.ready["hubId"]
        hub.stop()
        hub = RunningHub(binary,media,state)
        require(hub.ready["hubId"]==hub_id, "Hub identity changed")
        hub.request("GET",book_path,200,token)
        require(hub.command("revoke "+session["deviceId"],"revoked")["found"], "Unknown device")
        hub.request("GET",content,401,token)
        hub.stop()
        hub = RunningHub(binary,media,state)
        hub.request("GET",content,401,token)
        return {"sdk":result["sdk"],"fixtureFiles":len(records),"sdkResumeByte":4096,"automaticRetryByte":offsets[1],"videoSeekSeconds":23,
                "decoderRangeOffsets":seek_reads,"decodedFrame":remote,"authAndVersions":"passed","persistenceAndRevocation":"passed"}
    finally:
        hub.stop()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--exe",type=Path,default=PROJECT/"build/nami_hub.exe")
    args = parser.parse_args()
    try:
        with tempfile.TemporaryDirectory(prefix="namihub-interop-") as folder:
            print(json.dumps(verify(args.exe.resolve(),Path(folder)),indent=2))
    except subprocess.CalledProcessError as exc:
        if exc.stderr: print(exc.stderr)
        raise

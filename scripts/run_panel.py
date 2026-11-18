#!/usr/bin/env python3
from gevent import monkey
monkey.patch_all()
import os, ssl
os.chdir("/www/server/panel")
from BTPanel import app
from gevent.pywsgi import WSGIServer
from geventwebsocket.handler import WebSocketHandler

def main():
    with open("data/port.pl", encoding="utf-8") as f: port = int(f.read().strip())
    if not 1 <= port <= 65535: raise RuntimeError("Invalid panel port")
    host = "::" if os.path.exists("data/ipv6.pl") else "0.0.0.0"
    kwargs = {"handler_class": WebSocketHandler}
    if os.path.exists("data/ssl.pl") and os.path.isfile("ssl/privateKey.pem") and os.path.isfile("ssl/certificate.pem") and not os.path.exists("data/debug.pl"):
        ctx = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
        ctx.load_cert_chain("ssl/certificate.pem", "ssl/privateKey.pem")
        ctx.options |= getattr(ssl, "OP_NO_SSLv2", 0) | getattr(ssl, "OP_NO_SSLv3", 0)
        try: ctx.set_ciphers("ECDHE-RSA-AES128-GCM-SHA256:HIGH:!aNULL:!MD5:!RC4:!DHE")
        except ssl.SSLError: pass
        kwargs["ssl_context"] = ctx
    pid_path = "logs/panel.pid"
    os.makedirs("logs", exist_ok=True)
    with open(pid_path, "w", encoding="utf-8") as f:
        f.write(str(os.getpid()))
    try:
        WSGIServer((host, port), app, **kwargs).serve_forever()
    finally:
        try:
            os.remove(pid_path)
        except OSError:
            pass

if __name__ == "__main__": main()

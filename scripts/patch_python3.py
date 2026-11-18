#!/usr/bin/env python3
from pathlib import Path
ROOT = Path("/www/server/panel")
PATCHES = {
 "class/panelSafe.py": [
  ("print 'scanning ' + filename,", "print('scanning ' + filename, end=' ')"),
  ("print '  done'", "print('  done')")],
 "class/panelPort.py": [
  ("except Exception,e:", "except Exception as e:"),
  ("print str(ports)", "print(str(ports))")],
 "class/panelPing.py": [
  ("except socket.error, (errno, msg):",
   "except socket.error as exc:\n        errno = exc.errno if exc.errno is not None else (exc.args[0] if exc.args else None)\n        msg = str(exc)"),
  ("except socket.gaierror, e:", "except socket.gaierror as e:"),
  ("print verbose_ping(sys.argv[1],2)", "print(verbose_ping(sys.argv[1],2))")],
 "class/btkill.py": [
  ('print log + " >> killed\\n";', 'print(log + " >> killed\\n")'),
  ("except Exception as ex:print str(ex)", "except Exception as ex:\n                print(str(ex))"),
  ("print '======================================='", "print('=======================================')"),
  ('print "查杀完成, 共查杀["+str(num)+"]个异常进程!"', 'print("查杀完成, 共查杀["+str(num)+"]个异常进程!")'),
  ('print "官网: https://www.bt.cn/bbs"', 'print("官网: https://www.bt.cn/bbs")'),
  ('print "正在检测异常进程..."', 'print("正在检测异常进程...")')],
 "class/sewer/dns_providers/auroradns.py": [
  ('extractedDomain.subdomain is ""', 'extractedDomain.subdomain == ""')]
}
for rel, pairs in PATCHES.items():
    p = ROOT / rel
    if not p.is_file(): raise SystemExit("Missing source: " + str(p))
    s = p.read_text(encoding="utf-8")
    for old, new in pairs:
        if old in s: s = s.replace(old, new)
        elif new not in s: raise SystemExit("Patch context mismatch: " + rel + " :: " + repr(old))
    p.write_text(s, encoding="utf-8")
print("Python 3 compatibility patches applied.")

#!/usr/bin/env python3
import sys, re, secrets, string
if len(sys.argv) != 2:
    print("Usage: gen_secrets.py PATH_TO_ENV"); exit(1)
path = sys.argv[1]
content = open(path,"r",encoding="utf-8").read()
def make_secret(n=64):
    alphabet = string.ascii_letters + string.digits + string.punctuation
    safe = alphabet.replace('"','').replace("'","").replace("`","").replace("$","").replace("\\","")
    return ''.join(secrets.choice(safe) for _ in range(n))
for key in ("NETBOX_SECRET_KEY","NAUTOBOT_SECRET_KEY"):
    pattern = re.compile(rf"^{key}=.*$", re.MULTILINE)
    m = re.search(pattern, content)
    if not m or "changeme" in m.group(0):
        new_line = f"{key}={make_secret()}"
        content = re.sub(pattern, new_line, content) if m else content + f"\n{new_line}\n"
open(path,"w",encoding="utf-8").write(content)
print("Secrets generated/updated in .env")

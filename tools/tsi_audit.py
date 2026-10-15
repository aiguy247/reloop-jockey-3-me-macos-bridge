#!/usr/bin/env python3
"""Read-only Traktor TSI Controller Mappings summary."""
from pathlib import Path
import sys, re, base64, struct, hashlib

def read_chunk(data, off):
    tag=data[off:off+4].decode("latin1")
    n=struct.unpack(">I",data[off+4:off+8])[0]
    end=off+8+n
    if end>len(data): raise ValueError(tag)
    return tag,data[off+8:end],end

def chunks(payload):
    out=[]; off=0
    while off<len(payload):
        t,p,off=read_chunk(payload,off); out.append((t,p))
    return out

def parse(path):
    raw=Path(path).read_bytes()
    text=raw.decode("utf-8")
    m=re.search(r'(<Entry Name="DeviceIO\.Config\.Controller" Type="3" Value=")([^"]+)(")',text)
    if not m: raise ValueError("Controller entry not found")
    binary=base64.b64decode(m.group(2),validate=True)
    t,outer,end=read_chunk(binary,0)
    if t!="DIOM" or end!=len(binary): raise ValueError("DIOM")
    devpay=next(p for t,p in chunks(outer) if t=="DEVS")
    count=struct.unpack(">I",devpay[:4])[0]
    devs=[]; off=4
    for _ in range(count):
        t,p,off=read_chunk(devpay,off)
        if t!="DEVI": raise ValueError("DEVI")
        devs.append(p)
    return raw,devs

def info(devi):
    n=struct.unpack(">I",devi[:4])[0]
    pref=4+2*n
    generic=devi[4:pref].decode("utf-16-be")
    t,ddat,end=read_chunk(devi,pref)
    name=""; ddcb=None
    for tt,p in chunks(ddat):
        if tt=="DDIC":
            nn=struct.unpack(">I",p[:4])[0]
            name=p[4:4+2*nn].decode("utf-16-be")
        elif tt=="DDCB": ddcb=p
    ccount=bcount=0
    if ddcb:
        cmas=dcbm=None
        for tt,p in chunks(ddcb):
            if tt=="CMAS": cmas=p
            elif tt=="DCBM": dcbm=p
        if cmas is not None: ccount=struct.unpack(">I",cmas[:4])[0]
        if dcbm is not None: bcount=struct.unpack(">I",dcbm[:4])[0]
    return name,generic,ccount,bcount,ddat

if __name__=="__main__":
    if len(sys.argv)!=2: raise SystemExit("usage: tsi_audit.py file.tsi")
    raw,devs=parse(sys.argv[1])
    print("SHA-256:",hashlib.sha256(raw).hexdigest())
    print("Size:",len(raw))
    print("Devices:",len(devs))
    bridge="Reloop Jockey 3 ME (Bridge)".encode("utf-16-be")
    for i,d in enumerate(devs):
        name,generic,cc,bc,ddat=info(d)
        print(f"{i:02d} {name or '(unnamed)'} | {generic} | commands={cc} bindings={bc} bridge_refs={ddat.count(bridge)}")

"""Reproducible module and source ZIPs. Python standard library only."""
from pathlib import Path
import hashlib
import zipfile

ROOT=Path(__file__).resolve().parents[1]
DIST=ROOT/'dist'
VERSION='0.1.3'
STAMP=(2026,10,22,0,0,0)
EXCLUDE={'dist','tools','test-results','node_modules','.git','__pycache__'}

def data(path):
    raw=path.read_bytes()
    if path.suffix not in {'.png','.jpg','.zip'}:
        raw=raw.replace(b'\r\n',b'\n')
    return raw

def archive(output,entries):
    with zipfile.ZipFile(output,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for name,path in sorted(entries):
            raw=data(path)
            if name.endswith(('.sh','.js','.html','.css','.py','.md')) and (b'\r\n' in raw or raw.startswith(b'\xef\xbb\xbf')):
                raise ValueError('Unexpected encoding: '+name)
            info=zipfile.ZipInfo(name,STAMP)
            executable=path.suffix=='.sh' or path.name=='dirbridge'
            info.create_system=3
            info.external_attr=(0o100755 if executable else 0o100644)<<16
            info.compress_type=zipfile.ZIP_DEFLATED
            z.writestr(info,raw,compress_type=zipfile.ZIP_DEFLATED,compresslevel=9)
    with zipfile.ZipFile(output) as z:
        assert z.testzip() is None
        assert len(z.namelist())==len(set(z.namelist()))
    return hashlib.sha256(output.read_bytes()).hexdigest()

def main():
    DIST.mkdir(exist_ok=True)
    module=[(p.relative_to(ROOT/'module').as_posix(),p) for p in (ROOT/'module').rglob('*') if p.is_file()]
    module += [('LICENSE',ROOT/'LICENSE'),('README.md',ROOT/'README.md')]
    required={'module.prop','customize.sh','service.sh','bin/dirbridge','bin/lib.sh','bin/control.sh','webroot/index.html'}
    assert required <= {x[0] for x in module}
    assert 'version=v'+VERSION in (ROOT/'module/module.prop').read_text(encoding='utf-8')
    sources=[]
    for p in ROOT.rglob('*'):
        if not p.is_file():continue
        rel=p.relative_to(ROOT)
        if any(part in EXCLUDE for part in rel.parts) or p.suffix=='.pyc':continue
        sources.append(('DirBridge/'+rel.as_posix(),p))
    outputs=[(DIST/f'DirBridge-v{VERSION}.zip',module),(DIST/f'DirBridge-v{VERSION}-source.zip',sources)]
    lines=[]
    for output,entries in outputs:
        digest=archive(output,entries)
        lines.append(f'{digest}  {output.name}\n')
        print(f'{output.name}: {output.stat().st_size} bytes; SHA256 {digest}')
    (DIST/'SHA256SUMS.txt').write_text(''.join(lines),encoding='utf-8',newline='\n')

if __name__=='__main__':main()

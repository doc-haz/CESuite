"""Cross-check conservative Lua/Python boundaries; no inspected code executes."""
import argparse
import json
import re
from pathlib import Path
import sys
import tempfile
from replay_dependencies import replay

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'analyzer/src'))
from ct_analyzer.core import analyze, source_rows, aa_lines, arguments


def check(library):
    cases = [
        '{$luacode}\nalloc(fake,16)\naobscanmodule(fake,x,90)\nregistersymbol(fake)\n{$asm}\nalloc(real,16)',
        '{$luacode x}\n{$lua}\nalloc(fake,16)\n{$asm}',
        '{$luacode}\n--[=[\n{$asm}\nalloc(fake,16)\n]=]\n{$asm}\nalloc(real,16)',
        '{$luacode}\nlocal s=[=[\n{$asm}\nalloc(fake,16)\n]=]\n{$asm}',
        '{$luacode}\n--[[\n{$asm}\nalloc(fake,16)',
        '{$ifdef X}\nalloc(fake,16)\n{$ifndef Y}\naobscan(fake,90)\n{$endif}\n{$endif}\nalloc(real,16)',
        '{$endif}\nalloc(real,16)',
        '{$ifdef X}\nregistersymbol(fake)',
        '/* comment */ {$luacode}\nalloc(fake,16)\n{$asm}\nalloc(real,16)',
        '/*\n{$lua}\nalloc(fake,16)\n*/\nalloc(real,16)',
        '{$lua}\n--[[\n{$asm}\nalloc(fake,16)\n]]\n{$asm}\nalloc(real,16)',
        'alloc(real,16)\naobscanmodule(anchor,test.exe,90)\nregistersymbol(real)',
    ]
    cases += [cmd + '(symbol,fn("a,b",nested(1,2)),90)\nalloc(real,16)'
              for cmd in ('HOOK', 'UNHOOK', 'HOOK5', 'aobscanfunction', 'aobscanregion')]
    cases += [
        '{$luacode\nalloc(fake,16)\naobscan(fake,90)\nlabel(fake)\ndefine(fake,real)\nfake:',
        'alloc(prefix,16) {$luacode}\nalloc(fake,16)\n{$asm}\nalloc(real,16)',
        '{$ifdef X}{$endif}\nalloc(real,16)',
        '{$ifndef X}{$endif}\nalloc(real,16)',
        '{$ifdef X}{$ifndef Y}{$endif}{$endif}\nalloc(real,16)',
        '{$ifdef X}{$endif}{$endif}\nalloc(real,16)',
        '[ENABLE]\n{$ifdef X}\n[DISABLE]\n{$endif}\nalloc(real,16)\naobscan(anchor,90)',
        '[DISABLE]\n{$ifdef X}\n[ENABLE]\n{$endif}\nalloc(real,16)\nregistersymbol(real)',
        '{$ifdef X}[ENABLE]{$endif}\nalloc(real,16)',
        '{$ifdef X}\n[DISABLE]\n{$endif}\n[ENABLE]\nalloc(real,16)',
        '{$ifdef X} // {$endif}\nalloc(fake,16)\n{$endif}\nalloc(real,16)',
        '{$ifdef X} /* {$endif} */\nalloc(fake,16)\n{$endif}\nalloc(real,16)',
        '// {$luacode\nalloc(real,16)',
        'define(quoted,"{$luacode}")\nalloc(real,16)',
        '[ENABLE]\nalloc(buffer,16)\nregistersymbol(buffer)\n[DISABLE]\nunregistersymbol(buffer)\ndealloc(buffer)',
        'define(alias,anchor)\nlabel(anchor)\naobscan(anchor,90 ??)\nanchor:',
        'aobscanmodule(anchor,"C:/game.exe",90)\naobscanmodule(other,,90)',
        '{$lua}\nSHARED_GLOBAL = OTHER_GLOBAL\n{$asm}\nalloc(real,16)',
        '{$lua}\nlocal s=[=[\n{$asm}\nalloc(fake,16)\n]=]\nSHARED_GLOBAL=OTHER_GLOBAL\n{$asm}\nalloc(real,16)',
        '{$luacode}\n[DISABLE]\n{$asm}\nalloc(real,16)',
        '{$lua}\n[ENABLE]\nSHARED_GLOBAL=OTHER_GLOBAL\n[DISABLE]\nSHARED_GLOBAL=nil\n{$asm}',
        '{$ifndef X}{$ifdef Y}\nalloc(fake,16)\n{$endif}{$endif}\nalloc(real,16)',
        '{$luacode\n--[[\n{$asm}\nalloc(fake,16)',
    ]
    rules = {'OPAQUE-SOURCE','OPAQUE-COMMAND','OPAQUE-INCOMPLETE',
             'CONDITIONAL-SOURCE','CONDITIONAL-UNMATCHED','SECTION-INDETERMINATE'}
    fields = ('command','arguments','section','line')
    def projection(rows):
        return sorted((tuple(json.dumps(row[k],sort_keys=True) for k in fields) for row in rows))

    def aa_dependencies(py, text):
        # The offline analyzer has a cross-script provider/consumer contract, while
        # runtime has per-occurrence dependencies. Project their common AA command
        # observations into occurrence tuples, without asserting equal JSON shapes.
        out=[]
        def add(row,name,kind,relation):
            if re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*',name) and not re.fullmatch(r'[0-9A-Fa-f]+',name):
                out.append((row['line'],row['section'],row['command'],name,kind,relation))
        for row in py['allocations']+py['symbols']+py['aobs']:
            cmd,args=row['command'],row['arguments']
            if cmd in ('aobscan','aobscanmodule') and len(args)=={'aobscan':2,'aobscanmodule':3}[cmd]:
                add(row,args[0],'symbol','provides')
            elif cmd=='define' and len(args)==2:
                add(row,args[0],'symbol','provides');add(row,args[1],'symbol','requires')
            elif cmd=='label' and len(args)==1: add(row,args[0],'symbol','provides')
            elif (cmd=='alloc' and len(args) in (2,3)) or (cmd=='globalalloc' and len(args)==2):
                add(row,args[0],'resource','provides');add(row,args[0],'symbol','provides')
                if len(args)==3: add(row,args[2],'symbol','requires')
            elif cmd in ('registersymbol','unregistersymbol'):
                for name in args:
                    add(row,name,'symbol','requires')
                    if cmd=='registersymbol': add(row,name,'registered_symbol','provides')
            elif cmd=='dealloc' and len(args)==1: add(row,args[0],'resource','requires')
        section='common'
        for line,content in aa_lines(text):
            if content.strip().lower() in ('[enable]','[disable]','[unknown]'):
                section=content.strip()[1:-1].lower()
            elif content.strip().endswith(':'):
                add(dict(line=line,section=section,command='address_label'),content.strip()[:-1].strip(),'symbol','requires')
        return sorted(out)

    with tempfile.TemporaryDirectory(prefix='CESuite parser parity ') as directory:
        directory = Path(directory)
        for i, text in enumerate(cases,1):
            source = directory / 'input.json'
            source.write_text(json.dumps({'scripts':[{'id':'s','language':'AA','text':text}]}),encoding='utf-8')
            lua = replay(source,directory/'result.json',library)
            import xml.etree.ElementTree as ET
            root=ET.Element('CheatTable');entries=ET.SubElement(root,'CheatEntries')
            entry=ET.SubElement(entries,'CheatEntry');ET.SubElement(entry,'AssemblerScript').text=text
            py=analyze(ET.tostring(root))
            py_resources=[x for x in py['allocations']+py['symbols']
                          if x['command'] in ('alloc','globalalloc','dealloc','registersymbol','unregistersymbol')]
            assert projection([x for x in lua['resources'] if x['command']!='lua_rva_hook']) == projection(py_resources), ('resources',i)
            assert projection(lua['aobs']) == projection(py['aobs']), ('aobs',i)
            assert [(x['rule'],x['line']) for x in lua['diagnostics'] if x['rule'] in rules] == [
                (x['rule'],x['line']) for x in py['warnings'] if x['rule'] in rules], ('diagnostics',i,[(x['rule'],x['line']) for x in lua['diagnostics'] if x['rule'] in rules],[(x['rule'],x['line']) for x in py['warnings'] if x['rule'] in rules])
            actual=sorted((x['line'],x['section'],x['command'],x['name'],x['kind'],x['relation'])
                          for x in lua['dependencies'] if x['source']=='lexical')
            assert actual == aa_dependencies(py,text), ('AA dependencies',i,actual,aa_dependencies(py,text))
            # Embedded script text and exact source boundaries, including section splits.
            chunks=[];chunk=[];start=None
            for line,kind,content,_ in list(source_rows(text))+[(0,'asm','',None)]:
                if kind=='lua':
                    if start is None: start=line
                    chunk.append(content)
                elif start is not None:
                    chunks.append((start,'\n'.join(chunk)));chunk=[];start=None
            expected=[x for x in chunks if x[1].strip()]
            assert [(x['line'],x['text']) for x in lua['scripts'] if x['text'].strip()] == expected, ('Lua boundaries',i)
            assert [x['text'] for x in py['scripts'] if x['language']=='Lua' and x['text'].strip()] == [x[1] for x in expected], ('Python chunks',i)
            for row in lua['aobs']:
                assert row['status']=='not_scanned' and row['uniqueness']=='unverified', ('AOB status',i)
            assert all(x['uniqueness']=='unverified' for x in py['aobs']), ('Python AOB status',i)
            # Both contracts must exclude opaque providers from cross-script graphs.
            second=ET.SubElement(entries,'CheatEntry');ET.SubElement(second,'Address').text='fake'
            cross=analyze(ET.tostring(root))
            visible=any(x['relation']=='provides' and x['name']=='fake' for x in lua['dependencies'])
            assert bool([x for x in cross['dependencies'] if x['symbol']=='fake']) == visible, ('provider graph',i)
            if 'SHARED_GLOBAL' in text:
                # Fixed expectations for simple embedded chunks; no Lua is evaluated.
                globals_=[(x['name'],x['relation'],x['section']) for x in lua['dependencies'] if x['source']=='lua_lexical']
                assert ('SHARED_GLOBAL','provides','common' if '[ENABLE]' not in text else 'enable') in globals_, ('Lua dependencies',i)
                assert all(x['status']=='unverified' for x in lua['dependencies'])
    print(f'{len(cases)} Lua/Python parity cases passed (commands, arguments, sections, lines, resources, AOB state, dependency projections, embedded boundaries, diagnostics)')



if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--library',type=Path,required=True)
    check(parser.parse_args().library)

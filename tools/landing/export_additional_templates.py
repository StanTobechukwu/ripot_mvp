"""Export catalogue-only structures; preserve the four bundled starter bytes."""
import json
from pathlib import Path
from additional_templates import TEMPLATES
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/'landing/y/templates/downloads'
samples_path = ROOT/'tools/landing/example_values.json'
samples = json.loads(samples_path.read_text())
metadata = []
for spec in TEMPLATES:
    slug = spec['slug']; roots = []; values = {}; ids = set()
    def node(key, title, children=None, unit='', options=None, numeric=False):
        if key in ids: raise ValueError(f'Duplicate field: {slug}/{key}')
        ids.add(key)
        return dict(type='section',id=key,title=title,collapsed=False,
                    style=dict(level='h4',bold=True,align='left'),inputType='singleSelect' if options else 'numeric' if numeric else 'freeText',
                    options=options or [],unit=unit,showInPdf=True,addToRecords=False,addToLog=False,
                    allowOptionalNote=False,conditionalParentSectionId='',conditionalEquals='',indent=0,children=children or [])
    for index, (title, fields) in enumerate(spec['groups']):
        children=[]
        for f in fields:
            children.append(node(f['key'],f['title'],unit=f['unit'],options=f['options'],numeric=f['numeric']))
            values[f['key']]=f['example']
        roots.append(node(f'group_{index}',title,children))
    payload=dict(app='Ripot',ripotFileType='template',ripotExportVersion=1,template=dict(
        templateId='ripot_public_'+slug.removesuffix('-template').replace('-','_'),
        updatedAtIso='2026-10-25T00:00:00.000', name=spec['name'],groupName='',recordsConfigured=False,roots=roots,signature={}))
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/f'{slug}.ripottemplate.json').write_text(json.dumps(payload,indent=2,ensure_ascii=False)+'\n')
    samples[slug]=values
    metadata.append({k:spec[k] for k in ['slug','name','specialty','description','references']})
samples_path.write_text(json.dumps(samples,indent=2,ensure_ascii=False)+'\n')
(ROOT/'tools/landing/additional_catalog.json').write_text(json.dumps(metadata,indent=2)+'\n')
print(f'Exported {len(metadata)} additional blank structures and separate fictional fixtures.')

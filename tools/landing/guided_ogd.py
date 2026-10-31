"""Guided OGD: blank structured fields and independent repeatable findings.
No automatic diagnosis, risk scoring, treatment advice, Registry or research fields.
"""
VALUES = {}
def field(key, title, options=None, unit='', example='', multi=False, parent='', equals='', children=None, note=False):
    VALUES[key] = example
    return dict(type='section',id=key,title=title,collapsed=False,
        style=dict(level='h4',bold=True,align='left'),
        inputType=('multiSelect' if multi else 'singleSelect') if options else 'numeric' if unit else 'freeText',
        options=options or [],unit=unit,showInPdf=True,omitWhenEmpty=True,addToRecords=False,addToLog=False,
        allowOptionalNote=note,conditionalParentSectionId=parent,conditionalEquals=equals,
        indent=0,children=children or [])
def group(key,title,children):
    n=field(key,title,children=children);VALUES.pop(key,None);return n
def condition(n,parent,value):
    return dict(n,conditionalParentSectionId=parent,conditionalEquals=value)
def repeat(key,title,types,parent='',equals='',label='Add finding'):
    n=group(key,title,[]);n.update(repeatableTemplates=types,repeatableAddLabel=label,
        conditionalParentSectionId=parent,conditionalEquals=equals);return n
YES=['Yes','No','Not assessed']
LOCATIONS={
 'oesophagus':['Upper oesophagus','Middle oesophagus','Lower oesophagus','Gastro-oesophageal junction','Multiple regions','Other'],
 'stomach':['Cardia','Fundus','Body','Incisura','Antrum','Pylorus','Multiple regions','Other'],
 'duodenum':['Bulb','Second part','Beyond second part','Multiple regions','Other']}
FORREST=['Ia — spurting','Ib — oozing','IIa — non-bleeding visible vessel','IIb — adherent clot','IIc — flat pigmented spot','III — clean base','Not assessed','Not applicable']

def finding(region,kind,title,extras=(),size=False,biopsy=True,diffuse=False):
    k=region+'_'+kind
    fields=[field(k+'_location','Location',LOCATIONS[region],multi=diffuse,note=True)]
    if region=='stomach':
        fields.append(field(k+'_surface','Surface / curvature, if relevant',['Lesser curvature','Greater curvature','Anterior wall','Posterior wall','Circumferential','Other'],note=True))
    if size: fields.append(field(k+'_size','Size','',unit='mm'))
    fields.extend(extras)
    fields.append(field(k+'_description','Additional description, if needed'))
    if biopsy:
        fields += [field(k+'_biopsy','Biopsy taken?',YES,children=[
            field(k+'_container','Specimen container / label',parent=k+'_biopsy',equals='Yes'),
            field(k+'_biopsy_note','Sampling details, if needed',parent=k+'_biopsy',equals='Yes')])]
    fields += [field(k+'_treated','Treatment performed?',YES,children=[
        field(k+'_method','Treatment method',['Clips','Thermal therapy','Injection','Band ligation','Dilatation','Polypectomy','EMR','ESD','Other'],multi=True,parent=k+'_treated',equals='Yes',note=True),
        field(k+'_treatment_detail','Device / agent, dose and treatment details',parent=k+'_treated',equals='Yes'),
        field(k+'_outcome','Immediate outcome',['Completed','Partially completed','Unsuccessful','Not assessable'],parent=k+'_treated',equals='Yes',note=True)])]
    return group(k,title,fields)
def f(region,kind,label,options=None,unit='',suffix=None):
    return field(region+'_'+kind+'_'+(suffix or label.lower().replace(' ','_')),label,options,unit)
def ulcer(region):
    return finding(region,'ulcer','Ulcer',[
        f(region,'ulcer','Number at this location',unit='count',suffix='count'),
        f(region,'ulcer','Bleeding stigmata / Forrest category',FORREST,suffix='forrest')],size=True)
def lesion(region,kind,title):
    return finding(region,kind,title,[f(region,kind,'Morphology',['Pedunculated','Sessile','Flat','Elevated','Depressed','Ulcerated','Other'],suffix='morphology')],size=True)
def types(region):
    if region=='oesophagus':
        return [finding(region,'reflux','Reflux oesophagitis',[f(region,'reflux','Los Angeles grade',['A','B','C','D','Not assessed'],suffix='la')],biopsy=False,diffuse=True),
        finding(region,'barrett','Suspected / known Barrett’s',[f(region,'barrett','Prague C',unit='cm',suffix='c'),f(region,'barrett','Prague M',unit='cm',suffix='m'),f(region,'barrett','Visible lesion?',YES,suffix='lesion'),f(region,'barrett','Biopsy protocol',['Targeted','Seattle','Other','Not performed'],suffix='protocol')]),
        finding(region,'hernia','Hiatal hernia',[f(region,'hernia','Axial length',unit='cm',suffix='length'),f(region,'hernia','Hill grade',['I','II','III','IV','Not assessed'],suffix='hill')],biopsy=False),
        finding(region,'eoe','EoE features',[f(region,'eoe','Oedema',['Absent','Present','Not assessed'],suffix='oedema'),f(region,'eoe','Rings',['Absent','Mild','Moderate','Severe','Not assessed'],suffix='rings'),f(region,'eoe','Exudates',['Absent','Present','Not assessed'],suffix='exudates'),f(region,'eoe','Furrows',['Absent','Present','Not assessed'],suffix='furrows'),f(region,'eoe','Stricture',YES,suffix='stricture')],diffuse=True),
        finding(region,'varices','Oesophageal varices',[f(region,'varices','Size',['Small','Large','Not assessed'],suffix='size_grade'),f(region,'varices','Red signs',YES,suffix='red'),f(region,'varices','Bleeding',['None seen','Active','Recent stigmata','Not assessed'],suffix='bleeding')],biopsy=False),
        finding(region,'stricture','Ring / web / stricture',[f(region,'stricture','Type',['Ring','Web','Stricture','Other'],suffix='type'),f(region,'stricture','Length',unit='cm',suffix='length'),f(region,'stricture','Minimum diameter',unit='mm',suffix='diameter')]),
        finding(region,'candida','Suspected candidiasis',diffuse=True),ulcer(region),lesion(region,'lesion','Mass / lesion'),finding(region,'other','Other finding')]
    if region=='stomach':
        return [ulcer(region),finding(region,'gastritis','Gastritis / erythema',diffuse=True),finding(region,'erosions','Erosions',diffuse=True),
        lesion(region,'polyp','Polyp'),lesion(region,'lesion','Mass / lesion'),
        finding(region,'atrophy','Suspected atrophy / intestinal metaplasia',[f(region,'atrophy','Appearance',['Atrophy','Intestinal metaplasia suspected','Both','Uncertain'],suffix='appearance')],diffuse=True),
        finding(region,'varices','Gastric varices',[f(region,'varices','Sarin type',['GOV1','GOV2','IGV1','IGV2','Not classified'],suffix='sarin'),f(region,'varices','Bleeding',['None seen','Active','Recent stigmata','Not assessed'],suffix='bleeding')],biopsy=False),
        finding(region,'phg','Portal hypertensive gastropathy',[f(region,'phg','Severity',['Mild','Severe','Not graded'],suffix='severity')],biopsy=False,diffuse=True),
        finding(region,'gave','GAVE',biopsy=False,diffuse=True),finding(region,'retained','Retained food / fluid',biopsy=False,diffuse=True),finding(region,'surgery','Post-surgical anatomy',biopsy=False),finding(region,'other','Other finding')]
    return [ulcer(region),finding(region,'duodenitis','Erosions / duodenitis',diffuse=True),finding(region,'villous','Suspected villous atrophy',[f(region,'villous','Appearance',['Scalloping','Reduced folds','Mosaic pattern','Other'],suffix='appearance')],diffuse=True),lesion(region,'polyp','Polyp'),lesion(region,'lesion','Mass / ampullary lesion'),finding(region,'stenosis','Stenosis',size=True),finding(region,'diverticulum','Diverticulum',biopsy=False),finding(region,'other','Other finding')]

def build():
    VALUES.clear()
    roots=[group('procedure','Procedure',[
        field('indication','Indication',['Dyspepsia','Reflux','Dysphagia','Upper GI bleeding','Anaemia','Weight loss','Barrett’s surveillance','Variceal assessment','EoE assessment','Ulcer follow-up','Other'],example='Dyspepsia',multi=True,note=True),
        field('consent','Consent',['Obtained','Not obtained','Emergency exception documented','Documented elsewhere'],example='Obtained',note=True),
        field('fasting','Fasting status',['Confirmed','Not fasted','Uncertain','Documented elsewhere'],example='Confirmed',note=True),
        field('antithrombotics','Anticoagulant / antiplatelet medication',['None reported','Anticoagulant','Antiplatelet','Both','Unknown'],example='None reported',note=True),
        field('safety','Pre-procedure safety assessment',['Completed','Concern identified','Documented elsewhere','Not recorded'],example='Completed',note=True),
        field('sedation','Sedation / anaesthesia',['None','Topical anaesthesia only','Moderate sedation','Deep sedation','General anaesthesia'],example='None',note=True),
        field('sedation_drugs','Drugs and doses, if administered'),
        field('medication_plan','Other medications'),
        field('extra_details','Additional procedure details?',['Yes','No'],example='No',children=[
          field('scope','Endoscope used',parent='extra_details',equals='Yes'),
          field('asa','ASA class',['I','II','III','IV','V','VI','Not assessed'],parent='extra_details',equals='Yes')]),
    ]),group('extent_view','Extent and view',[
        field('extent','Extent reached',['Oesophagus','Stomach','Duodenal bulb','Second part of duodenum','Beyond second part','Other'],example='Second part of duodenum',note=True),
        field('view','Quality of view',['Adequate','Limited','Cannot assess'],example='Adequate',note=True),
        field('limitations','Limitations / reason for incomplete examination, if applicable'),
        field('duration','Examination duration, if recorded',unit='min',example='8'),
    ])]
    for region in LOCATIONS:
        roots.append(group(region+'_region',region.title(),[
            field(region+'_status',region.title()+' assessment',['Normal','Abnormal','Not examined','Cannot assess'],example='Normal',note=True),
            repeat(region+'_findings',region+' finding',types(region),parent=region+'_status',equals='Abnormal')]))
    roots += [group('closing','Conclusion and follow-up',[
        field('events','Immediate adverse events',['None observed','Bleeding','Perforation','Cardiorespiratory event','Aspiration','Other'],example='None observed',multi=True,note=True),
        field('tolerance','Tolerance',['Good','Fair','Poor','Not assessed'],example='Good'),
        field('conclusion','Conclusion / impression',example='No focal abnormality described in this fictional demonstration.'),
        field('followup','Plan and pathology follow-up',example='Individual advice and follow-up to be completed by the endoscopist.'),
    ])]
    # Specimens may also be taken from otherwise normal mucosa.
    roots.insert(-1,group('sampling','Sampling',[
        field('samples','Samples taken?',['Yes','No'],example='No'),
        repeat('specimens','specimen',[
          group('specimen_type','Specimen',[
            field('specimen_label','Container / label'),field('specimen_region','Region',['Oesophagus','Stomach','Duodenum','Other'],note=True),
            field('specimen_site','Precise site / linked finding'),field('specimen_number','Number of samples',unit='count'),
            field('specimen_protocol','Sampling protocol',['Targeted','Seattle','Gastric mapping','EoE','Coeliac','Other'],note=True)])
        ],parent='samples',equals='Yes',label='Add specimen')]))
    roots[0]['children'][-1]['showInPdf'] = False
    # Only fields in the routine form need fixture values; blueprints are blank.
    routine={}
    def walk(nodes):
        for n in nodes:
            if n.get('repeatableTemplates'):continue
            children=n['children']
            if not children: routine[n['id']]=VALUES.get(n['id'],'')
            else:
                if n['options']:routine[n['id']]=VALUES.get(n['id'],'')
                walk(children)
    walk(roots)
    return roots,routine

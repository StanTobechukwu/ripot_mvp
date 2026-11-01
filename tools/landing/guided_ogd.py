"""Guided OGD: conditional entry and concise, observation-only report output.
No automatic diagnosis, treatment advice, Registry or research fields.
"""
VALUES = {}


def field(key, title, options=None, unit='', example='', multi=False, parent='', equals='',
          children=None, note=False, report='', role=''):
    VALUES[key] = example
    return dict(type='section', id=key, title=title, collapsed=False,
        style=dict(level='h4', bold=True, align='left'),
        inputType=('multiSelect' if multi else 'singleSelect') if options else 'numeric' if unit else 'freeText',
        options=options or [], unit='' if unit == 'count' else unit,
        showInPdf=True, omitWhenEmpty=True, reportLabel=report, reportRole=role,
        addToRecords=False, addToLog=False, allowOptionalNote=note,
        conditionalParentSectionId=parent, conditionalEquals=equals,
        indent=0, children=children or [])


def group(key, title, children, role=''):
    n = field(key, title, children=children, role=role)
    VALUES.pop(key, None)
    return n


def repeat(key, title, types, parent='', equals='', label='Add finding', role=''):
    n = group(key, title, [], role=role)
    n.update(repeatableTemplates=types, repeatableAddLabel=label,
             conditionalParentSectionId=parent, conditionalEquals=equals)
    return n


YES = ['Yes', 'No', 'Not assessed']
LOCATIONS = {
 'oesophagus': ['Upper oesophagus', 'Middle oesophagus', 'Lower oesophagus', 'Gastro-oesophageal junction', 'Multiple regions', 'Other'],
 'stomach': ['Cardia', 'Fundus', 'Body', 'Incisura', 'Antrum', 'Pylorus', 'Multiple regions', 'Other'],
 'duodenum': ['Bulb', 'Second part', 'Beyond second part', 'Multiple regions', 'Other']}
FORREST = ['Ia — spurting', 'Ib — oozing', 'IIa — non-bleeding visible vessel',
           'IIb — adherent clot', 'IIc — flat pigmented spot', 'III — clean base',
           'Not assessed', 'Not applicable']


def biopsy_fields(key, parent='', equals=''):
    return [
        field(key+'_number', 'Number of biopsies', unit='count', parent=parent, equals=equals, role='biopsy.count'),
        field(key+'_type', 'Sampling type', ['Targeted', 'Non-targeted / random', 'Both', 'Not recorded'],
              parent=parent, equals=equals, role='biopsy.type'),
        field(key+'_container', 'Container / label', parent=parent, equals=equals, role='biopsy.container'),
        field(key+'_note', 'Sampling note, if needed', parent=parent, equals=equals, report='Sampling note', role='biopsy.note')]


def finding(region, kind, title, extras=(), size=False, biopsy=True, diffuse=False):
    k = region+'_'+kind
    fields = [field(k+'_location', 'Location', LOCATIONS[region], multi=diffuse, note=True, role='finding.location')]
    if region == 'oesophagus' and kind in ('ulcer', 'stricture', 'lesion', 'other'):
        fields.append(field(k+'_level', 'Level', unit='cm from incisors'))
    if region == 'stomach':
        fields.append(field(k+'_surface', 'Surface / curvature, if relevant',
            ['Lesser curvature', 'Greater curvature', 'Anterior wall', 'Posterior wall', 'Circumferential', 'Other'],
            note=True, report='Surface / curvature'))
    if size:
        fields.append(field(k+'_size', 'Size', unit='mm'))
    fields.extend(extras)
    fields.append(field(k+'_description', 'Additional description, if needed', report='Description'))
    if biopsy:
        fields.append(field(k+'_biopsy', 'Biopsy taken?', YES, report='Biopsy', role='ogd.biopsy',
                            children=biopsy_fields(k+'_biopsy', k+'_biopsy', 'Yes')))
    fields.append(field(k+'_treated', 'Treatment performed?', YES, report='Treatment', children=[
        field(k+'_method', 'Treatment method', ['Clips', 'Thermal therapy', 'Injection', 'Band ligation', 'Dilatation', 'Polypectomy', 'EMR', 'ESD', 'Other'],
              multi=True, parent=k+'_treated', equals='Yes', note=True),
        field(k+'_treatment_detail', 'Device / agent, dose and treatment details', parent=k+'_treated', equals='Yes', report='Treatment details'),
        field(k+'_outcome', 'Immediate outcome', ['Completed', 'Partially completed', 'Unsuccessful', 'Not assessable'],
              parent=k+'_treated', equals='Yes', note=True)]))
    return group(k, title, fields, role='ogd.finding')


def f(region, kind, label, options=None, unit='', suffix=None, **kwargs):
    return field(region+'_'+kind+'_'+(suffix or label.lower().replace(' ', '_')), label, options, unit, **kwargs)


def ulcer(region):
    return finding(region, 'ulcer', 'Ulcer', [
        f(region, 'ulcer', 'Number at this location', unit='count', suffix='count'),
        f(region, 'ulcer', 'Shape', ['Round', 'Oval', 'Linear', 'Irregular', 'Other'], note=True),
        f(region, 'ulcer', 'Edge', ['Regular', 'Irregular', 'Raised', 'Undermined', 'Other'], multi=True, note=True),
        f(region, 'ulcer', 'Base appearance', ['Clean', 'Fibrinous / slough-covered', 'Other'], note=True),
        f(region, 'ulcer', 'Bleeding stigmata / Forrest category', FORREST, suffix='forrest', report='Forrest category')], size=True)


def lesion(region, kind, title):
    return finding(region, kind, title, [f(region, kind, 'Morphology',
        ['Pedunculated', 'Sessile', 'Flat', 'Elevated', 'Depressed', 'Ulcerated', 'Other'], suffix='morphology', note=True)], size=True)


def erosions(region, title='Erosions'):
    return finding(region, 'erosions', title, [
        f(region, 'erosions', 'Number', ['Single', 'Multiple', 'Not recorded'], suffix='number'),
        f(region, 'erosions', 'Distribution', ['Focal', 'Patchy', 'Diffuse', 'Other'], note=True),
        f(region, 'erosions', 'Appearance', ['Punctate', 'Linear', 'Irregular', 'Other'], multi=True, note=True),
        f(region, 'erosions', 'Bleeding', ['None seen', 'Oozing', 'Blood staining', 'Not assessed'], suffix='bleeding')], diffuse=True)


def types(region):
    if region == 'oesophagus':
        return [finding(region, 'reflux', 'Reflux oesophagitis', [f(region, 'reflux', 'Los Angeles grade', ['A', 'B', 'C', 'D', 'Not assessed'], suffix='la')], biopsy=False, diffuse=True),
        finding(region, 'barrett', 'Suspected / known Barrett’s', [f(region, 'barrett', 'Prague C', unit='cm', suffix='c'), f(region, 'barrett', 'Prague M', unit='cm', suffix='m'), f(region, 'barrett', 'Visible lesion?', YES, suffix='lesion'), f(region, 'barrett', 'Biopsy protocol', ['Targeted', 'Seattle', 'Other', 'Not performed'], suffix='protocol')]),
        finding(region, 'hernia', 'Hiatal hernia', [f(region, 'hernia', 'Axial length', unit='cm', suffix='length'), f(region, 'hernia', 'Hill grade', ['I', 'II', 'III', 'IV', 'Not assessed'], suffix='hill')], biopsy=False),
        finding(region, 'eoe', 'EoE features', [f(region, 'eoe', 'Oedema', ['Absent', 'Present', 'Not assessed'], suffix='oedema'), f(region, 'eoe', 'Rings', ['Absent', 'Mild', 'Moderate', 'Severe', 'Not assessed'], suffix='rings'), f(region, 'eoe', 'Exudates', ['Absent', 'Present', 'Not assessed'], suffix='exudates'), f(region, 'eoe', 'Furrows', ['Absent', 'Present', 'Not assessed'], suffix='furrows'), f(region, 'eoe', 'Stricture', YES, suffix='stricture')], diffuse=True),
        finding(region, 'varices', 'Oesophageal varices', [
            f(region, 'varices', 'Size', ['Small (<5 mm)', 'Large (≥5 mm)', 'Not assessed'], suffix='size_grade'),
            f(region, 'varices', 'Extent', ['Lower third', 'To middle third', 'To upper third', 'Other'], note=True),
            f(region, 'varices', 'Number of columns, if recorded', unit='count', suffix='columns', report='Columns'),
            f(region, 'varices', 'Red signs', ['None seen', 'Red wale marks', 'Cherry-red spots', 'Haematocystic spots', 'Other', 'Not assessed'], multi=True, note=True, suffix='red'),
            f(region, 'varices', 'Bleeding', ['None seen', 'Active spurting', 'Active oozing', 'White nipple sign', 'Adherent clot', 'Other recent stigmata', 'Not assessed'], suffix='bleeding', note=True)], biopsy=False),
        finding(region, 'stricture', 'Ring / web / stricture', [f(region, 'stricture', 'Type', ['Ring', 'Web', 'Stricture', 'Other'], suffix='type'), f(region, 'stricture', 'Length', unit='cm', suffix='length'), f(region, 'stricture', 'Minimum diameter', unit='mm', suffix='diameter')]),
        finding(region, 'candida', 'Suspected candidiasis', diffuse=True), ulcer(region), lesion(region, 'lesion', 'Mass / lesion'), finding(region, 'other', 'Other finding')]
    if region == 'stomach':
        return [ulcer(region), finding(region, 'gastritis', 'Gastritis / erythema', [
            f(region, 'gastritis', 'Appearance', ['Erythema', 'Oedema', 'Nodularity', 'Friability', 'Other'], multi=True, note=True),
            f(region, 'gastritis', 'Distribution', ['Focal', 'Patchy', 'Diffuse', 'Other'], note=True)], diffuse=True), erosions(region),
        lesion(region, 'polyp', 'Polyp'), lesion(region, 'lesion', 'Mass / lesion'),
        finding(region, 'atrophy', 'Suspected atrophy / intestinal metaplasia', [f(region, 'atrophy', 'Appearance', ['Atrophy', 'Intestinal metaplasia suspected', 'Both', 'Uncertain'], suffix='appearance')], diffuse=True),
        finding(region, 'varices', 'Gastric varices', [f(region, 'varices', 'Sarin type', ['GOV1', 'GOV2', 'IGV1', 'IGV2', 'Not classified'], suffix='sarin'),
            f(region, 'varices', 'Largest diameter, if measured', unit='mm', suffix='diameter', report='Largest diameter'),
            f(region, 'varices', 'Bleeding', ['None seen', 'Active', 'Recent stigmata', 'Not assessed'], suffix='bleeding', note=True)], biopsy=False),
        finding(region, 'phg', 'Portal hypertensive gastropathy', [f(region, 'phg', 'Severity', ['Mild', 'Severe', 'Not graded'], suffix='severity')], biopsy=False, diffuse=True),
        finding(region, 'gave', 'GAVE', biopsy=False, diffuse=True), finding(region, 'retained', 'Retained food / fluid', biopsy=False, diffuse=True), finding(region, 'surgery', 'Post-surgical anatomy', biopsy=False), finding(region, 'other', 'Other finding')]
    return [ulcer(region), erosions(region, 'Erosions / duodenitis'), finding(region, 'villous', 'Suspected villous atrophy', [f(region, 'villous', 'Appearance', ['Scalloping', 'Reduced folds', 'Mosaic pattern', 'Other'], suffix='appearance')], diffuse=True), lesion(region, 'polyp', 'Polyp'), lesion(region, 'lesion', 'Mass / ampullary lesion'), finding(region, 'stenosis', 'Stenosis', size=True), finding(region, 'diverticulum', 'Diverticulum', biopsy=False), finding(region, 'other', 'Other finding')]


def build():
    VALUES.clear()
    preparation = group('preparation', 'Preparation and safety', [
        field('consent', 'Consent', ['Obtained', 'Not obtained', 'Emergency exception documented', 'Documented elsewhere'], example='Obtained', note=True),
        field('fasting', 'Fasting status', ['Confirmed', 'Not fasted', 'Uncertain', 'Documented elsewhere'], example='Confirmed', note=True),
        field('antithrombotics', 'Anticoagulant / antiplatelet medication', ['None reported', 'Anticoagulant', 'Antiplatelet', 'Both', 'Unknown'], example='None reported', note=True),
        field('safety', 'Pre-procedure safety assessment', ['Completed', 'Concern identified', 'Documented elsewhere', 'Not recorded'], example='Completed', note=True),
    ], role='ogd.preparation')
    details = group('extra_details', 'Additional procedure details', [preparation,
        field('scope', 'Endoscope used'), field('asa', 'ASA class', ['I', 'II', 'III', 'IV', 'V', 'VI', 'Not assessed'])], role='ogd.details')
    details['collapsed'] = True
    medication = group('medication_entry', 'Medication', [
        field('medication_name', 'Drug', role='medication.name'),
        field('medication_dose', 'Dose', unit='count', role='medication.dose'),
        field('medication_unit', 'Dose unit', ['mg', 'micrograms', 'g', 'mL', 'units', 'sprays', 'Other'], note=True, role='medication.unit'),
        field('medication_route', 'Route', ['IV', 'Oral', 'Topical', 'IM', 'Other'], note=True, role='medication.route')], role='ogd.medication')
    roots = [group('procedure', 'Procedure', [
        field('indication', 'Indication', ['Dyspepsia', 'Reflux', 'Dysphagia', 'Upper GI bleeding', 'Anaemia', 'Weight loss', 'Barrett’s surveillance', 'Variceal assessment', 'EoE assessment', 'Ulcer follow-up', 'Other'], example='Dyspepsia', multi=True, note=True),
        field('sedation', 'Sedation / anaesthesia', ['None', 'Topical anaesthesia only', 'Moderate sedation', 'Deep sedation', 'General anaesthesia'], example='None', note=True),
        repeat('medications', 'Medications administered', [medication], label='Add medication', role='ogd.medications'), details,
    ]), group('extent_view', 'Extent and view', [
        field('extent', 'Extent reached', ['Oesophagus', 'Stomach', 'Duodenal bulb', 'Second part of duodenum', 'Beyond second part', 'Other'], example='Second part of duodenum', note=True),
        field('view', 'Quality of view', ['Adequate', 'Limited', 'Cannot assess'], example='Adequate', note=True),
        field('limitations', 'Limitations / reason for incomplete examination, if applicable', report='Examination limitations'),
        field('duration', 'Examination duration, if recorded', unit='min', example='8', report='Examination duration'),
    ])]
    for region in LOCATIONS:
        fields = [field(region+'_status', region.title()+' assessment', ['Normal', 'Abnormal', 'Not examined', 'Cannot assess'], example='Normal', note=True, role='ogd.assessment')]
        if region == 'oesophagus':
            landmarks = field('oesophagus_landmarks', 'Record landmark measurements?', ['Yes', 'No'], example='No', children=[
                field('landmark_gej', 'GEJ (top of gastric folds)', unit='cm from incisors', parent='oesophagus_landmarks', equals='Yes'),
                field('landmark_z_line', 'Z-line', unit='cm from incisors', parent='oesophagus_landmarks', equals='Yes'),
                field('landmark_pinch', 'Diaphragmatic pinch', unit='cm from incisors', parent='oesophagus_landmarks', equals='Yes')])
            landmarks['showInPdf'] = False
            fields.append(landmarks)
        fields.append(repeat(region+'_findings', region+' finding', types(region), parent=region+'_status', equals='Abnormal', role='ogd.findings'))
        roots.append(group(region+'_region', region.title(), fields, role='ogd.region'))
    roots.append(group('sampling', 'Sampling', [
        repeat('specimens', 'Biopsy site', [group('specimen_entry', 'Biopsy site', [
            field('specimen_region', 'Region', ['Oesophagus', 'Stomach', 'Duodenum', 'Other'], note=True, role='biopsy.region'),
            field('specimen_site', 'Site', ['Upper oesophagus', 'Middle oesophagus', 'Lower oesophagus', 'Gastro-oesophageal junction', 'Cardia', 'Fundus', 'Body', 'Incisura', 'Antrum', 'Pylorus', 'Duodenal bulb', 'Second part of duodenum', 'Other'], note=True, role='biopsy.site'),
            *biopsy_fields('specimen')], role='ogd.specimen')], label='Add biopsy site', role='ogd.specimens')
    ], role='ogd.sampling'))
    roots.append(group('closing', 'Conclusion and follow-up', [
        field('events', 'Immediate adverse events', ['None observed', 'Bleeding', 'Perforation', 'Cardiorespiratory event', 'Aspiration', 'Other'], example='None observed', multi=True, note=True),
        field('tolerance', 'Tolerance', ['Good', 'Fair', 'Poor', 'Not assessed'], example='Good'),
        field('conclusion', 'Conclusion / impression', example='No focal abnormality described in this fictional demonstration.'),
        field('followup', 'Plan and pathology follow-up', example='Individual advice and follow-up to be completed by the endoscopist.'),
    ]))
    routine = {}
    def walk(nodes):
        for n in nodes:
            if n.get('repeatableTemplates'):
                continue
            children = n['children']
            if not children:
                routine[n['id']] = VALUES.get(n['id'], '')
            else:
                if n['options']:
                    routine[n['id']] = VALUES.get(n['id'], '')
                walk(children)
    walk(roots)
    return roots, routine

"""Brief documentation help, not diagnosis or treatment advice. Reviewed 2026-10-25."""
GUIDES = {
'colonoscopy-report-template': [
 ('Preparation and extent', 'Record the preparation scale used and the observed segment scores, not just an overall adjective. The Boston Bowel Preparation Scale describes how well the cleaned mucosa can be seen. Keep the segment findings with the total when using it. Document the furthest extent reached and the landmarks actually identified.'),
 ('Lesions and interventions', 'For each polyp, record its site, measured size and morphology, then describe the intervention, retrieval and specimen label. Keep separate lesions distinguishable so that subsequent histology can be matched to the endoscopic record.'),
 ('Impression', 'Summarise the principal findings and examination limitations. Record the clinician’s follow-up plan separately and identify any decision awaiting histology. Do not copy a fictional example as a normal report.')],
'upper-gi-endoscopy-report-template': [
 ('Before the findings', 'Use indication and sedation fields to document the reason for the examination and what was actually administered. Record relevant limitations rather than implying that every anatomical area was adequately examined.'),
 ('Anatomy and sampling', 'Describe the oesophagus, stomach and duodenum by the areas examined. Keep a lesion’s location and description together. For biopsies, distinguish sampling sites and specimen labels so that results can be reconciled with the report.'),
 ('Conclusion', 'Use the impression for the endoscopic summary. Keep histological diagnoses and pending results distinct from the visual findings. Enter the individual follow-up plan in the recommendation field.')],
'flexible-sigmoidoscopy-report-template': [
 ('Extent and visibility', 'Record the preparation, visibility, furthest landmark or distance reached, and any reason for stopping. This structure describes the examined lower bowel; it should not imply that the unexamined proximal colon was assessed.'),
 ('Findings and specimens', 'Use separate entries for lesions, their size and morphology, interventions and labelled specimens. Link the impression to the observed findings and mention any limitation that affects interpretation.')],
'abdominal-ultrasound-report-template': [
 ('Technique and organ findings', 'Describe the examination performed, relevant comparisons and limitations. Complete organ sections from the acquired examination; identify structures not visualised instead of leaving a reader to assume they were normal.'),
 ('Measurements and impression', 'Check the displayed units before entering dimensions. Keep a focal finding’s location, size and appearance together. Summarise the principal observations and limitations in the impression, with clinician-authored recommendations where appropriate.')],
'obstetric-ultrasound-report-template': [
 ('Dating and biometry', 'Record the established gestational age and dating basis. BPD, HC, AC and FL refer to biparietal diameter, head circumference, abdominal circumference and femur length. Keep units, the growth reference and any estimated-weight formula explicit; Ripot does not calculate or validate dating or centiles.'),
 ('Anatomy and incomplete views', 'Record the anatomy actually assessed, placenta and fluid observations. Identify incomplete views and technical limitations. A morphology examination cannot exclude every anomaly. For multiple fetuses, keep measurements and observations consistently associated with each fetus.')],
'pelvic-transvaginal-ultrasound-report-template': [
 ('Context and technique', 'Document the relevant menstrual or menopausal context and whether the examination was transabdominal, transvaginal or both. Record the applicable consent, chaperone and image-quality details.'),
 ('Measurements and findings', 'Use the uterine, endometrial, ovarian and adnexal fields to describe the examination. Keep dimensions and units explicit, and record non-visualisation or other limitations. The impression should reflect the actual findings and context rather than treating an isolated measurement as a diagnosis.')],
 'thyroid-neck-ultrasound-report-template': [
 ('Gland and nodule records', 'Document gland dimensions and background appearance. Give each nodule a stable identifier, location and dimensions. The nodule fields separate composition, echogenicity, shape, margins and echogenic foci so the observations remain reviewable.'),
 ('Classification and conclusion', 'If assigning a TI-RADS category, name the system used and verify the classification against that system. This template does not calculate a score or recommend biopsy. Record relevant lymph-node findings, comparison and the clinician’s conclusion separately.')],
'renal-artery-doppler-report-template': [
 ('Technique and sampling', 'Describe the renal examination and vessels sampled, with technical limitations. Keep right and left renal measurements separate. For Doppler, document the sampled sites, velocity units and relevant angle-correction information.'),
 ('Interpretation', 'PSV and EDV denote peak systolic and end-diastolic velocity. Record renal-aortic ratios and intrarenal resistive indices only from reviewed measurements, using the appropriate laboratory method. Ripot does not calculate these values or diagnose stenosis; explain incomplete assessment in the conclusion.')],
'holter-monitor-report-template': [
 ('Recording quality', 'Record the device, recording period and analysable duration. Describe artefact and excluded intervals so the reader understands the usable recording time.'),
 ('Rhythm and symptoms', 'Separate the predominant rhythm, heart-rate summary, ectopic events and conduction findings. Relate diary events to their times and reviewed rhythm strips. Automated detections require clinician verification; a symptom without a matching event should not silently become a rhythm diagnosis.')],
'ambulatory-blood-pressure-report-template': [
 ('Recording context', 'Record the device, cuff, arm, recording period and relevant medication timing. Identify awake and asleep periods from the method used, such as the patient’s diary.'),
 ('Summary and interpretation', 'Keep attempted and valid readings distinct. Enter the 24-hour, awake and asleep means with their units, followed by recording limitations. Document the method for any nocturnal change and the reference used for interpretation. Ripot does not calculate blood-pressure averages, dipping or diagnostic categories.')],
'general-surgical-operation-note-template': [
 ('Procedure record', 'Complete the procedure, date and time, team and diagnoses, then document the access, operative findings and work actually performed. Distinguish additional procedures from the original plan.'),
 ('Completion and handover', 'Record relevant specimens, implants, closure, estimated blood loss and complications. Keep the postoperative instructions specific to the patient and identify the responsible team. A reusable structure does not supply postoperative orders.')],
'caesarean-section-operation-note-template': [
 ('Maternal and operative record', 'Use the procedure and delivery sections to describe the indication, urgency, incisions, findings and delivery details from the actual operation. Keep the maternal record distinguishable from the newborn information.'),
 ('Newborn and completion', 'Record newborn identification, birth details and Apgar observations from the responsible clinical record. Add placental findings, closure, blood loss and complications as applicable, then document the individual postoperative handover. The template does not prescribe medicines or management.')],
'appendectomy-operation-note-template': [
 ('Findings and procedure', 'Describe the approach, appendix, base and surrounding findings. Record the method used for the mesoappendix and stump, specimen retrieval, and any additional procedure or conversion with its reason.'),
 ('Completion', 'Complete closure, blood loss, specimens, complications and handover from the actual case. Fields such as suction or irrigation are prompts to document what occurred, not instructions to perform a particular technique.')],
'wound-debridement-minor-operation-note-template': [
 ('Before and after', 'Record the site, side, initial wound dimensions and tissue findings. Document the debridement method, extent and deepest tissue removed, with the post-procedure dimensions kept separate from the initial assessment.'),
 ('Completion and plan', 'Describe haemostasis, closure or dressing and specimens as applicable. Record complications and the clinician’s individual wound-care and follow-up instructions. Blank antibiotic or tetanus fields require clinical assessment; the template does not generate treatment advice.')],
}
BASE_REFERENCES = {
'colonoscopy-report-template': [('ASGE / ACG: colonoscopy quality indicators', 'https://www.asge.org/docs/default-source/default-document-library/asge-acg-qi-for-colonoscopy-faq_oct24.pdf'), ('US Multi-Society Task Force: documenting colorectal lesions', 'https://www.asge.org/docs/default-source/guidelines/endoscopic-removal-of-colorectal-lesions-recommendations-by-the-us-multi-society-task-force-on-colorectal-cancer-2020-march-gie.pdf')],
'upper-gi-endoscopy-report-template': [('ESGE: standardised upper GI endoscopy reporting', 'https://www.esge.com/assets/downloads/pdfs/guidelines/2025_a-2652-8941.pdf')],
'abdominal-ultrasound-report-template': [('AIUM: ultrasound practice parameters', 'https://www.aium.org/resources/practice-parameters')],
'echocardiogram-report-template': [('ASE: adult echocardiography report standardisation', 'https://www.asecho.org/wp-content/uploads/2025/09/PIIS0894731725002925.pdf')],
}
GUIDES['echocardiogram-report-template'] = [
 ('Measurements and method', 'Document the study context, image quality and relevant comparison. Enter chamber measurements, systolic function and Doppler observations with the displayed units. State the method for measurements such as ejection fraction so that subsequent comparisons are meaningful.'),
 ('Integrated impression', 'Use the valve, ventricular and pericardial findings to support a concise clinician-authored summary. Document technical limitations and incomplete measurements. This structure does not calculate function or grade disease from an isolated number.')]

GUIDES['structured-upper-gi-endoscopy-report-template'] = [
 ('Choose the detail you need', 'Selecting a finding reveals its related prompts. Unselected findings are not assumed normal. Record examination extent and limitations, and review the rendered report before signing.'),
 ('Link samples to findings', 'Identify each sample by site and container. Document any intervention and immediate outcome, and state who will review pathology results. The 2025 ESGE STAR project informed this documentation structure; this is not an independently validated clinical protocol.'),
]
GUIDES['histopathology-report-template'] = [
 ('Identify specimens consistently', 'Use the accession number and container identifiers to connect the request, gross description, blocks and microscopic findings. Apply your laboratory identification and sign-out procedures.'),
 ('Write a clear conclusion', 'The conclusion is a separate field for the pathologist’s final diagnosis. This general structure does not replace tumour-specific datasets, staging protocols or a cytology reporting system. Use a separate cytology structure when reporting cell samples such as cervical smears.'),
]

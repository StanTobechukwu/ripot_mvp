import '../domain/models/nodes.dart';
import '../domain/models/report_doc.dart';
import '../domain/models/template_doc.dart';

class BuiltInTemplates {
  BuiltInTemplates._();

  static const upperGiId = 'ripot_starter_upper_gi_endoscopy';
  static const lowerGiId = 'ripot_starter_lower_gi_endoscopy';
  static const ultrasoundId = 'ripot_starter_abdominopelvic_ultrasound';

  static List<TemplateDoc> all() {
    return [
      upperGiEndoscopy(),
      lowerGiEndoscopy(),
      abdominopelvicUltrasound(),
    ];
  }

  static TemplateDoc upperGiEndoscopy() {
    return TemplateDoc(
      templateId: upperGiId,
      updatedAt: DateTime(2026, 8, 25),
      name: 'Upper GI Endoscopy',
      signature: const SignatureBlock(
        roleTitle: 'Endoscopist',
        assistantLabel: 'Assistant',
      ),
      roots: const [
        SectionNode(
          id: 'ugi_indication',
          title: 'Indication',
          inputType: FieldInputType.freeText,
          addToRecords: true,
        ),
        SectionNode(
          id: 'ugi_premedication',
          title: 'Premedication / Sedation',
          inputType: FieldInputType.freeText,
        ),
        SectionNode(
          id: 'ugi_findings',
          title: 'Findings',
          children: [
            SectionNode(
              id: 'ugi_oesophagus',
              title: 'Oesophagus',
              inputType: FieldInputType.freeText,
              children: [
                SectionNode(
                  id: 'ugi_oesophagus_upper',
                  title: 'Upper oesophagus',
                  inputType: FieldInputType.freeText,
                ),
                SectionNode(
                  id: 'ugi_oesophagus_middle',
                  title: 'Middle oesophagus',
                  inputType: FieldInputType.freeText,
                ),
                SectionNode(
                  id: 'ugi_oesophagus_lower',
                  title: 'Lower oesophagus',
                  inputType: FieldInputType.freeText,
                ),
                SectionNode(
                  id: 'ugi_ge_junction',
                  title: 'Gastro-oesophageal junction',
                  inputType: FieldInputType.freeText,
                ),
              ],
            ),
            SectionNode(
              id: 'ugi_stomach',
              title: 'Stomach',
              children: [
                SectionNode(
                  id: 'ugi_cardia',
                  title: 'Cardia',
                  inputType: FieldInputType.freeText,
                ),
                SectionNode(
                  id: 'ugi_fundus',
                  title: 'Fundus',
                  inputType: FieldInputType.freeText,
                ),
                SectionNode(
                  id: 'ugi_body',
                  title: 'Body',
                  inputType: FieldInputType.freeText,
                ),
                SectionNode(
                  id: 'ugi_antrum',
                  title: 'Antrum',
                  inputType: FieldInputType.freeText,
                ),
                SectionNode(
                  id: 'ugi_pylorus',
                  title: 'Pylorus',
                  inputType: FieldInputType.freeText,
                ),
              ],
            ),
            SectionNode(
              id: 'ugi_duodenum',
              title: 'Duodenum',
              children: [
                SectionNode(
                  id: 'ugi_duodenal_bulb',
                  title: 'Bulb',
                  inputType: FieldInputType.freeText,
                ),
                SectionNode(
                  id: 'ugi_duodenum_d2',
                  title: 'Second part',
                  inputType: FieldInputType.freeText,
                ),
              ],
            ),
          ],
        ),
        SectionNode(
          id: 'ugi_biopsy',
          title: 'Biopsy taken',
          inputType: FieldInputType.yesNo,
          addToRecords: true,
        ),
        SectionNode(
          id: 'ugi_biopsy_site',
          title: 'Biopsy site',
          inputType: FieldInputType.multiSelect,
          options: [
            'Oesophagus',
            'Cardia',
            'Fundus',
            'Body',
            'Antrum',
            'Pylorus',
            'Duodenal bulb',
            'Second part of duodenum',
            'Other',
          ],
          addToRecords: true,
          conditionalParentSectionId: 'ugi_biopsy',
          conditionalEquals: 'Yes',
        ),
        SectionNode(
          id: 'ugi_biopsy_number',
          title: 'Number of biopsies',
          inputType: FieldInputType.freeText,
          addToRecords: true,
          conditionalParentSectionId: 'ugi_biopsy',
          conditionalEquals: 'Yes',
        ),
        SectionNode(
          id: 'ugi_impression',
          title: 'Assessment / Impression',
          inputType: FieldInputType.freeText,
          addToRecords: true,
        ),
        SectionNode(
          id: 'ugi_recommendation',
          title: 'Recommendation',
          inputType: FieldInputType.freeText,
        ),
      ],
    );
  }

  static TemplateDoc lowerGiEndoscopy() {
    return TemplateDoc(
      templateId: lowerGiId,
      updatedAt: DateTime(2026, 8, 25),
      name: 'Lower GI Endoscopy',
      signature: const SignatureBlock(
        roleTitle: 'Endoscopist',
        assistantLabel: 'Assistant',
      ),
      roots: const [
        SectionNode(
          id: 'lgi_indication',
          title: 'Indication',
          inputType: FieldInputType.freeText,
          addToRecords: true,
        ),
        SectionNode(
          id: 'lgi_sedation',
          title: 'Premedication / Sedation',
          inputType: FieldInputType.freeText,
        ),
        SectionNode(
          id: 'lgi_bowel_prep',
          title: 'Bowel preparation',
          inputType: FieldInputType.singleSelect,
          options: [
            'Excellent',
            'Good',
            'Fair',
            'Poor',
          ],
          addToRecords: true,
        ),
        SectionNode(
          id: 'lgi_extent',
          title: 'Extent of examination',
          inputType: FieldInputType.singleSelect,
          options: [
            'Terminal ileum',
            'Caecum',
            'Ascending colon',
            'Transverse colon',
            'Descending colon',
            'Sigmoid colon',
            'Rectum',
          ],
          addToRecords: true,
        ),
        SectionNode(
          id: 'lgi_findings',
          title: 'Findings',
          children: [
            SectionNode(
              id: 'lgi_perianal',
              title: 'Perianal region',
              inputType: FieldInputType.freeText,
            ),
            SectionNode(
              id: 'lgi_rectum',
              title: 'Rectum',
              inputType: FieldInputType.freeText,
            ),
            SectionNode(
              id: 'lgi_sigmoid',
              title: 'Sigmoid colon',
              inputType: FieldInputType.freeText,
            ),
            SectionNode(
              id: 'lgi_descending',
              title: 'Descending colon',
              inputType: FieldInputType.freeText,
            ),
            SectionNode(
              id: 'lgi_transverse',
              title: 'Transverse colon',
              inputType: FieldInputType.freeText,
            ),
            SectionNode(
              id: 'lgi_ascending',
              title: 'Ascending colon',
              inputType: FieldInputType.freeText,
            ),
            SectionNode(
              id: 'lgi_caecum',
              title: 'Caecum',
              inputType: FieldInputType.freeText,
            ),
            SectionNode(
              id: 'lgi_terminal_ileum',
              title: 'Terminal ileum',
              inputType: FieldInputType.freeText,
            ),
          ],
        ),
        SectionNode(
          id: 'lgi_polyp',
          title: 'Polyp identified',
          inputType: FieldInputType.yesNo,
          addToRecords: true,
        ),
        SectionNode(
          id: 'lgi_polyp_site',
          title: 'Polyp site',
          inputType: FieldInputType.multiSelect,
          options: [
            'Rectum',
            'Sigmoid colon',
            'Descending colon',
            'Transverse colon',
            'Ascending colon',
            'Caecum',
            'Terminal ileum',
            'Multiple sites',
          ],
          addToRecords: true,
          conditionalParentSectionId: 'lgi_polyp',
          conditionalEquals: 'Yes',
        ),
        SectionNode(
          id: 'lgi_polyp_number',
          title: 'Number of polyps',
          inputType: FieldInputType.freeText,
          addToRecords: true,
          conditionalParentSectionId: 'lgi_polyp',
          conditionalEquals: 'Yes',
        ),
        SectionNode(
          id: 'lgi_polyp_size',
          title: 'Largest polyp size',
          inputType: FieldInputType.freeText,
          addToRecords: true,
          conditionalParentSectionId: 'lgi_polyp',
          conditionalEquals: 'Yes',
        ),
        SectionNode(
          id: 'lgi_polyp_morphology',
          title: 'Polyp morphology',
          inputType: FieldInputType.singleSelect,
          options: [
            'Pedunculated',
            'Sessile',
            'Flat',
            'Other',
          ],
          addToRecords: true,
          conditionalParentSectionId: 'lgi_polyp',
          conditionalEquals: 'Yes',
        ),
        SectionNode(
          id: 'lgi_polypectomy',
          title: 'Polypectomy performed',
          inputType: FieldInputType.yesNo,
          addToRecords: true,
          conditionalParentSectionId: 'lgi_polyp',
          conditionalEquals: 'Yes',
        ),
        SectionNode(
          id: 'lgi_biopsy',
          title: 'Biopsy taken',
          inputType: FieldInputType.yesNo,
          addToRecords: true,
        ),
        SectionNode(
          id: 'lgi_biopsy_site',
          title: 'Biopsy site',
          inputType: FieldInputType.multiSelect,
          options: [
            'Rectum',
            'Sigmoid colon',
            'Descending colon',
            'Transverse colon',
            'Ascending colon',
            'Caecum',
            'Terminal ileum',
            'Other',
          ],
          addToRecords: true,
          conditionalParentSectionId: 'lgi_biopsy',
          conditionalEquals: 'Yes',
        ),
        SectionNode(
          id: 'lgi_intervention',
          title: 'Other intervention',
          inputType: FieldInputType.freeText,
        ),
        SectionNode(
          id: 'lgi_impression',
          title: 'Assessment / Impression',
          inputType: FieldInputType.freeText,
          addToRecords: true,
        ),
        SectionNode(
          id: 'lgi_recommendation',
          title: 'Recommendation',
          inputType: FieldInputType.freeText,
        ),
      ],
    );
  }

  static TemplateDoc abdominopelvicUltrasound() {
    return TemplateDoc(
      templateId: ultrasoundId,
      updatedAt: DateTime(2026, 8, 25),
      name: 'Abdominopelvic Ultrasound',
      signature: const SignatureBlock(
        roleTitle: 'Sonologist / Radiologist',
        assistantLabel: 'Assistant',
      ),
      roots: const [
        SectionNode(
          id: 'us_indication',
          title: 'Clinical indication',
          inputType: FieldInputType.freeText,
          addToRecords: true,
        ),
        SectionNode(
          id: 'us_liver',
          title: 'Liver',
          inputType: FieldInputType.freeText,
        ),
        SectionNode(
          id: 'us_gallbladder',
          title: 'Gallbladder',
          inputType: FieldInputType.freeText,
        ),
        SectionNode(
          id: 'us_biliary_tree',
          title: 'Biliary tree',
          inputType: FieldInputType.freeText,
        ),
        SectionNode(
          id: 'us_pancreas',
          title: 'Pancreas',
          inputType: FieldInputType.freeText,
        ),
        SectionNode(
          id: 'us_spleen',
          title: 'Spleen',
          inputType: FieldInputType.freeText,
        ),
        SectionNode(
          id: 'us_right_kidney',
          title: 'Right kidney',
          inputType: FieldInputType.freeText,
        ),
        SectionNode(
          id: 'us_left_kidney',
          title: 'Left kidney',
          inputType: FieldInputType.freeText,
        ),
        SectionNode(
          id: 'us_urinary_bladder',
          title: 'Urinary bladder',
          inputType: FieldInputType.freeText,
        ),
        SectionNode(
          id: 'us_uterus',
          title: 'Uterus',
          inputType: FieldInputType.freeText,
        ),
        SectionNode(
          id: 'us_endometrium',
          title: 'Endometrium',
          inputType: FieldInputType.freeText,
        ),
        SectionNode(
          id: 'us_right_adnexa',
          title: 'Right ovary / adnexa',
          inputType: FieldInputType.freeText,
        ),
        SectionNode(
          id: 'us_left_adnexa',
          title: 'Left ovary / adnexa',
          inputType: FieldInputType.freeText,
        ),
        SectionNode(
          id: 'us_prostate',
          title: 'Prostate',
          inputType: FieldInputType.freeText,
        ),
        SectionNode(
          id: 'us_other',
          title: 'Other findings / Peritoneum',
          inputType: FieldInputType.freeText,
        ),
        SectionNode(
          id: 'us_impression',
          title: 'Impression',
          inputType: FieldInputType.freeText,
          addToRecords: true,
        ),
        SectionNode(
          id: 'us_recommendation',
          title: 'Recommendation',
          inputType: FieldInputType.freeText,
        ),
      ],
    );
  }
}

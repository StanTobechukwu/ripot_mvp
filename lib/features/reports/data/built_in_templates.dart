import '../domain/models/nodes.dart';
import '../domain/models/report_doc.dart';
import '../domain/models/template_doc.dart';

class BuiltInTemplates {
  BuiltInTemplates._();

  static const upperGiId = 'ripot_starter_upper_gi_endoscopy';
  static const lowerGiId = 'ripot_starter_lower_gi_endoscopy';
  static const ultrasoundId = 'ripot_starter_abdominopelvic_ultrasound';
  static const echoId = 'ripot_starter_2d_echocardiography';

  static List<TemplateDoc> all() {
    return [
      upperGiEndoscopy(),
      lowerGiEndoscopy(),
      abdominopelvicUltrasound(),
      echocardiography2D(),
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


  static TemplateDoc echocardiography2D() {
    const numericStyle = TitleStyle(level: HeadingLevel.h4, bold: false);
    return TemplateDoc(
      templateId: echoId,
      updatedAt: DateTime(2026, 9, 5),
      name: '2D Echocardiography',
      signature: const SignatureBlock(
        roleTitle: 'Echocardiographer',
        assistantLabel: 'Assistant',
      ),
      roots: const [
        SectionNode(
          id: 'echo_lv', title: 'Left Ventricle', children: [
            SectionNode(id: 'echo_lv_chamber_size', title: 'Chamber Size', inputType: FieldInputType.numeric, unit: 'cm', addToRecords: true, style: numericStyle),
            SectionNode(id: 'echo_lv_edv', title: 'End Diastolic Volume', inputType: FieldInputType.numeric, unit: 'mL', addToRecords: true, style: numericStyle),
            SectionNode(id: 'echo_lvidd', title: 'LVIDd', inputType: FieldInputType.numeric, unit: 'cm', addToRecords: true, style: numericStyle),
            SectionNode(id: 'echo_ivsd', title: 'Septal Wall (IVSd)', inputType: FieldInputType.numeric, unit: 'cm', addToRecords: true, style: numericStyle),
            SectionNode(id: 'echo_pwdd', title: 'Posterior Wall (PWDd)', inputType: FieldInputType.numeric, unit: 'cm', addToRecords: true, style: numericStyle),
            SectionNode(id: 'echo_lv_global_motion', title: 'Global Systolic Wall Motion', inputType: FieldInputType.singleSelect, options: ['Normal', 'Hyperdynamic', 'Reduced'], addToRecords: true),
            SectionNode(id: 'echo_ef', title: 'Ejection Fraction (EF)', inputType: FieldInputType.numeric, unit: '%', addToRecords: true, style: numericStyle),
            SectionNode(id: 'echo_rwma', title: 'Regional Wall Motion Abnormality', inputType: FieldInputType.singleSelect, options: ['None', 'Present'], addToRecords: true, allowOptionalNote: true),
            SectionNode(id: 'echo_diastolic_function', title: 'Diastolic Function', inputType: FieldInputType.singleSelect, options: ['Normal', 'Grade I', 'Grade II', 'Grade III'], addToRecords: true),
            SectionNode(id: 'echo_e_a', title: 'E/A', inputType: FieldInputType.numeric, addToRecords: true, style: numericStyle),
            SectionNode(id: 'echo_e_eprime', title: 'E/E′', inputType: FieldInputType.numeric, addToRecords: true, style: numericStyle),
            SectionNode(id: 'echo_septal_eprime', title: 'Septal E′', inputType: FieldInputType.numeric, unit: 'm/s', addToRecords: true, style: numericStyle),
            SectionNode(id: 'echo_lateral_eprime', title: 'Lateral E′', inputType: FieldInputType.numeric, unit: 'm/s', addToRecords: true, style: numericStyle),
          ],
        ),
        SectionNode(
          id: 'echo_mitral', title: 'Mitral Valve', children: [
            SectionNode(id: 'echo_mv_morphology', title: 'Leaflet Morphology', inputType: FieldInputType.singleSelect, options: ['Normal', 'Thickened', 'Calcified', 'Prolapse', 'Other'], addToRecords: true, allowOptionalNote: true),
            SectionNode(id: 'echo_mr', title: 'Mitral Regurgitation', inputType: FieldInputType.singleSelect, options: ['None', 'Mild', 'Moderate', 'Severe'], addToRecords: true),
            SectionNode(id: 'echo_ms', title: 'Mitral Stenosis', inputType: FieldInputType.singleSelect, options: ['None', 'Mild', 'Moderate', 'Severe'], addToRecords: true),
            SectionNode(id: 'echo_mr_vmax', title: 'MR Vmax', inputType: FieldInputType.numeric, unit: 'm/s', addToRecords: true, style: numericStyle),
            SectionNode(id: 'echo_mv_subvalvular', title: 'Subvalvular Apparatus', inputType: FieldInputType.singleSelect, options: ['Normal', 'Abnormal'], addToRecords: true, allowOptionalNote: true),
          ],
        ),
        SectionNode(
          id: 'echo_la', title: 'Left Atrium', children: [
            SectionNode(id: 'echo_la_size', title: 'Cavity Size', inputType: FieldInputType.singleSelect, options: ['Normal', 'Mildly dilated', 'Moderately dilated', 'Severely dilated'], addToRecords: true),
            SectionNode(id: 'echo_la_diameter', title: 'LA Diameter', inputType: FieldInputType.numeric, unit: 'cm', addToRecords: true, style: numericStyle),
            SectionNode(id: 'echo_la_area', title: 'LA Area', inputType: FieldInputType.numeric, unit: 'cm²', addToRecords: true, style: numericStyle),
            SectionNode(id: 'echo_ias', title: 'Interatrial Septum', inputType: FieldInputType.singleSelect, options: ['Intact', 'Defect present'], addToRecords: true, allowOptionalNote: true),
            SectionNode(id: 'echo_la_clot_mass', title: 'Clot / Mass', inputType: FieldInputType.singleSelect, options: ['None', 'Present'], addToRecords: true, allowOptionalNote: true),
          ],
        ),
        SectionNode(
          id: 'echo_aorta_av', title: 'Aorta / Aortic Valve', children: [
            SectionNode(id: 'echo_aortic_root', title: 'Aortic Root Diameter', inputType: FieldInputType.numeric, unit: 'cm', addToRecords: true, style: numericStyle),
            SectionNode(id: 'echo_av_morphology', title: 'Valve Morphology', inputType: FieldInputType.singleSelect, options: ['Normal', 'Thickened', 'Calcified', 'Bicuspid', 'Other'], addToRecords: true, allowOptionalNote: true),
            SectionNode(id: 'echo_av_vmax', title: 'AV Vmax', inputType: FieldInputType.numeric, unit: 'm/s', addToRecords: true, style: numericStyle),
            SectionNode(id: 'echo_av_peak_gradient', title: 'Peak Gradient', inputType: FieldInputType.numeric, unit: 'mmHg', addToRecords: true, style: numericStyle),
          ],
        ),
        SectionNode(
          id: 'echo_rv', title: 'Right Ventricle', children: [
            SectionNode(id: 'echo_rv_dimension', title: 'Cavity Dimension', inputType: FieldInputType.numeric, unit: 'cm', addToRecords: true, style: numericStyle),
            SectionNode(id: 'echo_rv_basal', title: 'RV Basal Diameter', inputType: FieldInputType.numeric, unit: 'cm', addToRecords: true, style: numericStyle),
            SectionNode(id: 'echo_rv_function', title: 'Systolic Function', inputType: FieldInputType.singleSelect, options: ['Normal', 'Mildly reduced', 'Moderately reduced', 'Severely reduced'], addToRecords: true),
            SectionNode(id: 'echo_tapse', title: 'TAPSE', inputType: FieldInputType.numeric, unit: 'cm', addToRecords: true, style: numericStyle),
          ],
        ),
        SectionNode(
          id: 'echo_tricuspid', title: 'Tricuspid Valve', children: [
            SectionNode(id: 'echo_tv_appearance', title: 'Valve Appearance', inputType: FieldInputType.singleSelect, options: ['Normal', 'Abnormal'], addToRecords: true, allowOptionalNote: true),
            SectionNode(id: 'echo_tv_morphology', title: 'Leaflet Morphology', inputType: FieldInputType.singleSelect, options: ['Normal', 'Abnormal'], addToRecords: true, allowOptionalNote: true),
            SectionNode(id: 'echo_tr', title: 'Tricuspid Regurgitation', inputType: FieldInputType.singleSelect, options: ['None', 'Mild', 'Moderate', 'Severe'], addToRecords: true),
            SectionNode(id: 'echo_tr_vmax', title: 'TR Vmax', inputType: FieldInputType.numeric, unit: 'm/s', addToRecords: true, style: numericStyle),
          ],
        ),
        SectionNode(
          id: 'echo_ra', title: 'Right Atrium', children: [
            SectionNode(id: 'echo_ra_size', title: 'Cavity Size', inputType: FieldInputType.singleSelect, options: ['Normal', 'Mildly dilated', 'Moderately dilated', 'Severely dilated'], addToRecords: true),
            SectionNode(id: 'echo_ra_area', title: 'Area', inputType: FieldInputType.numeric, unit: 'cm²', addToRecords: true, style: numericStyle),
            SectionNode(id: 'echo_ra_clot_mass', title: 'Clot / Mass', inputType: FieldInputType.singleSelect, options: ['None', 'Present'], addToRecords: true, allowOptionalNote: true),
          ],
        ),
        SectionNode(
          id: 'echo_ivc', title: 'Inferior Vena Cava (IVC)', children: [
            SectionNode(id: 'echo_ivc_dimension', title: 'IVC Dimension', inputType: FieldInputType.numeric, unit: 'cm', addToRecords: true, style: numericStyle),
            SectionNode(id: 'echo_ivc_collapse', title: 'Inspiratory Collapse', inputType: FieldInputType.singleSelect, options: ['>50%', '≤50%'], addToRecords: true),
            SectionNode(id: 'echo_estimated_pap', title: 'Estimated PAP', inputType: FieldInputType.numeric, unit: 'mmHg', addToRecords: true, style: numericStyle),
          ],
        ),
        SectionNode(
          id: 'echo_pericardium', title: 'Pericardium', children: [
            SectionNode(id: 'echo_pericardial_appearance', title: 'Appearance', inputType: FieldInputType.singleSelect, options: ['Normal', 'Abnormal'], addToRecords: true, allowOptionalNote: true),
            SectionNode(id: 'echo_pericardial_effusion', title: 'Pericardial Effusion', inputType: FieldInputType.singleSelect, options: ['None', 'Small', 'Moderate', 'Large'], addToRecords: true, allowOptionalNote: true),
          ],
        ),
        SectionNode(id: 'echo_conclusion', title: 'Conclusion', inputType: FieldInputType.freeText),
      ],
    );
  }
}

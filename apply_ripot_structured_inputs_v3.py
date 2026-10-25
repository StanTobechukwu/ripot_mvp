#!/usr/bin/env python3
"""
Ripot structured-input global change-set.

Run from the root of the ripot_mvp repository while on:
  ripot-structured-inputs-image-flow

What it does:
- Preserves the current FieldInputType enum for backward compatibility.
- Makes Free text vs Structured explicit in the template editor UI.
- Disables Records for free-text fields at the model/provider layer.
- Adds independent "Show value in PDF" and "Save to Records" controls.
- Adds template-level "Allow optional note".
- Stores report-instance notes separately from structured values.
- Preserves showInPdf correctly through template serialization.
- Adds optional notes to the report editor and PDF output.
- Keeps existing saved templates/reports migration-safe.

It intentionally does NOT implement longitudinal Registry fields; that belongs to Ripot Registry.
"""

from pathlib import Path
import subprocess
import sys

ROOT = Path.cwd()

FILES = [
    "lib/features/reports/domain/models/nodes.dart",
    "lib/features/reports/domain/serialization/template_codec.dart",
    "lib/features/reports/domain/serialization/report_codec.dart",
    "lib/features/reports/providers/template_editor_provider.dart",
    "lib/features/reports/providers/report_editor_provider.dart",
    "lib/features/reports/ui/template_editor_screen.dart",
    "lib/features/reports/ui/report_editor_screen.dart",
    "lib/features/reports/services/pdf_renderer_service.dart",
]

def die(msg):
    print(f"\nERROR: {msg}\n", file=sys.stderr)
    sys.exit(1)

def replace_one(text, old, new, label):
    count = text.count(old)
    if count != 1:
        die(f"{label}: expected exactly 1 match, found {count}. No files were written.")
    return text.replace(old, new, 1)

def replace_at_least_one(text, old, new, label):
    count = text.count(old)
    if count < 1:
        die(f"{label}: expected at least 1 match, found 0. No files were written.")
    return text.replace(old, new)

def replace_first(text, old, new, label):
    count = text.count(old)
    if count < 1:
        die(f"{label}: expected at least 1 match, found 0. No files were written.")
    return text.replace(old, new, 1)

# Safety checks
for rel in FILES:
    if not (ROOT / rel).exists():
        die(f"Run this script from the ripot_mvp repository root. Missing: {rel}")

try:
    branch = subprocess.check_output(
        ["git", "branch", "--show-current"], text=True
    ).strip()
except Exception:
    branch = ""

if branch and branch != "ripot-structured-inputs-image-flow":
    die(
        f"Current branch is '{branch}'. Switch to "
        "'ripot-structured-inputs-image-flow' before applying this change-set."
    )

original = {rel: (ROOT / rel).read_text(encoding="utf-8") for rel in FILES}
updated = dict(original)

# ------------------------------------------------------------------
# 1. Domain model: SectionNode
# ------------------------------------------------------------------
p = "lib/features/reports/domain/models/nodes.dart"
t = updated[p]

t = replace_one(
    t,
    """  /// When true, this section's content is copied into Records when the report is saved.
  final bool addToRecords;

  /// Optional simple conditional display rule for this section.
""",
    """  /// When true, this section's structured value is copied into Records
  /// when the report is saved. Free-text fields must not use this.
  final bool addToRecords;

  /// Structured fields can optionally allow an additional narrative note.
  /// This is a template-level capability, not the note value itself.
  final bool allowOptionalNote;

  /// Report-instance narrative note attached to a structured field.
  /// This note is not structured Records data.
  final String note;

  /// Optional simple conditional display rule for this section.
""",
    "nodes.dart add note fields",
)

t = replace_one(
    t,
    """    this.showInPdf = true,
    this.addToRecords = false,
    this.conditionalParentSectionId = '',
""",
    """    this.showInPdf = true,
    this.addToRecords = false,
    this.allowOptionalNote = false,
    this.note = '',
    this.conditionalParentSectionId = '',
""",
    "nodes.dart constructor",
)

t = replace_one(
    t,
    """    bool? showInPdf,
    bool? addToRecords,
    String? conditionalParentSectionId,
""",
    """    bool? showInPdf,
    bool? addToRecords,
    bool? allowOptionalNote,
    String? note,
    String? conditionalParentSectionId,
""",
    "nodes.dart copyWith args",
)

t = replace_one(
    t,
    """      showInPdf: showInPdf ?? this.showInPdf,
      addToRecords: addToRecords ?? this.addToRecords,
      conditionalParentSectionId: conditionalParentSectionId ?? this.conditionalParentSectionId,
""",
    """      showInPdf: showInPdf ?? this.showInPdf,
      addToRecords: addToRecords ?? this.addToRecords,
      allowOptionalNote: allowOptionalNote ?? this.allowOptionalNote,
      note: note ?? this.note,
      conditionalParentSectionId: conditionalParentSectionId ?? this.conditionalParentSectionId,
""",
    "nodes.dart copyWith body",
)

# Template clone: preserve capability, drop report-instance note.
# This exact three-line sequence also appears in ReportClone, so intentionally
# patch only the first occurrence (TemplateClone appears first in nodes.dart).
t = replace_first(
    t,
    """      showInPdf: showInPdf,
      addToRecords: addToRecords,
      conditionalParentSectionId: conditionalParentSectionId,
""",
    """      showInPdf: showInPdf,
      addToRecords: addToRecords,
      allowOptionalNote: allowOptionalNote,
      note: '',
      conditionalParentSectionId: conditionalParentSectionId,
""",
    "nodes.dart template clone",
)

# Report clone: preserve both.
t = replace_one(
    t,
    """      showInPdf: showInPdf,
      addToRecords: addToRecords,
      conditionalParentSectionId: conditionalParentSectionId,
      conditionalEquals: conditionalEquals,
      indent: indent,
      children: children.map((n) {
""",
    """      showInPdf: showInPdf,
      addToRecords: addToRecords,
      allowOptionalNote: allowOptionalNote,
      note: note,
      conditionalParentSectionId: conditionalParentSectionId,
      conditionalEquals: conditionalEquals,
      indent: indent,
      children: children.map((n) {
""",
    "nodes.dart report clone",
)
updated[p] = t

# ------------------------------------------------------------------
# 2. Template codec: preserve showInPdf + allowOptionalNote
# ------------------------------------------------------------------
p = "lib/features/reports/domain/serialization/template_codec.dart"
t = updated[p]
t = replace_one(
    t,
    """        'showInPdf': true,
        'addToRecords': s.addToRecords,
""",
    """        'showInPdf': s.showInPdf,
        'addToRecords': s.addToRecords,
        'allowOptionalNote': s.allowOptionalNote,
""",
    "template_codec encode",
)
t = replace_one(
    t,
    """        showInPdf: true,
        addToRecords: (j['addToRecords'] as bool?) ?? false,
""",
    """        showInPdf: (j['showInPdf'] as bool?) ?? true,
        addToRecords: (j['addToRecords'] as bool?) ?? false,
        allowOptionalNote: (j['allowOptionalNote'] as bool?) ?? false,
        note: '',
""",
    "template_codec decode",
)
updated[p] = t

# ------------------------------------------------------------------
# 3. Report codec: persist note + capability
# ------------------------------------------------------------------
p = "lib/features/reports/domain/serialization/report_codec.dart"
t = updated[p]
t = replace_one(
    t,
    """        'showInPdf': s.showInPdf,
        'addToRecords': s.addToRecords,
        'conditionalParentSectionId': s.conditionalParentSectionId,
""",
    """        'showInPdf': s.showInPdf,
        'addToRecords': s.addToRecords,
        'allowOptionalNote': s.allowOptionalNote,
        'note': s.note,
        'conditionalParentSectionId': s.conditionalParentSectionId,
""",
    "report_codec encode",
)
t = replace_one(
    t,
    """        showInPdf: (j['showInPdf'] as bool?) ?? true,
        addToRecords: (j['addToRecords'] as bool?) ?? false,
        conditionalParentSectionId: (j['conditionalParentSectionId'] as String?) ?? '',
""",
    """        showInPdf: (j['showInPdf'] as bool?) ?? true,
        addToRecords: (j['addToRecords'] as bool?) ?? false,
        allowOptionalNote: (j['allowOptionalNote'] as bool?) ?? false,
        note: (j['note'] as String?) ?? '',
        conditionalParentSectionId: (j['conditionalParentSectionId'] as String?) ?? '',
""",
    "report_codec decode",
)
updated[p] = t

# ------------------------------------------------------------------
# 4. Template provider: stop forcing PDF visibility; enforce free-text rule
# ------------------------------------------------------------------
p = "lib/features/reports/providers/template_editor_provider.dart"
t = updated[p]

t = replace_one(
    t,
    """      roots: _template.roots
          .map((r) => _forcePdfVisible(r.toTemplateNode(includeContent: includeContent)))
          .toList(growable: false),
""",
    """      roots: _template.roots
          .map((r) => r.toTemplateNode(includeContent: includeContent))
          .toList(growable: false),
""",
    "template provider stop force PDF visible",
)

force_method = """  SectionNode _forcePdfVisible(SectionNode section) {
    return section.copyWith(
      showInPdf: true,
      children: section.children.map((child) {
        if (child is SectionNode) return _forcePdfVisible(child);
        return child;
      }).toList(growable: false),
    );
  }

"""
t = replace_one(t, force_method, "", "template provider remove _forcePdfVisible")

old_method = """  void updateSectionFieldSettings(
    String sectionId, {
    FieldInputType? inputType,
    List<String>? options,
    bool? showInPdf,
    bool? addToRecords,
    String? conditionalParentSectionId,
    String? conditionalEquals,
  }) {
    _template = _template.copyWith(
      roots: _updateTree(
        _template.roots,
        sectionId,
        (s) => s.copyWith(
          inputType: inputType,
          options: options,
          showInPdf: true,
          addToRecords: addToRecords,
          conditionalParentSectionId: conditionalParentSectionId,
          conditionalEquals: conditionalEquals,
        ),
      ),
      updatedAt: DateTime.now(),
    );
    _markDirty();
    notifyListeners();
  }
"""
new_method = """  void updateSectionFieldSettings(
    String sectionId, {
    FieldInputType? inputType,
    List<String>? options,
    bool? showInPdf,
    bool? addToRecords,
    bool? allowOptionalNote,
    String? conditionalParentSectionId,
    String? conditionalEquals,
  }) {
    _template = _template.copyWith(
      roots: _updateTree(
        _template.roots,
        sectionId,
        (s) {
          final nextInputType = inputType ?? s.inputType;
          final isStructured = nextInputType != FieldInputType.freeText;
          return s.copyWith(
            inputType: nextInputType,
            options: options,
            showInPdf: showInPdf ?? s.showInPdf,
            addToRecords: isStructured
                ? (addToRecords ?? s.addToRecords)
                : false,
            allowOptionalNote: isStructured
                ? (allowOptionalNote ?? s.allowOptionalNote)
                : false,
            note: isStructured ? s.note : '',
            conditionalParentSectionId: conditionalParentSectionId,
            conditionalEquals: conditionalEquals,
          );
        },
      ),
      updatedAt: DateTime.now(),
    );
    _markDirty();
    notifyListeners();
  }
"""
t = replace_one(t, old_method, new_method, "template provider field settings")
updated[p] = t

# ------------------------------------------------------------------
# 5. Report provider: separate note updater
# ------------------------------------------------------------------
p = "lib/features/reports/providers/report_editor_provider.dart"
t = updated[p]
anchor = """  void updateContent(String contentId, String text) {
    _doc = _doc.copyWith(
      roots: _updateContentTree(_doc.roots, contentId, text),
      updatedAtIso: nowIso(),
    );
    _markDirty();
  }

"""
addition = anchor + """  void updateSectionNote(String sectionId, String note) {
    _doc = _doc.copyWith(
      roots: _updateSectionTree(
        _doc.roots,
        sectionId,
        (s) => s.copyWith(note: note),
      ),
      updatedAtIso: nowIso(),
    );
    _markDirty();
  }

"""
t = replace_one(t, anchor, addition, "report provider update note")
updated[p] = t

# ------------------------------------------------------------------
# 6. Template editor UI: Free text vs Structured, outputs, optional note
# ------------------------------------------------------------------
p = "lib/features/reports/ui/template_editor_screen.dart"
t = updated[p]

t = replace_one(
    t,
    """            inputType: res.inputType,
            options: res.options,
            addToRecords: res.addToRecords,
            conditionalParentSectionId: res.conditionalParentSectionId,
""",
    """            inputType: res.inputType,
            options: res.options,
            showInPdf: res.showInPdf,
            addToRecords: res.addToRecords,
            allowOptionalNote: res.allowOptionalNote,
            conditionalParentSectionId: res.conditionalParentSectionId,
""",
    "template editor apply result",
)

t = replace_one(
    t,
    """  final bool? addToRecords;
  final String? conditionalParentSectionId;
""",
    """  final bool? showInPdf;
  final bool? addToRecords;
  final bool? allowOptionalNote;
  final String? conditionalParentSectionId;
""",
    "template editor result fields",
)

t = replace_one(
    t,
    """    this.options,
    this.addToRecords,
    this.conditionalParentSectionId,
""",
    """    this.options,
    this.showInPdf,
    this.addToRecords,
    this.allowOptionalNote,
    this.conditionalParentSectionId,
""",
    "template editor result ctor",
)

t = replace_one(
    t,
    """  late final TextEditingController _options;
  late bool _addToRecords;
  late bool _useCondition;
""",
    """  late final TextEditingController _options;
  late bool _showInPdf;
  late bool _addToRecords;
  late bool _allowOptionalNote;
  late bool _useCondition;
""",
    "template editor state fields",
)

t = replace_one(
    t,
    """    _options = TextEditingController(text: widget.section.options.join('\\n'));
    _addToRecords = widget.section.addToRecords;
    _useCondition = widget.section.hasCondition;
""",
    """    _options = TextEditingController(text: widget.section.options.join('\\n'));
    _showInPdf = widget.section.showInPdf;
    _addToRecords = widget.section.inputType == FieldInputType.freeText
        ? false
        : widget.section.addToRecords;
    _allowOptionalNote = widget.section.inputType == FieldInputType.freeText
        ? false
        : widget.section.allowOptionalNote;
    _useCondition = widget.section.hasCondition;
""",
    "template editor state init",
)

old_ui = """                DropdownButtonFormField<FieldInputType>(
                  initialValue: _inputType,
                  decoration: const InputDecoration(
                    labelText: 'Input type',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: FieldInputType.values
                      .map((type) => DropdownMenuItem(value: type, child: Text(type.label)))
                      .toList(),
                  onChanged: (v) => setState(() => _inputType = v ?? _inputType),
                ),
                if (_inputType != FieldInputType.freeText) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _options,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: _inputType == FieldInputType.yesNo ? 'Options' : 'Options / suggestions',
                      hintText: _inputType == FieldInputType.yesNo ? 'Yes and No are used automatically' : 'One option per line, or comma-separated',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    enabled: _inputType != FieldInputType.yesNo,
                  ),
                ],
                CheckboxListTile(
                  value: _addToRecords,
                  onChanged: (v) => setState(() => _addToRecords = v ?? false),
                  title: const Text('Save to Records'),
                  subtitle: const Text('Store this field as searchable/exportable data.'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
"""
new_ui = """                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: 'freeText',
                      label: Text('Free text'),
                      icon: Icon(Icons.notes_outlined, size: 18),
                    ),
                    ButtonSegment(
                      value: 'structured',
                      label: Text('Structured field'),
                      icon: Icon(Icons.tune_outlined, size: 18),
                    ),
                  ],
                  selected: {
                    _inputType == FieldInputType.freeText
                        ? 'freeText'
                        : 'structured'
                  },
                  onSelectionChanged: (selection) {
                    final structured = selection.first == 'structured';
                    setState(() {
                      if (structured) {
                        if (_inputType == FieldInputType.freeText) {
                          _inputType = FieldInputType.singleSelect;
                        }
                      } else {
                        _inputType = FieldInputType.freeText;
                        _addToRecords = false;
                        _allowOptionalNote = false;
                      }
                    });
                  },
                ),
                if (_inputType != FieldInputType.freeText) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<FieldInputType>(
                    value: _inputType,
                    decoration: const InputDecoration(
                      labelText: 'Structured type',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: FieldInputType.yesNo,
                        child: Text('Yes / No'),
                      ),
                      DropdownMenuItem(
                        value: FieldInputType.singleSelect,
                        child: Text('Single select'),
                      ),
                      DropdownMenuItem(
                        value: FieldInputType.multiSelect,
                        child: Text('Multi-select'),
                      ),
                    ],
                    onChanged: (v) => setState(() {
                      _inputType = v ?? _inputType;
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _options,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: _inputType == FieldInputType.yesNo
                          ? 'Options'
                          : 'Options / suggestions',
                      hintText: _inputType == FieldInputType.yesNo
                          ? 'Yes and No are used automatically'
                          : 'One option per line, or comma-separated',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    enabled: _inputType != FieldInputType.yesNo,
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: _showInPdf,
                    onChanged: (v) =>
                        setState(() => _showInPdf = v ?? true),
                    title: const Text('Show value in PDF'),
                    subtitle: const Text(
                      'Include the selected structured value in the report.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  CheckboxListTile(
                    value: _addToRecords,
                    onChanged: (v) =>
                        setState(() => _addToRecords = v ?? false),
                    title: const Text('Save to Records'),
                    subtitle: const Text(
                      'Store the structured value as searchable/exportable data.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  CheckboxListTile(
                    value: _allowOptionalNote,
                    onChanged: (v) =>
                        setState(() => _allowOptionalNote = v ?? false),
                    title: const Text('Allow optional note'),
                    subtitle: const Text(
                      'Let the clinician add narrative detail without changing the structured value.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.info_outline, size: 20),
                    title: Text('Free text is narrative only'),
                    subtitle: Text(
                      'It can appear in the PDF but is not saved as structured Records data.',
                    ),
                  ),
                ],
"""
t = replace_one(t, old_ui, new_ui, "template editor field behavior UI")

t = replace_one(
    t,
    """                        inputType: _inputType,
                        options: options,
                        addToRecords: _addToRecords,
                        conditionalParentSectionId: _useCondition ? _conditionParentId : '',
""",
    """                        inputType: _inputType,
                        options: options,
                        showInPdf: _inputType == FieldInputType.freeText
                            ? true
                            : _showInPdf,
                        addToRecords: _inputType == FieldInputType.freeText
                            ? false
                            : _addToRecords,
                        allowOptionalNote: _inputType == FieldInputType.freeText
                            ? false
                            : _allowOptionalNote,
                        conditionalParentSectionId: _useCondition ? _conditionParentId : '',
""",
    "template editor apply button",
)
updated[p] = t

# ------------------------------------------------------------------
# 7. Report editor: show separate optional note under structured selector
# ------------------------------------------------------------------
p = "lib/features/reports/ui/report_editor_screen.dart"
t = updated[p]

old_return = """      return Padding(
        padding: EdgeInsets.only(left: contentIndentPx),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: openStructuredPicker,
          child: InputDecorator(
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            child: Text(
              valueText,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isPlaceholder ? Colors.black45 : null,
                    fontStyle: isPlaceholder ? FontStyle.italic : FontStyle.normal,
                  ),
            ),
          ),
        ),
      );
"""
new_return = """      return Padding(
        padding: EdgeInsets.only(left: contentIndentPx),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: openStructuredPicker,
              child: InputDecorator(
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                child: Text(
                  valueText,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: isPlaceholder ? Colors.black45 : null,
                        fontStyle: isPlaceholder
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                ),
              ),
            ),
            if (s.allowOptionalNote) ...[
              const SizedBox(height: 8),
              TextFormField(
                key: ValueKey('structured-note-${s.id}'),
                initialValue: s.note,
                minLines: 1,
                maxLines: null,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Optional note…',
                  helperText:
                      'Narrative detail for the report; not saved as structured data.',
                  isDense: true,
                ),
                onChanged: (v) => vm.updateSectionNote(s.id, v),
              ),
            ],
          ],
        ),
      );
"""
t = replace_one(t, old_return, new_return, "report editor optional note UI")
updated[p] = t

# ------------------------------------------------------------------
# 8. PDF renderer: note remains report narrative even if structured value hidden
# ------------------------------------------------------------------
p = "lib/features/reports/services/pdf_renderer_service.dart"
t = updated[p]

t = replace_one(
    t,
    """  bool _sectionHasAnyPdfOutput(ReportDoc doc, SectionNode section) {
    if (!_sectionConditionAllows(doc, section)) return false;
    if (section.showInPdf) return true;
    return section.children
""",
    """  bool _sectionHasAnyPdfOutput(ReportDoc doc, SectionNode section) {
    if (!_sectionConditionAllows(doc, section)) return false;
    if (section.showInPdf || section.note.trim().isNotEmpty) return true;
    return section.children
""",
    "PDF output detection",
)

old_hidden = """    if (!s.showInPdf) {
      for (final child in s.children.whereType<SectionNode>()) {
        out.addAll(_sectionWidgets(child, doc: doc, contentFontSize: contentFontSize));
      }
      return out;
    }
"""
new_hidden = """    if (!s.showInPdf) {
      final note = s.note.trim();
      if (note.isNotEmpty) {
        final prefix = s.title.trim().isEmpty ? '' : '${s.title}: ';
        out.add(
          pw.Padding(
            padding: pw.EdgeInsets.only(
              left: doc.indentHierarchy ? 12.0 * s.indent : 0.0,
              bottom: 10,
            ),
            child: pw.RichText(
              text: pw.TextSpan(
                children: [
                  if (prefix.isNotEmpty)
                    pw.TextSpan(
                      text: prefix,
                      style: pw.TextStyle(
                        fontSize: contentFontSize,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  pw.TextSpan(
                    text: note,
                    style: pw.TextStyle(
                      fontSize: contentFontSize,
                      lineSpacing: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      for (final child in s.children.whereType<SectionNode>()) {
        out.addAll(
          _sectionWidgets(child, doc: doc, contentFontSize: contentFontSize),
        );
      }
      return out;
    }
"""
t = replace_one(t, old_hidden, new_hidden, "PDF hidden structured value with note")

# Insert a reusable note widget after blockContentWidget.
needle = """    pw.Widget inlineWidget(String text, {required bool aligned, required bool showLabel}) {
"""
note_helper = """    pw.Widget noteWidget() {
      final note = s.note.trim();
      if (note.isEmpty) return pw.SizedBox();
      return pw.Padding(
        padding: pw.EdgeInsets.only(left: contentIndentPx, bottom: 10),
        child: pw.Text(
          note,
          style: pw.TextStyle(
            fontSize: contentFontSize,
            lineSpacing: 1.6,
          ),
        ),
      );
    }

    pw.Widget inlineWidget(String text, {required bool aligned, required bool showLabel}) {
"""
t = replace_first(t, needle, note_helper, "PDF note helper")

# Section with children: append note after intro before children.
t = replace_first(
    t,
    """      if (introNode != null && introNode.text.trim().isNotEmpty) {
        out.add(
          doc.reportLayout == ReportLayout.block
              ? blockContentWidget(introNode.text.trim())
              : inlineWidget(introNode.text.trim(), aligned: doc.reportLayout == ReportLayout.aligned, showLabel: true),
        );
      }
      for (final child in sectionChildren) {
""",
    """      if (introNode != null && introNode.text.trim().isNotEmpty) {
        out.add(
          doc.reportLayout == ReportLayout.block
              ? blockContentWidget(introNode.text.trim())
              : inlineWidget(
                  introNode.text.trim(),
                  aligned: doc.reportLayout == ReportLayout.aligned,
                  showLabel: true,
                ),
        );
      }
      if (s.note.trim().isNotEmpty) {
        out.add(noteWidget());
      }
      for (final child in sectionChildren) {
""",
    "PDF note for parent section",
)

# Leaf block: append note before return.
t = replace_first(
    t,
    """      out.add(titleWidget(overrideTitle: colonTitle));
      out.add(blockContentWidget(leafText));
      return out;
""",
    """      out.add(titleWidget(overrideTitle: colonTitle));
      out.add(blockContentWidget(leafText));
      if (s.note.trim().isNotEmpty) {
        out.add(noteWidget());
      }
      return out;
""",
    "PDF note for block leaf",
)

# Leaf inline: append note after inline value.
t = replace_first(
    t,
    """    out.add(
      inlineWidget(
        leafText,
        aligned: doc.reportLayout == ReportLayout.aligned,
        showLabel: true,
      ),
    );
    return out;
""",
    """    out.add(
      inlineWidget(
        leafText,
        aligned: doc.reportLayout == ReportLayout.aligned,
        showLabel: true,
      ),
    );
    if (s.note.trim().isNotEmpty) {
      out.add(noteWidget());
    }
    return out;
""",
    "PDF note for inline leaf",
)
updated[p] = t

# ------------------------------------------------------------------
# Final validation before writing
# ------------------------------------------------------------------
changed = [rel for rel in FILES if updated[rel] != original[rel]]
if not changed:
    die("No changes produced.")

# Only write after every transformation above succeeded.
for rel in changed:
    (ROOT / rel).write_text(updated[rel], encoding="utf-8")

print("\nApplied Ripot structured-input change-set successfully.")
print(f"Changed {len(changed)} files:")
for rel in changed:
    print(f"  - {rel}")

print(
    "\nNext run:\n"
    "  dart format " + " ".join(changed) + "\n"
    "  flutter analyze\n"
    "  flutter run -d chrome\n"
)
print(
    "If you want to discard the whole change-set before committing:\n"
    "  git reset --hard HEAD\n"
)

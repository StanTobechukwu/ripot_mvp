#include "../../windows/runner/report_clipboard_format.h"
#include <cassert>
#include <iostream>

int main() {
  for (const std::string& fragment : {std::string("<div>Report</div>"),
       std::string(u8"<div>Fictional Éméka: 12.5 µm, 37 °C 中文</div>")}) {
    const auto html = ReportClipboardHtml(fragment);
    const auto offset = [&](const std::string& label) {
      return std::stoull(html.substr(html.find(label) + label.size(), 10));
    };
    assert(html.substr(offset("StartHTML:"), 6) == "<html>");
    assert(offset("EndHTML:") == html.size());
    const auto first = offset("StartFragment:");
    const auto last = offset("EndFragment:");
    assert(html.substr(first, last - first) == fragment);
    assert(html.substr(last, 18) == "<!--EndFragment-->");
  }
  std::cout << "PASS: CF_HTML byte offsets for ASCII and multibyte report text\n";
}

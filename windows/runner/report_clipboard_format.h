#ifndef RUNNER_REPORT_CLIPBOARD_FORMAT_H_
#define RUNNER_REPORT_CLIPBOARD_FORMAT_H_

#include <iomanip>
#include <sstream>
#include <string>

// CF_HTML offsets count UTF-8 bytes, not characters. Keep the header fixed-width
// so non-ASCII names and clinical symbols do not shift the selected fragment.
inline std::string ReportClipboardHtml(const std::string& fragment) {
  const std::string prefix =
      "<html><head><meta charset=\"utf-8\"></head><body><!--StartFragment-->";
  const std::string suffix = "<!--EndFragment--></body></html>";
  auto header = [](size_t start, size_t end, size_t first, size_t last) {
    std::ostringstream out;
    out << "Version:1.0\r\nStartHTML:" << std::setfill('0') << std::setw(10)
        << start << "\r\nEndHTML:" << std::setw(10) << end
        << "\r\nStartFragment:" << std::setw(10) << first
        << "\r\nEndFragment:" << std::setw(10) << last << "\r\n";
    return out.str();
  };
  const size_t start = header(0, 0, 0, 0).size();
  const size_t first = start + prefix.size();
  const size_t last = first + fragment.size();
  return header(start, last + suffix.size(), first, last) + prefix + fragment + suffix;
}

#endif

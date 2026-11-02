#include "report_clipboard.h"
#include "report_clipboard_format.h"

#include <cstring>
#include <limits>
#include <string>

namespace {
HGLOBAL CopyMemoryBlock(const void* bytes, size_t size) {
  HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, size);
  if (!memory) return nullptr;
  void* target = GlobalLock(memory);
  if (!target) { GlobalFree(memory); return nullptr; }
  std::memcpy(target, bytes, size);
  GlobalUnlock(memory);
  return memory;
}

bool WriteReportClipboard(HWND owner, const std::string& text,
                          const std::string& fragment) {
  if (text.size() > static_cast<size_t>(std::numeric_limits<int>::max())) return false;
  const int length = static_cast<int>(text.size());
  const int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                      text.data(), length, nullptr, 0);
  if (!text.empty() && count == 0) return false;
  std::wstring wide(static_cast<size_t>(count), L'\0');
  if (count > 0) MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                    text.data(), length, wide.data(), count);
  const auto html = ReportClipboardHtml(fragment);
  const UINT html_format = RegisterClipboardFormatW(L"HTML Format");
  if (!html_format) return false;
  HGLOBAL plain_memory = CopyMemoryBlock(wide.c_str(), (wide.size() + 1) * sizeof(wchar_t));
  HGLOBAL html_memory = CopyMemoryBlock(html.c_str(), html.size() + 1);
  if (!plain_memory || !html_memory || !OpenClipboard(owner)) {
    if (plain_memory) GlobalFree(plain_memory);
    if (html_memory) GlobalFree(html_memory);
    return false;
  }
  bool success = false;
  if (EmptyClipboard()) {
    if (SetClipboardData(CF_UNICODETEXT, plain_memory)) {
      plain_memory = nullptr; // Ownership transferred to Windows.
      if (SetClipboardData(html_format, html_memory)) {
        html_memory = nullptr;
        success = true;
      }
    }
  }
  CloseClipboard();
  if (plain_memory) GlobalFree(plain_memory);
  if (html_memory) GlobalFree(html_memory);
  return success;
}
}  // namespace

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterReportClipboard(flutter::BinaryMessenger* messenger, HWND owner) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "ripot/report_clipboard", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([owner](const auto& call, auto result) {
    if (call.method_name() != "write") { result->NotImplemented(); return; }
    const auto* args = call.arguments()
        ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
    if (!args) { result->Error("arguments", "Missing report text."); return; }
    const auto plain = args->find(flutter::EncodableValue("text"));
    const auto rich = args->find(flutter::EncodableValue("html"));
    const auto* text = plain == args->end() ? nullptr : std::get_if<std::string>(&plain->second);
    const auto* html = rich == args->end() ? nullptr : std::get_if<std::string>(&rich->second);
    if (!text || !html) { result->Error("arguments", "Missing report text."); return; }
    if (!WriteReportClipboard(owner, *text, *html)) {
      result->Error("clipboard", "Clipboard is unavailable. Try again.");
      return;
    }
    result->Success();
  });
  return channel;
}

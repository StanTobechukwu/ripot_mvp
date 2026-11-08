#ifndef RUNNER_MICROSOFT_STORE_H_
#define RUNNER_MICROSOFT_STORE_H_
#include <flutter/binary_messenger.h>
#include <memory>
#include <windows.h>

class MicrosoftStoreBridge {
 public:
  MicrosoftStoreBridge(flutter::BinaryMessenger* messenger, HWND window);
  ~MicrosoftStoreBridge();
 private:
  struct State;
  std::shared_ptr<State> state_;
};
#endif

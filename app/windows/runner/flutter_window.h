#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <shellapi.h>

#include <chrono>
#include <memory>
#include <string>

#include "win32_window.h"

class FlutterWindow : public Win32Window {
 public:
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  static UINT ShowMessage();

 protected:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void HandleCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void ShowWindowNow();
  void HideWindow();
  void ToggleWindow();
  bool Visible();

  void AddTrayIcon();
  void RemoveTrayIcon();
  void ShowTrayMenu();

  flutter::DartProject project_;
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  bool quitting_ = false;
  bool active_ = false;
  std::chrono::steady_clock::time_point left_at_;

  NOTIFYICONDATAW tray_ = {};
  bool tray_added_ = false;
  UINT taskbar_created_ = 0;
  std::wstring tray_open_ = L"Open YAMP", tray_exit_ = L"Exit";
};

#endif  // RUNNER_FLUTTER_WINDOW_H_

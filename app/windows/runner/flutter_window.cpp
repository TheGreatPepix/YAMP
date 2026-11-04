#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT kTrayId = 1;
constexpr UINT kMenuOpen = 1, kMenuExit = 2;

std::wstring Wide(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  int size = MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                 static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring out(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      out.data(), size);
  return out;
}

std::wstring StringArg(const flutter::EncodableValue* args, const char* key) {
  auto map = args ? std::get_if<flutter::EncodableMap>(args) : nullptr;
  if (!map) {
    return std::wstring();
  }
  auto it = map->find(flutter::EncodableValue(key));
  if (it == map->end()) {
    return std::wstring();
  }
  auto text = std::get_if<std::string>(&it->second);
  return text ? Wide(*text) : std::wstring();
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

UINT FlutterWindow::ShowMessage() {
  static UINT message = RegisterWindowMessageW(L"YAMP.Show");
  return message;
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "yamp/desktop",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleCall(call, std::move(result));
  });

  taskbar_created_ = RegisterWindowMessageW(L"TaskbarCreated");
  AddTrayIcon();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::HandleCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& method = call.method_name();
  if (method == "show") {
    ShowWindowNow();
  } else if (method == "tray") {
    auto open_label = StringArg(call.arguments(), "open");
    auto exit_label = StringArg(call.arguments(), "exit");
    if (!open_label.empty()) {
      tray_open_ = open_label;
    }
    if (!exit_label.empty()) {
      tray_exit_ = exit_label;
    }
  } else if (method == "quit") {
    quitting_ = true;
    RemoveTrayIcon();
    PostMessageW(GetHandle(), WM_CLOSE, 0, 0);
  } else {
    result->NotImplemented();
    return;
  }
  result->Success();
}

bool FlutterWindow::Visible() {
  HWND hwnd = GetHandle();
  return hwnd && IsWindowVisible(hwnd) && !IsIconic(hwnd);
}

void FlutterWindow::ShowWindowNow() {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }
  ShowWindow(hwnd, IsIconic(hwnd) ? SW_RESTORE : SW_SHOW);
  HWND foreground = GetForegroundWindow();
  if (foreground == hwnd) {
    return;
  }
  DWORD ours = GetCurrentThreadId();
  DWORD theirs = GetWindowThreadProcessId(foreground, nullptr);
  bool attached =
      theirs != 0 && theirs != ours && AttachThreadInput(theirs, ours, TRUE);
  const UINT flags = SWP_NOSIZE | SWP_NOMOVE | SWP_SHOWWINDOW;
  SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, flags);
  SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0, flags);
  BringWindowToTop(hwnd);
  if (!SetForegroundWindow(hwnd)) {
    FlashWindow(hwnd, TRUE);
  }
  if (attached) {
    AttachThreadInput(theirs, ours, FALSE);
  }
}

void FlutterWindow::HideWindow() {
  if (HWND hwnd = GetHandle()) {
    ShowWindow(hwnd, SW_HIDE);
  }
}

void FlutterWindow::ToggleWindow() {
  bool front = active_ || std::chrono::steady_clock::now() - left_at_ <
                              std::chrono::seconds(1);
  if (Visible() && front) {
    HideWindow();
  } else {
    ShowWindowNow();
  }
}

void FlutterWindow::AddTrayIcon() {
  if (tray_added_ || quitting_) {
    return;
  }
  tray_.cbSize = sizeof(tray_);
  tray_.hWnd = GetHandle();
  tray_.uID = kTrayId;
  tray_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  tray_.uCallbackMessage = kTrayMessage;
  if (!tray_.hIcon) {
    tray_.hIcon = static_cast<HICON>(LoadImageW(
        GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
        GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), 0));
  }
  wcscpy_s(tray_.szTip, L"YAMP");
  tray_added_ = Shell_NotifyIconW(NIM_ADD, &tray_) != FALSE;
}

void FlutterWindow::RemoveTrayIcon() {
  if (tray_added_) {
    Shell_NotifyIconW(NIM_DELETE, &tray_);
    tray_added_ = false;
  }
  if (tray_.hIcon) {
    DestroyIcon(tray_.hIcon);
    tray_.hIcon = nullptr;
  }
}

void FlutterWindow::ShowTrayMenu() {
  HWND hwnd = GetHandle();
  HMENU menu = CreatePopupMenu();
  AppendMenuW(menu, MF_STRING, kMenuOpen, tray_open_.c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kMenuExit, tray_exit_.c_str());
  SetMenuDefaultItem(menu, kMenuOpen, FALSE);
  POINT at;
  GetCursorPos(&at);
  SetForegroundWindow(hwnd);
  UINT command = static_cast<UINT>(TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON | TPM_BOTTOMALIGN,
      at.x, at.y, 0, hwnd, nullptr));
  PostMessageW(hwnd, WM_NULL, 0, 0);
  DestroyMenu(menu);
  if (command == kMenuOpen) {
    ShowWindowNow();
  } else if (command == kMenuExit) {
    if (channel_) {
      channel_->InvokeMethod("exit", nullptr);
    }
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == ShowMessage()) {
    ShowWindowNow();
    return 0;
  }
  if (taskbar_created_ != 0 && message == taskbar_created_) {
    tray_added_ = false;
    AddTrayIcon();
    return 0;
  }
  switch (message) {
    case kTrayMessage:
      if (LOWORD(lparam) == WM_LBUTTONUP) {
        ToggleWindow();
      } else if (LOWORD(lparam) == WM_RBUTTONUP) {
        ShowTrayMenu();
      }
      return 0;
    case WM_CLOSE:
      if (!quitting_) {
        HideWindow();
        return 0;
      }
      break;
    case WM_ACTIVATE:
      active_ = LOWORD(wparam) != WA_INACTIVE;
      if (!active_) {
        left_at_ = std::chrono::steady_clock::now();
      }
      break;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

#include "flutter_window.h"

#include <optional>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shobjidl.h>
#include <shellapi.h>
#include <wrl/client.h>
#include "resource.h"
#include "utils.h"

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

namespace {
constexpr UINT kHubTray = WM_APP + 12;
constexpr UINT kOpen = 1;
constexpr UINT kExit = 2;
}

bool FlutterWindow::SetTray(bool enabled) {
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = GetHandle();
  data.uID = 1;
  if (!enabled) {
    if (tray_active_) Shell_NotifyIconW(NIM_DELETE, &data);
    tray_active_ = false;
    return false;
  }
  if (tray_active_) return true;
  data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  data.uCallbackMessage = kHubTray;
  data.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(data.szTip, L"NamiHub");
  tray_active_ = Shell_NotifyIconW(NIM_ADD, &data) != FALSE;
  return tray_active_;
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
  flutter::MethodChannel<flutter::EncodableValue> folders(
      flutter_controller_->engine()->messenger(), "nami_hub/desktop",
      &flutter::StandardMethodCodec::GetInstance());
  folders.SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "sharing") {
      const bool* active = call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
      sharing_ = active && *active;
      result->Success(flutter::EncodableValue(SetTray(sharing_)));
      return;
    }
    if (call.method_name() != "choose") { result->NotImplemented(); return; }
    Microsoft::WRL::ComPtr<IFileOpenDialog> dialog;
    HRESULT hr = CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog));
    DWORD options = 0;
    if (SUCCEEDED(hr)) hr = dialog->GetOptions(&options);
    if (SUCCEEDED(hr)) hr = dialog->SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_NOCHANGEDIR);
    if (SUCCEEDED(hr)) hr = dialog->Show(GetHandle());
    if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) { result->Success(); return; }
    Microsoft::WRL::ComPtr<IShellItem> item;
    if (SUCCEEDED(hr)) hr = dialog->GetResult(&item);
    PWSTR path = nullptr;
    if (SUCCEEDED(hr)) hr = item->GetDisplayName(SIGDN_FILESYSPATH, &path);
    if (FAILED(hr)) { result->Error("folder_dialog", "Folder selection failed"); return; }
    const std::string utf8 = Utf8FromUtf16(path);
    CoTaskMemFree(path);
    if (utf8.empty()) {
      result->Error("folder_dialog", "Could not read the selected folder path");
      return;
    }
    result->Success(flutter::EncodableValue(utf8));
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

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
  SetTray(false);
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_CLOSE && tray_active_) {
    ShowWindow(hwnd, SW_HIDE);
    return 0;
  }
  if (message == kHubTray) {
    if (lparam == WM_LBUTTONUP) {
      ShowWindow(hwnd, SW_RESTORE);
      SetForegroundWindow(hwnd);
    }
    if (lparam == WM_RBUTTONUP) {
      HMENU menu = CreatePopupMenu();
      if (!menu) return 0;
      AppendMenuW(menu, MF_STRING, kOpen, L"\u6253\u5f00 NamiHub");
      AppendMenuW(menu, MF_STRING, kExit, L"\u9000\u51fa\u5e76\u505c\u6b62\u5171\u4eab");
      POINT cursor{};
      GetCursorPos(&cursor);
      SetForegroundWindow(hwnd);
      const int choice = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON,
                                        cursor.x, cursor.y, 0, hwnd, nullptr);
      DestroyMenu(menu);
      PostMessage(hwnd, WM_NULL, 0, 0);
      if (choice == kOpen) {
        ShowWindow(hwnd, SW_RESTORE);
        SetForegroundWindow(hwnd);
      } else if (choice == kExit) {
        sharing_ = false;
        SetTray(false);
        PostMessage(hwnd, WM_CLOSE, 0, 0);
      }
    }
    return 0;
  }
  static const UINT taskbar_created = RegisterWindowMessageW(L"TaskbarCreated");
  if (message == taskbar_created && sharing_) {
    tray_active_ = false;
    if (!SetTray(true)) ShowWindow(hwnd, SW_RESTORE);
    return 0;
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

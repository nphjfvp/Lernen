#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include <optional>
#include <string>
#include <utility>
#include <variant>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"
#include "utils.h"

namespace {

// Nachricht des Symbols im Infobereich (Klick holt die App nach vorn).
constexpr UINT kTrayMessage = WM_APP + 42;
constexpr UINT kTrayId = 1;

std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  const int length = ::MultiByteToWideChar(
      CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
  if (length <= 0) {
    return std::wstring();
  }
  std::wstring result(static_cast<size_t>(length), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                        result.data(), length);
  return result;
}

std::string StringArg(const flutter::EncodableMap& map, const char* key) {
  const auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) {
    return std::string();
  }
  const auto* value = std::get_if<std::string>(&it->second);
  return value != nullptr ? *value : std::string();
}

HWND HwndFrom(const flutter::EncodableValue* value) {
  if (value == nullptr) {
    return nullptr;
  }
  if (const auto* small = std::get_if<int32_t>(value)) {
    return reinterpret_cast<HWND>(static_cast<intptr_t>(*small));
  }
  if (const auto* big = std::get_if<int64_t>(value)) {
    return reinterpret_cast<HWND>(static_cast<intptr_t>(*big));
  }
  return nullptr;
}

// Programmname (z.B. "chrome.exe") und Titel eines Fensters. Der Titel kommt
// ohne Nachricht an das Fenster (InternalGetWindowText), damit ein haengendes
// Programm die App nicht aufhaelt.
flutter::EncodableMap WindowInfo(HWND hwnd, DWORD pid) {
  wchar_t title[512] = {};
  ::InternalGetWindowText(hwnd, title, 512);
  std::wstring exe;
  HANDLE process = ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (process != nullptr) {
    wchar_t path[1024] = {};
    DWORD size = 1024;
    if (::QueryFullProcessImageNameW(process, 0, path, &size)) {
      exe.assign(path, size);
      const size_t slash = exe.find_last_of(L"\\/");
      if (slash != std::wstring::npos) {
        exe = exe.substr(slash + 1);
      }
    }
    ::CloseHandle(process);
  }
  flutter::EncodableMap map;
  map[flutter::EncodableValue("hwnd")] = flutter::EncodableValue(
      static_cast<int64_t>(reinterpret_cast<intptr_t>(hwnd)));
  map[flutter::EncodableValue("exe")] =
      flutter::EncodableValue(Utf8FromUtf16(exe.c_str()));
  map[flutter::EncodableValue("title")] =
      flutter::EncodableValue(Utf8FromUtf16(title));
  map[flutter::EncodableValue("self")] =
      flutter::EncodableValue(pid == ::GetCurrentProcessId());
  return map;
}

BOOL CALLBACK CollectWindow(HWND hwnd, LPARAM param) {
  auto* list = reinterpret_cast<flutter::EncodableList*>(param);
  if (!::IsWindowVisible(hwnd) || ::GetWindow(hwnd, GW_OWNER) != nullptr) {
    return TRUE;
  }
  if ((::GetWindowLongPtrW(hwnd, GWL_EXSTYLE) & WS_EX_TOOLWINDOW) != 0) {
    return TRUE;
  }
  wchar_t title[8] = {};
  if (::InternalGetWindowText(hwnd, title, 8) == 0) {
    return TRUE;
  }
  DWORD pid = 0;
  ::GetWindowThreadProcessId(hwnd, &pid);
  if (pid == ::GetCurrentProcessId()) {
    return TRUE;
  }
  list->push_back(flutter::EncodableValue(WindowInfo(hwnd, pid)));
  return TRUE;
}

// Autostart mit Windows (unsichtbar, nur Symbol im Infobereich).
void SetAutostart(bool on) {
  const wchar_t* key = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
  if (on) {
    wchar_t path[1024] = {};
    const DWORD length = ::GetModuleFileNameW(nullptr, path, 1024);
    if (length == 0) {
      return;
    }
    const std::wstring value =
        L"\"" + std::wstring(path, length) + L"\" --minimized";
    ::RegSetKeyValueW(HKEY_CURRENT_USER, key, L"Lernen", REG_SZ, value.c_str(),
                      static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
  } else {
    HKEY handle = nullptr;
    if (::RegOpenKeyExW(HKEY_CURRENT_USER, key, 0, KEY_SET_VALUE, &handle) ==
        ERROR_SUCCESS) {
      ::RegDeleteValueW(handle, L"Lernen");
      ::RegCloseKey(handle);
    }
  }
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

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

  guard_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "lernen/windows_guard",
          &flutter::StandardMethodCodec::GetInstance());
  guard_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleGuardCall(call, std::move(result)); });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (!start_hidden_) {
      this->Show();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  SetTray(false);
  guard_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::HandleGuardCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  if (method == "foreground") {
    HWND foreground = ::GetForegroundWindow();
    if (foreground == nullptr) {
      result->Success();
      return;
    }
    DWORD pid = 0;
    ::GetWindowThreadProcessId(foreground, &pid);
    result->Success(flutter::EncodableValue(WindowInfo(foreground, pid)));
  } else if (method == "windows") {
    flutter::EncodableList list;
    ::EnumWindows(CollectWindow, reinterpret_cast<LPARAM>(&list));
    result->Success(flutter::EncodableValue(list));
  } else if (method == "minimize") {
    HWND target = HwndFrom(call.arguments());
    if (target != nullptr && ::IsWindow(target)) {
      ::ShowWindowAsync(target, SW_MINIMIZE);
    }
    result->Success();
  } else if (method == "close") {
    HWND target = HwndFrom(call.arguments());
    if (target != nullptr && ::IsWindow(target)) {
      ::PostMessageW(target, WM_CLOSE, 0, 0);
    }
    result->Success();
  } else if (method == "bringToFront") {
    BringToFront();
    result->Success();
  } else if (method == "hideSelf") {
    SetTray(true);
    ::ShowWindow(GetHandle(), SW_HIDE);
    result->Success();
  } else if (method == "setKeepRunning") {
    const auto* value = std::get_if<bool>(call.arguments());
    keep_running_ = value != nullptr && *value;
    SetTray(keep_running_);
    SetAutostart(keep_running_);
    if (!keep_running_ && !::IsWindowVisible(GetHandle())) {
      BringToFront();
    }
    result->Success();
  } else if (method == "notify") {
    const auto* map = std::get_if<flutter::EncodableMap>(call.arguments());
    if (map != nullptr) {
      ShowBalloon(Utf16FromUtf8(StringArg(*map, "title")),
                  Utf16FromUtf8(StringArg(*map, "body")));
    }
    result->Success();
  } else {
    result->NotImplemented();
  }
}

void FlutterWindow::SetTray(bool on) {
  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(data);
  data.hWnd = GetHandle();
  data.uID = kTrayId;
  if (on && !tray_added_) {
    data.uFlags = NIF_ICON | NIF_TIP | NIF_MESSAGE;
    data.uCallbackMessage = kTrayMessage;
    data.hIcon = ::LoadIconW(::GetModuleHandleW(nullptr),
                             MAKEINTRESOURCEW(IDI_APP_ICON));
    wcsncpy_s(data.szTip, L"Lernen - Lernzeit-Sperre aktiv", _TRUNCATE);
    tray_added_ = ::Shell_NotifyIconW(NIM_ADD, &data) != FALSE;
  } else if (!on && tray_added_) {
    ::Shell_NotifyIconW(NIM_DELETE, &data);
    tray_added_ = false;
  }
}

void FlutterWindow::ShowBalloon(const std::wstring& title,
                                const std::wstring& body) {
  SetTray(true);
  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(data);
  data.hWnd = GetHandle();
  data.uID = kTrayId;
  data.uFlags = NIF_INFO;
  wcsncpy_s(data.szInfoTitle, title.c_str(), _TRUNCATE);
  wcsncpy_s(data.szInfo, body.c_str(), _TRUNCATE);
  data.dwInfoFlags = NIIF_INFO;
  ::Shell_NotifyIconW(NIM_MODIFY, &data);
}

void FlutterWindow::BringToFront() {
  HWND hwnd = GetHandle();
  ::ShowWindow(hwnd, SW_SHOW);
  ::ShowWindow(hwnd, SW_RESTORE);
  ::SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
  ::SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
  // Den Fokus holen: Windows erlaubt das nur dem Vordergrund-Programm, darum
  // kurz an dessen Eingabe anhaengen.
  HWND foreground = ::GetForegroundWindow();
  const DWORD foreground_thread =
      foreground != nullptr ? ::GetWindowThreadProcessId(foreground, nullptr)
                            : 0;
  const DWORD own_thread = ::GetCurrentThreadId();
  if (foreground_thread != 0 && foreground_thread != own_thread) {
    ::AttachThreadInput(foreground_thread, own_thread, TRUE);
    ::BringWindowToTop(hwnd);
    ::SetForegroundWindow(hwnd);
    ::AttachThreadInput(foreground_thread, own_thread, FALSE);
  } else {
    ::SetForegroundWindow(hwnd);
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
    case WM_CLOSE:
      // Lernzeit-Sperre an: nur ausblenden, die Sperre laeuft weiter.
      if (keep_running_) {
        SetTray(true);
        ::ShowWindow(hwnd, SW_HIDE);
        return 0;
      }
      break;
    case kTrayMessage:
      if (static_cast<UINT>(lparam) == WM_LBUTTONUP ||
          static_cast<UINT>(lparam) == WM_LBUTTONDBLCLK) {
        BringToFront();
        return 0;
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

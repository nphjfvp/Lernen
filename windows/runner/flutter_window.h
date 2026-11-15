#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <string>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  // Lernzeit-Sperre: per Autostart unsichtbar starten (nur das Symbol im
  // Infobereich), statt das Fenster nach dem ersten Bild zu zeigen.
  void SetStartHidden(bool hidden) { start_hidden_ = hidden; }

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // Kanal "lernen/windows_guard" fuer die Lernzeit-Sperre (siehe
  // lib/services/windows_guard.dart).
  void HandleGuardCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void SetTray(bool on);
  void ShowBalloon(const std::wstring& title, const std::wstring& body);
  void BringToFront();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      guard_channel_;

  // Solange die Sperre an ist: Schliessen blendet nur aus (Symbol im
  // Infobereich bleibt), damit sie weiterlaeuft.
  bool keep_running_ = false;
  bool tray_added_ = false;
  bool start_hidden_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_

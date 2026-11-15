#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  bool start_hidden = false;
  // "Vorlesung mit Aufgabe": die Tafel als eigenes Fenster der App.
  bool lecture_board = false;
  for (const std::string& argument : command_line_arguments) {
    if (argument == "--minimized") {
      start_hidden = true;
    }
    if (argument.rfind("--lecture-board=", 0) == 0) {
      lecture_board = true;
    }
  }

  // Nur eine laufende App (die Lernzeit-Sperre startet sie mit Windows):
  // ein zweiter Start holt die laufende nach vorn. Das Tafel-Fenster zaehlt
  // nicht mit.
  HANDLE single_instance =
      lecture_board
          ? nullptr
          : ::CreateMutexW(nullptr, FALSE, L"Local\\LernenAppEinzigeInstanz");
  if (single_instance != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"lernen");
    if (existing != nullptr) {
      ::ShowWindow(existing, SW_SHOW);
      ::ShowWindow(existing, SW_RESTORE);
      ::SetForegroundWindow(existing);
    }
    ::CloseHandle(single_instance);
    return EXIT_SUCCESS;
  }

  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  window.SetStartHidden(start_hidden);
  Win32Window::Point origin(lecture_board ? 60u : 10u, lecture_board ? 60u : 10u);
  Win32Window::Size size(lecture_board ? 900u : 1280u, lecture_board ? 820u : 720u);
  if (!window.Create(lecture_board ? L"Lernen - Tafel" : L"lernen", origin,
                     size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (single_instance != nullptr) {
    ::CloseHandle(single_instance);
  }
  return EXIT_SUCCESS;
}

#include "flutter_window.h"
#include <optional>
#include "flutter/generated_plugin_registrant.h"
#include <shobjidl.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  // Initialize COM for Taskbar Progress
  CoInitialize(NULL);

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  // Setup Method Channel for Taskbar Progress
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "com.dirxplore/taskbar",
      &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name().compare("setProgress") == 0) {
          const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
          if (arguments) {
             auto progress_it = arguments->find(flutter::EncodableValue("progress"));
             if (progress_it != arguments->end()) {
               double progress = std::get<double>(progress_it->second);
               
               ITaskbarList3* pTaskbarList;
               HRESULT hr = CoCreateInstance(CLSID_TaskbarList, NULL, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&pTaskbarList));
               if (SUCCEEDED(hr)) {
                 hr = pTaskbarList->HrInit();
                 if (SUCCEEDED(hr)) {
                   HWND hwnd = GetHandle();
                   if (progress >= 1.0) {
                     pTaskbarList->SetProgressState(hwnd, TBPF_NOPROGRESS);
                   } else if (progress < 0) {
                     pTaskbarList->SetProgressState(hwnd, TBPF_INDETERMINATE);
                   } else {
                     pTaskbarList->SetProgressState(hwnd, TBPF_NORMAL);
                     pTaskbarList->SetProgressValue(hwnd, (ULONGLONG)(progress * 100), 100);
                   }
                 }
                 pTaskbarList->Release();
               }
             }
          }
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  CoUninitialize();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
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
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "flutter/method_channel.h"
#include "flutter/standard_method_codec.h"

namespace {
// Flutter encodes Dart ints as either int32_t or int64_t; accept both.
int64_t ToIntValue(const flutter::EncodableValue& v) {
  if (const auto* i = std::get_if<int32_t>(&v)) return *i;
  if (const auto* i = std::get_if<int64_t>(&v)) return *i;
  return 0;
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

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Face detection engine: load models from the directory next to the exe.
  {
    wchar_t exe_path[MAX_PATH] = {0};
    DWORD len = GetModuleFileNameW(nullptr, exe_path, MAX_PATH);
    std::wstring dir;
    if (len > 0) {
      std::wstring p(exe_path);
      auto pos = p.find_last_of(L'\\');
      if (pos != std::wstring::npos) dir = p.substr(0, pos);
    }
    face_engine_ = std::make_unique<FaceEngine>();
    face_engine_->Initialize(dir);
  }

  // Method channel for on-device face detection.
  face_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "jingerpic/face",
          &flutter::StandardMethodCodec::GetInstance());
  face_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "detect" && face_engine_ &&
            face_engine_->IsReady()) {
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (!args) {
            result->Error("bad_args", "expected a map");
            return;
          }
          auto rgb_it = args->find(flutter::EncodableValue("rgb"));
          auto w_it = args->find(flutter::EncodableValue("w"));
          auto h_it = args->find(flutter::EncodableValue("h"));
          if (rgb_it == args->end() || w_it == args->end() ||
              h_it == args->end()) {
            result->Error("bad_args", "missing rgb/w/h");
            return;
          }
          const auto& rgb_vec =
              std::get<std::vector<uint8_t>>(rgb_it->second);
          const int w = static_cast<int>(ToIntValue(w_it->second));
          const int h = static_cast<int>(ToIntValue(h_it->second));
          std::vector<FaceDetection> faces =
              face_engine_->Detect(rgb_vec.data(), w, h);
          flutter::EncodableList out;
          for (const auto& f : faces) {
            flutter::EncodableMap m;
            m[flutter::EncodableValue("x")] = f.x;
            m[flutter::EncodableValue("y")] = f.y;
            m[flutter::EncodableValue("w")] = f.w;
            m[flutter::EncodableValue("h")] = f.h;
            m[flutter::EncodableValue("score")] = f.score;
            flutter::EncodableList emb;
            for (float v : f.embedding) emb.push_back(v);
            m[flutter::EncodableValue("embedding")] = std::move(emb);
            out.push_back(flutter::EncodableValue(std::move(m)));
          }
          result->Success(flutter::EncodableValue(std::move(out)));
        } else {
          result->NotImplemented();
        }
      });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
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

#pragma once

#include <vector>
#include <string>
#include <cstdint>

// A single detected face: bounding box (original-image pixel coordinates),
// confidence score, and a 128-d SFace embedding.
struct FaceDetection {
  float x = 0.0f;
  float y = 0.0f;
  float w = 0.0f;
  float h = 0.0f;
  float score = 0.0f;
  std::vector<float> embedding;  // 128 floats, L2-normalized
};

// Local face engine backed by ONNX Runtime (loaded dynamically at runtime,
// so no link-time dependency on onnxruntime.lib is required).
class FaceEngine {
 public:
  FaceEngine();
  ~FaceEngine();

  // Loads the YuNet detector and SFace recognizer models from the given
  // directory (they are expected as siblings of the executable).
  bool Initialize(const std::wstring& modelDir);

  bool IsReady() const { return ready_; }

  // rgb: row-major RGB bytes (length = w * h * 3). Returns all faces found.
  std::vector<FaceDetection> Detect(const uint8_t* rgb, int w, int h);

 private:
  // ONNX Runtime handles (C API).
  void* ort_dll_ = nullptr;
  const void* api_ = nullptr;          // const OrtApi*
  void* env_ = nullptr;                // OrtEnv*
  void* mem_info_ = nullptr;           // OrtMemoryInfo*
  void* allocator_ = nullptr;          // OrtAllocator*
  void* yunet_ = nullptr;              // OrtSession*
  void* sface_ = nullptr;              // OrtSession*

  std::string yunet_in_name_;
  std::vector<std::string> yunet_out_names_;  // 12 heads
  std::string sface_in_name_;
  std::string sface_out_name_;

  bool ready_ = false;

  // Spatial input size each model expects (queried from the graph at load
  // time; YuNet ships in both 320 and 640 variants).
  int yunet_input_size_ = 640;
  int sface_input_size_ = 112;

  // Reads the NCHW spatial size of a session's first input. False when dynamic.
  bool ReadInputSize(void* session, int* size) const;

  // Builds a 1x3xKxK NCHW BGR blob: anisotropic resize to the detector's real
  // input size, matching cv::FaceDetectorYN's preprocessing.
  std::vector<float> PreprocessYuNet(const uint8_t* rgb, int w, int h) const;

  // Runs a session and returns the raw float output plus its shape.
  std::vector<float> RunSession(void* session, const std::string& in_name,
                               const std::string& out_name,
                               const std::vector<float>& input,
                               const int64_t* in_dims, size_t in_dims_count,
                               std::vector<int64_t>& out_shape) const;

  // Aligns the face (via the 5 landmarks, image-space) to the canonical
  // 112x112 template and returns the L2-normalized SFace embedding.
  std::vector<float> ExtractEmbedding(const uint8_t* rgb, int w, int h,
                                      const float* landmarks);
};

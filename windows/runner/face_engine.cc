#include "face_engine.h"

#include <windows.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>

#ifdef JINGER_FACE_DEBUG
#define FLOG(...) std::fprintf(stderr, __VA_ARGS__)
#else
#define FLOG(...) ((void)0)
#endif

#include "onnxruntime_c_api.h"

namespace {

// Resize a RGB buffer (sw x sh) into dw x dh with bilinear interpolation.
void ResizeRGB(const uint8_t* src, int sw, int sh, int dw, int dh,
               std::vector<uint8_t>& out) {
  out.resize(static_cast<size_t>(dw) * dh * 3);
  for (int y = 0; y < dh; ++y) {
    float sy = (static_cast<float>(y) + 0.5f) / dh * sh - 0.5f;
    int y0 = static_cast<int>(std::floor(sy));
    int y1 = y0 + 1;
    float ty = sy - y0;
    auto clamp = [](int v, int n) { return v < 0 ? 0 : (v >= n ? n - 1 : v); };
    int ya = clamp(y0, sh), yb = clamp(y1, sh);
    for (int x = 0; x < dw; ++x) {
      float sx = (static_cast<float>(x) + 0.5f) / dw * sw - 0.5f;
      int x0 = static_cast<int>(std::floor(sx));
      int x1 = x0 + 1;
      float tx = sx - x0;
      int xa = clamp(x0, sw), xb = clamp(x1, sw);
      const uint8_t* p00 = src + (static_cast<size_t>(ya) * sw + xa) * 3;
      const uint8_t* p10 = src + (static_cast<size_t>(ya) * sw + xb) * 3;
      const uint8_t* p01 = src + (static_cast<size_t>(yb) * sw + xa) * 3;
      const uint8_t* p11 = src + (static_cast<size_t>(yb) * sw + xb) * 3;
      for (int c = 0; c < 3; ++c) {
        float v = (p00[c] * (1 - tx) + p10[c] * tx) * (1 - ty) +
                  (p01[c] * (1 - tx) + p11[c] * tx) * ty;
        out[static_cast<size_t>(y) * dw * 3 + x * 3 + c] =
            static_cast<uint8_t>(std::max(0.0f, std::min(255.0f, v)));
      }
    }
  }
}

// Reference facial landmarks for a 112x112 aligned face, in YuNet's order:
// right eye, left eye, nose tip, right mouth corner, left mouth corner.
const float kRefLandmarks[10] = {
    38.2946f, 51.6963f,  // right eye
    73.5318f, 51.6963f,  // left eye
    56.0252f, 71.7366f,  // nose tip
    41.5493f, 92.3655f,  // right mouth corner
    70.7299f, 92.3655f,  // left mouth corner
};

// Umeyama similarity transform: maps the 5 source points to the 5 reference
// points via rotation + uniform scale + translation. Writes a 2x3 matrix
// [M0 M1 M2; M3 M4 M5] that sends src -> dst.
void SimilarityTransform(const float* src, const float* dst, float M[6]) {
  float msx = 0, msy = 0, mdx = 0, mdy = 0;
  for (int i = 0; i < 5; ++i) {
    msx += src[2 * i];
    msy += src[2 * i + 1];
    mdx += dst[2 * i];
    mdy += dst[2 * i + 1];
  }
  msx /= 5; msy /= 5; mdx /= 5; mdy /= 5;
  float sdx[5], sdy[5], ddx[5], ddy[5];
  for (int i = 0; i < 5; ++i) {
    sdx[i] = src[2 * i] - msx;
    sdy[i] = src[2 * i + 1] - msy;
    ddx[i] = dst[2 * i] - mdx;
    ddy[i] = dst[2 * i + 1] - mdy;
  }
  double a00 = 0, a01 = 0, a10 = 0, a11 = 0;
  for (int i = 0; i < 5; ++i) {
    a00 += sdx[i] * ddx[i];
    a01 += sdx[i] * ddy[i];
    a10 += sdy[i] * ddx[i];
    a11 += sdy[i] * ddy[i];
  }
  a00 /= 5; a01 /= 5; a10 /= 5; a11 /= 5;
  double theta = std::atan2(a10 - a01, a00 + a11);
  double c = std::cos(theta), s = std::sin(theta);
  double trace = c * a00 + s * a10 - s * a01 + c * a11;
  double var = 0;
  for (int i = 0; i < 5; ++i) var += sdx[i] * sdx[i] + sdy[i] * sdy[i];
  var /= 5;
  double scale = (var > 1e-8) ? trace / var : 1.0;
  double tx = mdx - scale * (c * msx - s * msy);
  double ty = mdy - scale * (s * msx + c * msy);
  M[0] = static_cast<float>(scale * c);
  M[1] = static_cast<float>(-scale * s);
  M[2] = static_cast<float>(tx);
  M[3] = static_cast<float>(scale * s);
  M[4] = static_cast<float>(scale * c);
  M[5] = static_cast<float>(ty);
}

// Inverse-warp src rgb (w x h) into a dw x dh buffer using the 2x3 affine M.
void WarpAffineRGB(const uint8_t* rgb, int w, int h, const float M[6], int dw,
                   int dh, std::vector<uint8_t>& out) {
  out.resize(static_cast<size_t>(dw) * dh * 3);
  const float c = M[0], d = M[1], e = M[3], f = M[4];
  const float det = c * f - d * e;
  const float id = (std::abs(det) < 1e-8f) ? 1e-8f : det;
  const float ic = f / id, id2 = -d / id, ie = -e / id, iff = c / id;
  auto clamp = [](int v, int n) { return v < 0 ? 0 : (v >= n ? n - 1 : v); };
  for (int y = 0; y < dh; ++y) {
    for (int x = 0; x < dw; ++x) {
      const float dx = static_cast<float>(x) - M[2];
      const float dy = static_cast<float>(y) - M[5];
      const float sx = ic * dx + id2 * dy;
      const float sy = ie * dx + iff * dy;
      const int x0 = static_cast<int>(std::floor(sx));
      const int y0 = static_cast<int>(std::floor(sy));
      const float tx = sx - x0, ty = sy - y0;
      const int x1 = x0 + 1, y1 = y0 + 1;
      const int xa = clamp(x0, w), xb = clamp(x1, w);
      const int ya = clamp(y0, h), yb = clamp(y1, h);
      const uint8_t* p00 = rgb + (static_cast<size_t>(ya) * w + xa) * 3;
      const uint8_t* p10 = rgb + (static_cast<size_t>(ya) * w + xb) * 3;
      const uint8_t* p01 = rgb + (static_cast<size_t>(yb) * w + xa) * 3;
      const uint8_t* p11 = rgb + (static_cast<size_t>(yb) * w + xb) * 3;
      for (int cc = 0; cc < 3; ++cc) {
        const float v = (p00[cc] * (1 - tx) + p10[cc] * tx) * (1 - ty) +
                        (p01[cc] * (1 - tx) + p11[cc] * tx) * ty;
        out[static_cast<size_t>(y) * dw * 3 + x * 3 + cc] =
            static_cast<uint8_t>(std::max(0.0f, std::min(255.0f, v)));
      }
    }
  }
}

}  // namespace

FaceEngine::FaceEngine() = default;

FaceEngine::~FaceEngine() {
  const OrtApi* api = static_cast<const OrtApi*>(api_);
  if (api) {
    if (yunet_) api->ReleaseSession(static_cast<OrtSession*>(yunet_));
    if (sface_) api->ReleaseSession(static_cast<OrtSession*>(sface_));
    if (mem_info_) api->ReleaseMemoryInfo(static_cast<OrtMemoryInfo*>(mem_info_));
    if (env_) api->ReleaseEnv(static_cast<OrtEnv*>(env_));
  }
  if (ort_dll_) FreeLibrary(static_cast<HMODULE>(ort_dll_));
}

bool FaceEngine::Initialize(const std::wstring& modelDir) {
  if (ready_) return true;
  ort_dll_ = LoadLibraryA("onnxruntime.dll");
  if (!ort_dll_) return false;

  using GetApiBaseFn = const OrtApiBase*(ORT_API_CALL*)();
  auto get_api_base = reinterpret_cast<GetApiBaseFn>(
      GetProcAddress(static_cast<HMODULE>(ort_dll_), "OrtGetApiBase"));
  if (!get_api_base) return false;
  api_ = get_api_base()->GetApi(ORT_API_VERSION);
  const OrtApi* api = static_cast<const OrtApi*>(api_);
  if (!api) return false;

  if (api->CreateEnv(ORT_LOGGING_LEVEL_ERROR, "jingerpic",
                     reinterpret_cast<OrtEnv**>(&env_)) != nullptr)
    return false;
  if (api->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault,
                               reinterpret_cast<OrtMemoryInfo**>(&mem_info_)) !=
      nullptr)
    return false;
  if (api->GetAllocatorWithDefaultOptions(
          reinterpret_cast<OrtAllocator**>(&allocator_)) != nullptr)
    return false;

  std::wstring yunet_path = modelDir + L"/face_detection_yunet_2023mar.onnx";
  std::wstring sface_path = modelDir + L"/face_recognition_sface_2021dec.onnx";

  if (api->CreateSession(static_cast<OrtEnv*>(env_), yunet_path.c_str(),
                         nullptr,
                         reinterpret_cast<OrtSession**>(&yunet_)) != nullptr)
    return false;
  if (api->CreateSession(static_cast<OrtEnv*>(env_), sface_path.c_str(),
                         nullptr,
                         reinterpret_cast<OrtSession**>(&sface_)) != nullptr)
    return false;

  char* in = nullptr;
  char* out = nullptr;
  api->SessionGetInputName(static_cast<OrtSession*>(yunet_), 0,
                           static_cast<OrtAllocator*>(allocator_), &in);
  if (in) yunet_in_name_ = in;
  // YuNet has 12 outputs (cls/obj/bbox/kps for strides 8/16/32); keep all
  // names so Detect can request every head in a single Run.
  for (int i = 0; i < 12; ++i) {
    char* nm = nullptr;
    api->SessionGetOutputName(static_cast<OrtSession*>(yunet_), i,
                              static_cast<OrtAllocator*>(allocator_), &nm);
    yunet_out_names_.push_back(nm ? nm : "");
  }
  in = nullptr;
  api->SessionGetInputName(static_cast<OrtSession*>(sface_), 0,
                           static_cast<OrtAllocator*>(allocator_), &in);
  api->SessionGetOutputName(static_cast<OrtSession*>(sface_), 0,
                            static_cast<OrtAllocator*>(allocator_), &out);
  if (in) sface_in_name_ = in;
  if (out) sface_out_name_ = out;

  // The models ship in several input resolutions (YuNet exists as 320x320 and
  // 640x640). Query each graph's real NCHW input size instead of assuming one:
  // feeding a wrongly sized blob makes OrtApi::Run fail outright, which used to
  // silently yield zero detections.
  yunet_input_size_ = 640;
  if (!ReadInputSize(static_cast<OrtSession*>(yunet_), &yunet_input_size_))
    yunet_input_size_ = 640;
  if (!ReadInputSize(static_cast<OrtSession*>(sface_), &sface_input_size_))
    sface_input_size_ = 112;
  if (yunet_input_size_ <= 0) yunet_input_size_ = 640;
  if (sface_input_size_ <= 0) sface_input_size_ = 112;
  FLOG("[init] yunet_input=%d sface_input=%d\n", yunet_input_size_,
       sface_input_size_);

  ready_ = true;
  return true;
}

// Reads the spatial size of input 0 assuming an NCHW layout. Returns false for
// dynamic/unknown dimensions, in which case the caller keeps its default.
bool FaceEngine::ReadInputSize(void* session, int* size) const {
  const OrtApi* api = static_cast<const OrtApi*>(api_);
  OrtTypeInfo* type_info = nullptr;
  if (api->SessionGetInputTypeInfo(static_cast<OrtSession*>(session), 0,
                                   &type_info) != nullptr)
    return false;
  const OrtTensorTypeAndShapeInfo* tensor_info = nullptr;
  bool ok = false;
  if (api->CastTypeInfoToTensorInfo(type_info, &tensor_info) == nullptr &&
      tensor_info != nullptr) {
    size_t dims_count = 0;
    api->GetDimensionsCount(tensor_info, &dims_count);
    if (dims_count == 4) {
      std::vector<int64_t> shape(dims_count);
      api->GetDimensions(tensor_info, shape.data(), dims_count);
      if (shape[2] > 0 && shape[3] > 0 && shape[2] == shape[3]) {
        *size = static_cast<int>(shape[2]);
        ok = true;
      } else {
        FLOG("[init] non-square or dynamic input dims: [%lld,%lld,%lld,%lld]\n",
             static_cast<long long>(shape[0]), static_cast<long long>(shape[1]),
             static_cast<long long>(shape[2]), static_cast<long long>(shape[3]));
      }
    }
  }
  api->ReleaseTypeInfo(type_info);
  return ok;
}

std::vector<float> FaceEngine::RunSession(
    void* session, const std::string& in_name, const std::string& out_name,
    const std::vector<float>& input, const int64_t* in_dims,
    size_t in_dims_count, std::vector<int64_t>& out_shape) const {
  const OrtApi* api = static_cast<const OrtApi*>(api_);
  std::vector<float> result;
  OrtValue* input_tensor = nullptr;
  size_t data_len = input.size() * sizeof(float);
  FLOG("[run] in=%s size=%zu dims=[", in_name.c_str(), input.size());
  for (size_t i = 0; i < in_dims_count; ++i)
    FLOG("%lld,", static_cast<long long>(in_dims[i]));
  FLOG("]\n");
  OrtStatus* st_create = api->CreateTensorWithDataAsOrtValue(
      static_cast<OrtMemoryInfo*>(mem_info_), const_cast<float*>(input.data()),
      data_len, in_dims, in_dims_count, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
      &input_tensor);
  if (st_create != nullptr) {
    FLOG("[run] CreateTensor FAILED: code=%d msg=%s\n",
         api->GetErrorCode(st_create), api->GetErrorMessage(st_create));
    api->ReleaseStatus(st_create);
    return result;
  }
  FLOG("[run] tensor ok\n");

  OrtRunOptions* run_opts = nullptr;
  api->CreateRunOptions(&run_opts);

  const char* in_names[1] = {in_name.c_str()};
  const char* out_names[1] = {out_name.c_str()};
  OrtValue* output_tensor = nullptr;
  OrtStatus* st_run =
      api->Run(static_cast<OrtSession*>(session), run_opts, in_names,
               &input_tensor, 1, out_names, 1, &output_tensor);
  if (st_run != nullptr) {
    FLOG("[run] Run FAILED for '%s': code=%d msg=%s\n", in_name.c_str(),
         api->GetErrorCode(st_run), api->GetErrorMessage(st_run));
    api->ReleaseStatus(st_run);
    api->ReleaseValue(input_tensor);
    if (run_opts) api->ReleaseRunOptions(run_opts);
    return result;
  }
  FLOG("[run] run ok\n");

  OrtTensorTypeAndShapeInfo* shape_info = nullptr;
  api->GetTensorTypeAndShape(output_tensor, &shape_info);
  size_t dims_count = 0;
  api->GetDimensionsCount(shape_info, &dims_count);
  out_shape.resize(dims_count);
  api->GetDimensions(shape_info, out_shape.data(), dims_count);
  size_t total = 1;
  for (int64_t d : out_shape) total *= static_cast<size_t>(d);
  FLOG("[run] out=%s dims=%zu total=%zu\n", out_name.c_str(), dims_count, total);

  const float* out_data = nullptr;
  void* mutable_data = nullptr;
  api->GetTensorMutableData(output_tensor, &mutable_data);
  out_data = static_cast<const float*>(mutable_data);
  if (out_data) {
    result.assign(out_data, out_data + total);
  }
  api->ReleaseTensorTypeAndShapeInfo(shape_info);
  api->ReleaseValue(output_tensor);
  api->ReleaseValue(input_tensor);
  if (run_opts) api->ReleaseRunOptions(run_opts);
  return result;
}

std::vector<float> FaceEngine::PreprocessYuNet(const uint8_t* rgb, int w, int h) const {
  // Square-pad the image (top-left) to max(w, h), then resize isotropically to
  // the model's input size. BGR planes, no mean, no scaling. Empirically this
  // beats OpenCV's anisotropic stretch on low-res photos (the stretch distorts
  // faces and measurably lowers detection confidence).
  const int k = yunet_input_size_;
  const int side = std::max(w, h);
  std::vector<uint8_t> square(static_cast<size_t>(side) * side * 3, 0);
  for (int y = 0; y < h; ++y) {
    for (int x = 0; x < w; ++x) {
      const uint8_t* p = rgb + (static_cast<size_t>(y) * w + x) * 3;
      uint8_t* q = square.data() + (static_cast<size_t>(y) * side + x) * 3;
      q[0] = p[0];
      q[1] = p[1];
      q[2] = p[2];
    }
  }
  std::vector<uint8_t> resized;
  ResizeRGB(square.data(), side, side, k, k, resized);

  std::vector<float> blob(static_cast<size_t>(1) * 3 * k * k);
  for (int y = 0; y < k; ++y) {
    for (int x = 0; x < k; ++x) {
      for (int c = 0; c < 3; ++c) {
        float v = resized[static_cast<size_t>(y) * k * 3 + x * 3 + c];
        blob[(c * k + y) * k + x] = v;
      }
    }
  }
  // RGB -> BGR in place: swap planes 0 and 2.
  for (int i = 0; i < k * k; ++i) std::swap(blob[i], blob[2 * k * k + i]);
  return blob;
}

std::vector<float> FaceEngine::ExtractEmbedding(const uint8_t* rgb, int w, int h,
                                               const float* landmarks) {
  // Align the face using the 5 detected landmarks (similarity transform to the
  // canonical 112x112 template). Alignment is essential for SFace accuracy -
  // feeding a raw, unaligned bbox instead produces near-random embeddings.
  const int crop = sface_input_size_;
  // The reference landmarks above describe the canonical 112x112 layout; scale
  // them if the model takes a different resolution.
  std::vector<float> ref(kRefLandmarks, kRefLandmarks + 10);
  if (crop != 112) {
    const float s = static_cast<float>(crop) / 112.0f;
    for (float& v : ref) v *= s;
  }

  float M[6];
  SimilarityTransform(landmarks, ref.data(), M);
  std::vector<uint8_t> aligned;
  WarpAffineRGB(rgb, w, h, M, crop, crop, aligned);
  if (aligned.size() != static_cast<size_t>(crop) * crop * 3) return {};
#ifdef JINGER_FACE_DEBUG
  // Optional offline dump of the aligned crop for visual verification.
  if (const char* dir = std::getenv("JINGER_FACE_ALIGNED")) {
    static int seq = 0;
    char path[512];
    std::snprintf(path, sizeof(path), "%s_%03d.rgb", dir, seq++);
    FILE* fp = std::fopen(path, "wb");
    if (fp) {
      std::fwrite(aligned.data(), 1, aligned.size(), fp);
      std::fclose(fp);
    }
  }
#endif  // JINGER_FACE_DEBUG

  const int k = crop;
  std::vector<float> blob(static_cast<size_t>(1) * 3 * k * k);
  // aligned is RGB; the model expects BGR (channel c -> 2-c).
  // This SFace ONNX applies its own input normalization inside the graph, so
  // the pixels must be fed RAW (0..255). Feeding the OpenCV-demo-style
  // (v-127.5)/127.5 collapses every embedding to near-identical vectors
  // (verified empirically: all pairwise cosines ~0.97 vs a healthy spread).
  for (int y = 0; y < k; ++y) {
    for (int x = 0; x < k; ++x) {
      for (int c = 0; c < 3; ++c) {
        const float v =
            aligned[static_cast<size_t>(y) * k * 3 + x * 3 + (2 - c)];
        blob[(c * k + y) * k + x] = v;
      }
    }
  }
  int64_t in_dims[4] = {1, 3, k, k};
  std::vector<int64_t> out_shape;
  std::vector<float> out = RunSession(sface_, sface_in_name_, sface_out_name_,
                                      blob, in_dims, 4, out_shape);
  if (out.empty()) return out;
  // L2-normalize.
  double sum = 0.0;
  for (float v : out) sum += static_cast<double>(v) * v;
  const float norm = static_cast<float>(std::sqrt(sum) + 1e-9);
  for (float& v : out) v /= norm;
  return out;
}

std::vector<FaceDetection> FaceEngine::Detect(const uint8_t* rgb, int w, int h) {
  std::vector<FaceDetection> faces;
  if (!ready_ || !rgb || w <= 0 || h <= 0) return faces;

  const int k = yunet_input_size_;
  std::vector<float> input = PreprocessYuNet(rgb, w, h);
  int64_t in_dims[4] = {1, 3, k, k};

  // YuNet (as consumed by OpenCV FaceDetectorYN) exposes 12 raw heads:
  // cls_{8,16,32}, obj_{8,16,32}, bbox_{8,16,32}, kps_{8,16,32}. Run them all
  // in one shot and decode exactly like OpenCV does.
  std::vector<std::vector<float>> outs(12);
  {
    std::vector<const char*> out_names(12);
    out_names[0] = yunet_out_names_[0].c_str();
    for (int i = 1; i < 12; ++i) out_names[i] = yunet_out_names_[i].c_str();
    const char* in_name = yunet_in_name_.c_str();
    const OrtApi* api = static_cast<const OrtApi*>(api_);
    OrtValue* in_tensor = nullptr;
    if (api->CreateTensorWithDataAsOrtValue(
            static_cast<OrtMemoryInfo*>(mem_info_),
            const_cast<float*>(input.data()),
            input.size() * sizeof(float), in_dims, 4,
            ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
            &in_tensor) != nullptr)
      return faces;
    OrtValue* out_tensors[12] = {nullptr};
    OrtStatus* st = api->Run(static_cast<OrtSession*>(yunet_), nullptr,
                             &in_name, &in_tensor, 1, out_names.data(), 12,
                             out_tensors);
    if (st != nullptr) {
      FLOG("[detect] Run FAILED: %s\n", api->GetErrorMessage(st));
      api->ReleaseStatus(st);
      api->ReleaseValue(in_tensor);
      return faces;
    }
    for (int i = 0; i < 12; ++i) {
      void* data = nullptr;
      if (out_tensors[i] &&
          api->GetTensorMutableData(out_tensors[i], &data) == nullptr && data) {
        OrtTensorTypeAndShapeInfo* info = nullptr;
        api->GetTensorTypeAndShape(out_tensors[i], &info);
        size_t total = 1;
        if (info) {
          size_t nd = 0;
          api->GetDimensionsCount(info, &nd);
          std::vector<int64_t> dims(nd);
          api->GetDimensions(info, dims.data(), nd);
          for (int64_t d : dims) total *= static_cast<size_t>(d);
          api->ReleaseTensorTypeAndShapeInfo(info);
        }
        const float* f = static_cast<const float*>(data);
        outs[i].assign(f, f + total);
      }
      if (out_tensors[i]) api->ReleaseValue(out_tensors[i]);
    }
    api->ReleaseValue(in_tensor);
  }

  // Decode exactly like cv::FaceDetectorYNImpl::postProcess.
  // OpenCV's default score threshold is 0.9; we default lower for recall on
  // small/blurry faces (offline tuning only, via JINGER_FACE_THRESH).
  const float kScoreThreshold = 0.40f;
#ifdef JINGER_FACE_DEBUG
  if (const char* t = std::getenv("JINGER_FACE_THRESH")) {
    kScoreThreshold = static_cast<float>(std::atof(t));
  }
#endif
  const float kNmsThreshold = 0.3f;     // OpenCV default
  struct RawBox {
    float x, y, w, h, score;
    float lm[10];
  };
  std::vector<RawBox> proposals;
  const int strides[3] = {8, 16, 32};
  for (int s = 0; s < 3; ++s) {
    const int stride = strides[s];
    const int cols = k / stride;
    const std::vector<float>& cls = outs[s];
    const std::vector<float>& obj = outs[3 + s];
    const std::vector<float>& bbox = outs[6 + s];
    const std::vector<float>& kps = outs[9 + s];
    if (cls.empty() || obj.empty() || bbox.empty() || kps.empty()) continue;
    const size_t anchors = cls.size();
    const float imgScale = static_cast<float>(std::max(w, h)) / k;
    for (int r = 0; r < cols; ++r) {
      for (int c = 0; c < cols; ++c) {
        const size_t idx = static_cast<size_t>(r) * cols + c;
        if (idx >= anchors) continue;
        float cs = std::min(std::max(cls[idx], 0.f), 1.f);
        float os = std::min(std::max(obj[idx], 0.f), 1.f);
        const float score = std::sqrt(cs * os);
        if (score < kScoreThreshold) continue;
        const float cx = (c + bbox[idx * 4 + 0]) * stride;
        const float cy = (r + bbox[idx * 4 + 1]) * stride;
        const float bw = std::exp(bbox[idx * 4 + 2]) * stride;
        const float bh = std::exp(bbox[idx * 4 + 3]) * stride;
        RawBox rb;
        // Map from blob space back to source-image space (isotropic: the image
        // was square-padded, so one scale fits both axes).
        rb.x = (cx - bw * 0.5f) * imgScale;
        rb.y = (cy - bh * 0.5f) * imgScale;
        rb.w = bw * imgScale;
        rb.h = bh * imgScale;
        rb.score = score;
        for (int n = 0; n < 5; ++n) {
          rb.lm[2 * n] = (kps[idx * 10 + 2 * n] + c) * stride * imgScale;
          rb.lm[2 * n + 1] = (kps[idx * 10 + 2 * n + 1] + r) * stride * imgScale;
        }
        proposals.push_back(rb);
      }
    }
  }
  FLOG("[detect] img=%dx%d proposals=%zu\n", w, h, proposals.size());

  // Greedy NMS on (x, y, w, h).
  std::sort(proposals.begin(), proposals.end(),
            [](const RawBox& a, const RawBox& b) { return a.score > b.score; });
  std::vector<char> suppressed(proposals.size(), 0);
  for (size_t i = 0; i < proposals.size(); ++i) {
    if (suppressed[i]) continue;
    for (size_t j = i + 1; j < proposals.size(); ++j) {
      if (suppressed[j]) continue;
      const float ix1 = std::max(proposals[i].x, proposals[j].x);
      const float iy1 = std::max(proposals[i].y, proposals[j].y);
      const float ix2 = std::min(proposals[i].x + proposals[i].w,
                                 proposals[j].x + proposals[j].w);
      const float iy2 = std::min(proposals[i].y + proposals[i].h,
                                 proposals[j].y + proposals[j].h);
      const float iw = std::max(0.f, ix2 - ix1);
      const float ih = std::max(0.f, iy2 - iy1);
      const float inter = iw * ih;
      const float uni = proposals[i].w * proposals[i].h +
                        proposals[j].w * proposals[j].h - inter;
      if (uni > 0 && inter / uni > kNmsThreshold) suppressed[j] = 1;
    }
  }

  for (size_t i = 0; i < proposals.size(); ++i) {
    if (suppressed[i]) continue;
    const RawBox& rb = proposals[i];
    float x = rb.x, y = rb.y, bw = rb.w, bh = rb.h;
    if (bw <= 0 || bh <= 0) continue;
    // clamp to image
    if (x < 0) { bw += x; x = 0; }
    if (y < 0) { bh += y; y = 0; }
    if (x + bw > w) bw = static_cast<float>(w) - x;
    if (y + bh > h) bh = static_cast<float>(h) - y;
    if (bw <= 0 || bh <= 0) continue;

    FaceDetection f;
    f.x = x;
    f.y = y;
    f.w = bw;
    f.h = bh;
    f.score = rb.score;
    f.embedding = ExtractEmbedding(rgb, w, h, rb.lm);
    FLOG("[detect] kept box=(%0.f,%0.f,%0.f,%0.f) score=%f emb=%zu\n", x, y, bw,
         bh, rb.score, f.embedding.size());
    if (!f.embedding.empty()) {
#ifdef JINGER_FACE_DEBUG
      // Optional offline crop dump for visual verification.
      if (const char* dir = std::getenv("JINGER_FACE_CROPS")) {
        double sx = 0, sy = 0;
        for (int n = 0; n < 5; ++n) {
          sx += rb.lm[2 * n];
          sy += rb.lm[2 * n + 1];
        }
        const int cx = static_cast<int>(sx / 5.0);
        const int cy = static_cast<int>(sy / 5.0);
        const int side = 96;
        static int seq = 0;
        char path[512];
        std::snprintf(path, sizeof(path), "%s_%03d_s%.2f.rgb", dir, seq++,
                      rb.score);
        FILE* fp = std::fopen(path, "wb");
        if (fp) {
          for (int yy = 0; yy < side; ++yy) {
            for (int xx = 0; xx < side; ++xx) {
              const int px = std::min(std::max(cx + xx - side / 2, 0), w - 1);
              const int py = std::min(std::max(cy + yy - side / 2, 0), h - 1);
              std::fwrite(rgb + (static_cast<size_t>(py) * w + px) * 3, 1, 3, fp);
            }
          }
          std::fclose(fp);
        }
      }
#endif  // JINGER_FACE_DEBUG
      faces.push_back(std::move(f));
    }
  }
  return faces;
}

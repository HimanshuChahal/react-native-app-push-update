#include <jni.h>
#include <string>
#include <android/log.h>
#include "bspatch.h"
#include "bzlib.h"
#include <fstream>
#include <vector>

#define LOG_TAG "PatcherJNI"
#define LOGI(...) _android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS_)
#define LOGE(...) _android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS_)

struct PatchInput {
    std::ifstream file;
};

static int read_patch(const struct bspatch_stream* stream, void* buffer, int length) {
    PatchInput* input = reinterpret_cast<PatchInput*>(stream->opaque);
    if (!input->file.read(reinterpret_cast<char*>(buffer), length)) {
        // Return number of bytes actually read (could be less than requested)
        return static_cast<int>(input->file.gcount());
    }
    return length;
}

static int64_t offtin(const unsigned char *buf) {
    int64_t y = buf[7] & 0x7F;
    for (int i = 6; i >= 0; i--) {
        y <<= 8;
        y += buf[i];
    }
    if (buf[7] & 0x80)
        y = -y;
    return y;
}

int64_t readNewFileSize(const std::string &patchPath) {
    std::ifstream f(patchPath, std::ios::binary);
    if (!f)
        return -1;

    unsigned char header[32];
    if (!f.read(reinterpret_cast<char *>(header), 32))
        return -1;

    // Validate the magic header
    if (memcmp(header, "ENDSLEY/BSDIFF43", 16) != 0) {
        LOGE("Invalid BSDIFF header magic");
        return -2;
    }

    int64_t ctrlBlockLen = offtin(header + 16);
    int64_t diffBlockLen = offtin(header + 24);
    int64_t newSize = offtin(header + 32);

    LOGE("ctrlBlockLen: %lld, diffBlockLen: %lld, newSize: %lld",
         (long long)ctrlBlockLen,
         (long long)diffBlockLen,
         (long long)newSize);

    return newSize;
}

std::vector<uint8_t> readFile(const char* path) {
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file) return {};
    std::streamsize size = file.tellg();
    file.seekg(0, std::ios::beg);
    std::vector<uint8_t> buffer(size);
    if (!file.read(reinterpret_cast<char*>(buffer.data()), size)) return {};
    return buffer;
}

extern "C"
JNIEXPORT jint JNICALL
Java_com_apppushupdate_NativeBridge_applyPatch(
        JNIEnv *env,
        jobject /* this */,
        jstring oldPath_, jstring patchPath_, jstring outputPath_) {

    const char* oldPath = env->GetStringUTFChars(oldPath_, nullptr);
    const char* patchPath = env->GetStringUTFChars(patchPath_, nullptr);
    const char* outputPath = env->GetStringUTFChars(outputPath_, nullptr);

    const auto release_resources = [&]() {
        env->ReleaseStringUTFChars(oldPath_, oldPath);
        env->ReleaseStringUTFChars(patchPath_, patchPath);
        env->ReleaseStringUTFChars(outputPath_, outputPath);
    };

    LOGI("Applying patch %s + %s -> %s", oldPath, patchPath, outputPath);

    auto oldData = readFile(oldPath);
    if (oldData.empty()) {
        LOGE("Failed to read old file");
        release_resources();
        return -1;
    }

    FILE* pf = fopen(patchPath, "rb");
    if (!pf) {
        LOGE("Cannot open patch file");
        release_resources();
        return -2;
    }

    char header[16];
    if (fread(header, 1, 16, pf) != 16 || memcmp(header, "ENDSLEY/BSDIFF43", 16) != 0) {
        LOGE("Invalid patch header");
        fclose(pf);
        release_resources();
        return -3;
    }

    uint8_t sizeBuf[8];
    if (fread(sizeBuf, 1, 8, pf) != 8) {
        LOGE("Failed to read new size");
        fclose(pf);
        release_resources();
        return -4;
    }
    int64_t newSize = offtin(sizeBuf);
    LOGI("New file size read from patch: %lld", (long long)newSize);

    int bz2err;
    BZFILE* bz2 = BZ2_bzReadOpen(&bz2err, pf, 0, 0, nullptr, 0);
    if (bz2 == nullptr) {
        LOGE("BZ2_bzReadOpen failed, bz2err=%d", bz2err);
        fclose(pf);
        release_resources();
        return -5;
    }

    auto bz2_read = [](const struct bspatch_stream* stream, void* buffer, int length) -> int {
        int bz2err;
        BZ2_bzRead(&bz2err, (BZFILE*)stream->opaque, buffer, length);
        return bz2err == BZ_OK || bz2err == BZ_STREAM_END ? 0 : -1;
    };

    struct bspatch_stream stream{};
    stream.read = bz2_read;
    stream.opaque = bz2;

    LOGI("Starting patch apply...");
    LOGI("Old file size: %zu", oldData.size());
    LOGI("Expected new file size: %lld", (long long)newSize);

    std::vector<uint8_t> newData(newSize);

    int result = bspatch(oldData.data(), oldData.size(),
                         newData.data(), newSize,
                         &stream);

    BZ2_bzReadClose(&bz2err, bz2);
    fclose(pf);

    LOGI("Starting patch apply...");
    LOGI("Old file size: %zu", oldData.size());
    LOGI("Expected new file size: %lld", (long long)newSize);

    if (result != 0) {
        LOGE("Patch failed with code %d", result);
        release_resources();
        return -5;
    }

    // ---- Step 7: Write output file ----
    std::ofstream outFile(outputPath, std::ios::binary);
    if (!outFile) {
        LOGE("Failed to write output file");
        release_resources();
        return -6;
    }
    outFile.write(reinterpret_cast<const char*>(newData.data()), newSize);
    LOGI("Patched output written successfully");

    release_resources();
    return 0;
}

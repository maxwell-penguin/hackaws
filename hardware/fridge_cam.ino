/*
 * PantryFlow — ESP32-CAM fridge zone camera firmware
 * ---------------------------------------------------
 * Freenove ESP32-CAM (OV2640, AI-Thinker pinout).
 *
 * Behavior:
 *   DEMO_MODE = 1  -> capture on button press (for judging)
 *   DEMO_MODE = 0  -> "production" mode: auto-capture every 12h
 *
 * On trigger: flash LED (GPIO 4), capture a JPEG, POST it as
 * multipart/form-data to /api/fridge-photos with a `zoneId` field
 * so the backend routes the photo to the right fridge zone.
 *
 * Flash with Arduino IDE: Board = "AI Thinker ESP32-CAM" (or ESP32 Dev
 * Module with 4MB flash), Flash Mode = QIO, Flash Size = 4MB, Partition
 * = Huge APP, PSRAM = Enabled, Flash Speed 80MHz.
 */

#include "esp_camera.h"
#include <WiFi.h>
#include <HTTPClient.h>
#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"
#include <vector>
#include <string>

// =========================== CONFIG — EDIT THESE ===========================
#define WIFI_SSID       "YOUR_WIFI_SSID"
#define WIFI_PASS       "YOUR_WIFI_PASSWORD"
#define ENDPOINT_URL    "https://YOUR_API_HOST/api/fridge-photos"

// Distinct per physical board. Must match a fridgeZone value in Strapi.
#define ZONE_ID         "top-shelf"   // e.g. "top-shelf", "door", "produce-bin"

// DEMO_MODE = 1 (button trigger) is the default for judging.
// Set to 0 to enable the 12-hour "production" auto-capture timer.
#define DEMO_MODE       1

// Button: wire a momentary push button between this pin and GND (INPUT_PULLUP).
// NOTE: do NOT use GPIO 0 — it is the camera's XCLK on the AI-Thinker board.
// GPIO 12/13/14 are free when the microSD slot is unused (default here).
#define BTN_PIN         12
#define FLASH_LED_PIN   4           // Freenove / AI-Thinker ESP32-CAM flash LED
#define CAPTURE_INTERVAL_MS (12UL * 60UL * 60UL * 1000UL)  // 12 hours
// ===========================================================================

// ---- Camera pinout: CAMERA_MODEL_AI_THINKER (Freenove ESP32-CAM) ----------
#define PWDN_GPIO_NUM   32
#define RESET_GPIO_NUM  -1
#define XCLK_GPIO_NUM   0
#define SIOD_GPIO_NUM   26
#define SIOC_GPIO_NUM   27
#define Y9_GPIO_NUM     35
#define Y8_GPIO_NUM     34
#define Y7_GPIO_NUM     39
#define Y6_GPIO_NUM     36
#define Y5_GPIO_NUM     21
#define Y4_GPIO_NUM     19
#define Y3_GPIO_NUM     18
#define Y2_GPIO_NUM     5
#define VSYNC_GPIO_NUM  25
#define HREF_GPIO_NUM   23
#define PCLK_GPIO_NUM   22

// ---- multipart constants ---------------------------------------------------
static const char* BOUNDARY = "----PantryFlowCamBoundary";

void logStep(const char* msg) {
  Serial.println(msg);
}

bool setupWiFi() {
  logStep("[wifi] connecting...");
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  int tries = 0;
  while (WiFi.status() != WL_CONNECTED && tries < 40) {
    delay(500);
    Serial.print(".");
    tries++;
  }
  Serial.println();
  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("[wifi] connected, IP: %s\n", WiFi.localIP().toString().c_str());
    return true;
  }
  logStep("[wifi] FAILED to connect");
  return false;
}

bool setupCamera() {
  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer   = LEDC_TIMER_0;
  config.pin_d0       = Y2_GPIO_NUM;
  config.pin_d1       = Y3_GPIO_NUM;
  config.pin_d2       = Y4_GPIO_NUM;
  config.pin_d3       = Y5_GPIO_NUM;
  config.pin_d4       = Y6_GPIO_NUM;
  config.pin_d5       = Y7_GPIO_NUM;
  config.pin_d6       = Y8_GPIO_NUM;
  config.pin_d7       = Y9_GPIO_NUM;
  config.pin_xclk     = XCLK_GPIO_NUM;
  config.pin_pclk     = PCLK_GPIO_NUM;
  config.pin_vsync    = VSYNC_GPIO_NUM;
  config.pin_href     = HREF_GPIO_NUM;
  config.pin_sccb_sda = SIOD_GPIO_NUM;
  config.pin_sccb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn     = PWDN_GPIO_NUM;
  config.pin_reset    = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;
  config.pixel_format = PIXFORMAT_JPEG;
  config.frame_size   = FRAMESIZE_SVGA;   // 800x600 — plenty for Claude vision, small POST
  config.jpeg_quality = 12;               // lower = better quality, larger file
  config.fb_count     = 1;

#if defined(CONFIG_SPIRAM_SUPPORT) || defined(CONFIG_ESP32_SPIRAM_SUPPORT)
  config.fb_location = CAMERA_FB_IN_PSRAM;
  config.grab_mode   = CAMERA_GRAB_LATEST;
#endif

  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("[camera] init FAILED: 0x%x\n", err);
    return false;
  }
  logStep("[camera] initialized");
  return true;
}

bool captureAndPost() {
  if (WiFi.status() != WL_CONNECTED) {
    logStep("[wifi] disconnected — reconnecting...");
    setupWiFi();
    if (WiFi.status() != WL_CONNECTED) return false;
  }

  // Flash the LED for consistent lighting, give it a beat to stabilize.
  digitalWrite(FLASH_LED_PIN, HIGH);
  delay(200);
  logStep("[capture] flashing LED + capturing...");

  camera_fb_t* fb = esp_camera_fb_get();
  if (!fb) {
    logStep("[capture] FAILED to get frame");
    digitalWrite(FLASH_LED_PIN, LOW);
    return false;
  }
  Serial.printf("[capture] JPEG captured: %u bytes\n", fb->len);

  // Build multipart/form-data body:
  //   --boundary
  //   Content-Disposition: form-data; name="image"; filename="fridge.jpg"
  //   Content-Type: image/jpeg
  //
  //   <jpeg bytes>
  //   --boundary
  //   Content-Disposition: form-data; name="zoneId"
  //
  //   <zone id>
  //   --boundary--
  std::vector<uint8_t> body;
  std::string part1 = "--" BOUNDARY
      "\r\nContent-Disposition: form-data; name=\"image\"; filename=\"fridge.jpg\""
      "\r\nContent-Type: image/jpeg\r\n\r\n";
  body.insert(body.end(), part1.begin(), part1.end());
  body.insert(body.end(), fb->buf, fb->buf + fb->len);
  std::string part2 = "\r\n--" BOUNDARY
      "\r\nContent-Disposition: form-data; name=\"zoneId\"\r\n\r\n"
      ZONE_ID
      "\r\n--" BOUNDARY "--\r\n";
  body.insert(body.end(), part2.begin(), part2.end());

  esp_camera_fb_return(fb);
  digitalWrite(FLASH_LED_PIN, LOW);

  logStep("[post] uploading to " ENDPOINT_URL "...");
  HTTPClient http;
  WiFiClient client;
  http.begin(client, ENDPOINT_URL);
  http.addHeader("Content-Type", "multipart/form-data; boundary=" BOUNDARY);
  http.setTimeout(20000);

  int code = http.POST(body.data(), body.size());
  if (code > 0) {
    Serial.printf("[post] response code: %d\n", code);
    String resp = http.getString();
    if (resp.length() > 200) resp = resp.substring(0, 200);
    Serial.printf("[post] body (truncated): %s\n", resp.c_str());
  } else {
    Serial.printf("[post] FAILED, error: %s\n", http.errorToString(code).c_str());
  }
  http.end();
  return code >= 200 && code < 300;
}

void setup() {
  Serial.begin(115200);
  delay(300);
  logStep("=== PantryFlow ESP32-CAM booting ===");

  // Avoid brownout resets when the flash LED draws current.
  WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);

  pinMode(FLASH_LED_PIN, OUTPUT);
  digitalWrite(FLASH_LED_PIN, LOW);
  pinMode(BTN_PIN, INPUT_PULLUP);

  setupWiFi();
  setupCamera();

#if DEMO_MODE
  logStep("[mode] DEMO — press the button to capture");
#else
  logStep("[mode] PRODUCTION — auto-capture every 12h");
#endif
}

void loop() {
#if DEMO_MODE
  // Button press = trigger. Pullup + active-low; debounce lightly.
  static uint32_t lastPress = 0;
  if (digitalRead(BTN_PIN) == LOW && (millis() - lastPress) > 1000) {
    lastPress = millis();
    logStep("[trigger] button pressed");
    captureAndPost();
  }
  delay(50);
#else
  static uint32_t lastCapture = 0;
  if (millis() - lastCapture >= CAPTURE_INTERVAL_MS) {
    lastCapture = millis();
    logStep("[trigger] 12h timer elapsed");
    captureAndPost();
  }
  delay(1000);
#endif
}

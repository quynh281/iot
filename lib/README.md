<<<<<<< HEAD
# 🌿 Smart Garden – Hệ Thống Tưới Cây Thông Minh

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-blue?logo=flutter" />
  <img src="https://img.shields.io/badge/ESP32-IoT-green?logo=espressif" />
  <img src="https://img.shields.io/badge/SQLite-local--db-lightgrey?logo=sqlite" />
  <img src="https://img.shields.io/badge/Telegram-Bot-blue?logo=telegram" />
  <img src="https://img.shields.io/badge/Open--Meteo-Weather%20API-orange" />
  <img src="https://img.shields.io/badge/license-MIT-green" />
</p>

---

## Mục lục

1. [Thông tin chung](#1-thông-tin-chung)
2. [Giới thiệu đề tài](#2-giới-thiệu-đề-tài)
3. [Các chức năng chính](#3-các-chức-năng-chính)
4. [Kiến trúc hệ thống](#4-kiến-trúc-hệ-thống)
5. [Công nghệ sử dụng](#5-công-nghệ-sử-dụng)
6. [Yêu cầu môi trường](#6-yêu-cầu-môi-trường)
7. [Hướng dẫn cài đặt và chạy](#7-hướng-dẫn-cài-đặt-và-chạy)
8. [Cấu trúc thư mục](#8-cấu-trúc-thư-mục)
9. [Cơ sở dữ liệu](#9-cơ-sở-dữ-liệu)
10. [Mô hình gợi ý thích ứng](#10-mô-hình-gợi-ý-thích-ứng)
11. [API & Tài liệu kỹ thuật](#11-api--tài-liệu-kỹ-thuật)
12. [Kiểm thử](#12-kiểm-thử)
13. [Triển khai](#13-triển-khai)
14. [Giao diện minh hoạ](#14-giao-diện-minh-hoạ)
15. [Tài liệu liên quan](#15-tài-liệu-liên-quan)
16. [Lời cảm ơn](#16-lời-cảm-ơn)
17. [Trích dẫn](#17-trích-dẫn)
18. [Liên hệ](#18-liên-hệ)

---

## 1. Thông tin chung

| Mục | Thông tin |
|-----|-----------|
| **Tên đề tài** | Xây dựng hệ thống điều khiển tưới tiêu thông minh trên nền tảng IoT |
| **Trường** | [Trường Đại học Sư phạm - Đại học Đà Nẵng] |
| **Khoa | [Khoa Toán - Tin] |
| **Môn học** | [Khóa luận tốt nghiệp] |
| **Học kỳ** | [Học kỳ 2] |
| **Năm học** | 2025 – 2026 |

### Thành viên nhóm

| STT | Họ và tên | MSSV | Vai trò |
|-----|-----------|------|---------|
| 1 | [Lê Thị Như Quỳnh] | [3120222112] | |

> **Giáo viên hướng dẫn:** [TS. Nguyễn Trần Quốc Vinh]

---

## 2. Giới thiệu đề tài

**Smart Garden** là hệ thống tưới cây thông minh kết hợp phần cứng ESP32 và ứng dụng di động Flutter. Hệ thống cho phép người dùng theo dõi thời gian thực các thông số môi trường (nhiệt độ, độ ẩm không khí, độ ẩm đất), điều khiển bơm nước thủ công hoặc tự động, lập lịch tưới và nhận cảnh báo qua Telegram.

### Mục tiêu

- Tự động hóa việc tưới cây dựa trên dữ liệu cảm biến thực tế.
- Tích hợp dự báo thời tiết để tránh tưới lãng phí khi trời sắp mưa.
- Lưu trữ lịch sử dữ liệu cục bộ, hỗ trợ xuất báo cáo CSV.
- Khi **offline** (chỉ kết nối WiFi ESP32) hoạt động trên webserver, khi **online** (có internet đầy đủ) hoạt động trên app flutter.

### Phạm vi

Đề tài tập trung vào việc xây dựng ứng dụng mobile Flutter kết nối trực tiếp với ESP32 qua HTTP, không yêu cầu server trung gian. Phù hợp với môi trường vườn nhà, chậu cây trong nhà, hoặc nông nghiệp quy mô nhỏ.

---

## 3. Các chức năng chính

### 3.1 Giám sát môi trường (Real-time)
- Hiển thị **nhiệt độ**, **độ ẩm không khí** cập nhật mỗi 2 giây.
- Theo dõi **3 cảm biến độ ẩm đất** (Soil 1, 2, 3) kèm giá trị RAW.
- Hiển thị Max/Min trong phiên làm việc.
- Trạng thái môi trường: Nóng / Lạnh / Bình thường; Ẩm cao / Khô / Bình thường.

### 3.2 Điều khiển bơm
- Điều khiển **3 máy bơm** độc lập (bật/tắt thủ công).
- **Kịch bản nhanh**: Tưới tất cả / Tắt tất cả.
- Hỗ trợ chế độ **Manual** và **Auto**.

### 3.3 Tưới tự động (Auto Watering)
- Khi độ ẩm đất xuống dưới ngưỡng, hệ thống tự bật bơm trong **2 phút** rồi tự tắt.

### 3.4 Lập lịch tưới (Schedule)
- Thêm, bật/tắt, xoá lịch tưới theo giờ/phút cho từng bơm.
- Cài đặt thời lượng tưới từ 1–60 phút.
- Gửi lịch trực tiếp lên ESP32 qua HTTP.
- Tự động **bỏ qua lịch** nếu dự báo thời tiết có mưa (≥ 70%).

### 3.5 Dự báo thời tiết & cảnh báo mưa
- Tích hợp **Open-Meteo API** để lấy xác suất mưa 3 giờ tới.
- Cảnh báo khi xác suất mưa ≥ 70%, tránh tưới lãng phí.
- Hỏi xác nhận trước khi bật bơm nếu trời sắp mưa.

### 3.6 Thông báo & Telegram
- Push thông báo nội bộ khi: đất khô, nhiệt độ cao, lịch bị hủy do mưa.
- Gửi cảnh báo qua **Telegram Bot** (cần internet).
- Lưu toàn bộ lịch sử thông báo, hỗ trợ xóa từng mục hoặc xóa tất cả.

### 3.7 Thống kê & Xuất báo cáo
- Biểu đồ đường (Line Chart) nhiệt độ và độ ẩm không khí.
- Thống kê tổng thời gian chạy từng bơm trong ngày.
- Lịch sử bật/tắt bơm với thời lượng từng lần.
- **Xuất CSV** dữ liệu sensor và pump log (hôm nay / 7 ngày / 30 ngày / toàn bộ).

### 3.8 Hỗ trợ Offline / Online
- **Offline**: Điều khiển ESP32 bình thường, bỏ qua weather/Telegram
- **Online**: Đầy đủ tính năng, tự fetch lại thời tiết khi có internet trở lại.
---

## 4. Kiến trúc hệ thống

```
┌─────────────────────────────────────────────────────────┐
│                   Flutter Mobile App                    │
│                                                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────┐ │
│  │ HomePage │  │ Schedule │  │Statistics│  │ Config │ │
│  └──────────┘  └──────────┘  └──────────┘  └────────┘ │
│                                                         │
│  ┌─────────────────────┐   ┌──────────────────────────┐│
│  │   DatabaseHelper    │   │   SharedPreferences      ││
│  │   (SQLite local)    │   │   (IP, city, token...)   ││
│  └─────────────────────┘   └──────────────────────────┘│
└────────────────┬────────────────────┬───────────────────┘
                 │ HTTP (WiFi LAN)    │ HTTPS (Internet)
        ┌────────▼────────┐  ┌────────▼──────────────────┐
        │   ESP32 Device  │  │  External APIs            │
        │                 │  │  - Open-Meteo (weather)   │
        │ - DHT sensor    │  │  - Telegram Bot           │
        │ - Soil sensors  │  │  - Geocoding API          │
        │ - 3 Relay pumps │  └───────────────────────────┘
        └─────────────────┘
```

**Luồng dữ liệu chính:**

1. Flutter poll ESP32 mỗi **2 giây** qua `GET /data` → parse JSON → cập nhật UI.
2. Người dùng bấm toggle → `GET /toggle?r={index}` → cập nhật trạng thái bơm.
3. Mỗi 30 giây → lưu sensor vào SQLite.
4. Mỗi 5 giây → kiểm tra schedule → tự kích hoạt bơm nếu đúng giờ.
5. Mỗi 10 giây (Auto mode) → kiểm tra sensor mapping → tự tưới nếu đất khô.
6. Mỗi 30 phút → fetch dự báo mưa từ Open-Meteo.

---

## 5. Công nghệ sử dụng

| Thành phần | Công nghệ | Phiên bản |
|-----------|-----------|-----------|
| **Mobile App** | Flutter / Dart | 3.x |
| **Vi điều khiển** | ESP32 (Arduino framework) | – |
| **Cơ sở dữ liệu** | SQLite (sqflite) | 2.x |
| **Local storage** | SharedPreferences | – |
| **HTTP Client** | dart:http | – |
| **Biểu đồ** | fl_chart | – |
| **Xuất CSV** | csv package | – |
| **Thời tiết** | Open-Meteo API (miễn phí) | – |
| **Geocoding** | Open-Meteo Geocoding API | – |
| **Thông báo** | Telegram Bot API | – |
| **Cảm biến** | DHT22 (temp/hum), Capacitive Soil Sensor | – |
| **Relay** | Module relay 4 kênh | – |

---

## 6. Yêu cầu môi trường

### Thiết bị di động
- Android 6.0 (API 23) trở lên **hoặc** iOS 12 trở lên.
- Kết nối WiFi (cùng mạng với ESP32 **hoặc** mạng có internet).

### Máy tính phát triển
- Flutter SDK >= 3.0.0
- Dart SDK >= 3.0.0
- Android Studio / VS Code
- Android SDK (build-tools, platform-tools)

### Phần cứng ESP32
- ESP32 DevKit (hoặc tương đương)
- 1x DHT22 (nhiệt độ & độ ẩm không khí)
- 3x Cảm biến độ ẩm đất (capacitive)
- 1x Module relay 3 kênh (5V)
- 3x Máy bơm mini (3–5V hoặc 12V tùy relay)
- Nguồn cấp phù hợp

### Tùy chọn (để dùng tính năng Online)
- Kết nối Internet trên điện thoại
- Telegram Bot Token + Chat ID

---

## 7. Hướng dẫn cài đặt và chạy

### 7.1 Clone repo

```bash
git clone https://github.com/[username]/smart-garden.git
cd smart-garden
```

### 7.2 Cài dependencies Flutter

```bash
flutter pub get
```

### 7.3 Chạy ứng dụng

```bash
# Kiểm tra thiết bị kết nối
flutter devices

# Chạy debug
flutter run

# Build APK release
flutter build apk --release
```

### 7.4 Nạp firmware ESP32

1. Mở thư mục `esp32_firmware/` bằng Arduino IDE hoặc PlatformIO.
2. Cài đặt thư viện: `DHT sensor library`, `ArduinoJson`, `WiFi`, `WebServer`.
3. Sửa thông tin WiFi trong `firmware.ino`:
```cpp
const char* ssid     = "TEN_WIFI_CUA_BAN";
const char* password = "MAT_KHAU_WIFI";
```
4. Upload lên ESP32, mở Serial Monitor để lấy địa chỉ IP.

### 7.5 Cấu hình ứng dụng

1. Mở app → vào tab **Cấu hình (⚙️)**.
2. Nhập **IP ESP32** (lấy từ Serial Monitor).
3. Nhập **Thành phố** (để lấy tọa độ dự báo thời tiết).
4. *(Tùy chọn)* Nhập **Telegram Bot Token** và **Chat ID**.
5. Nhấn **LƯU CẤU HÌNH**.

---

## 8. Cấu trúc thư mục

```
smart-garden/
├── lib/
│   ├── main.dart                 # Entry point, navigation
│   ├── home_page.dart            # Màn hình chính – giám sát & điều khiển
│   ├── schedule_page.dart        # Lập lịch tưới
│   ├── statistics_page.dart      # Thống kê & biểu đồ
│   ├── notification_page.dart    # Lịch sử thông báo
│   ├── config_page.dart          # Cấu hình hệ thống
│   └── database_helper.dart      # SQLite singleton helper
├── esp32_firmware/
│   └── firmware.ino              # Code Arduino ESP32
├── assets/
│   └── ...                       # Icons, images
├── pubspec.yaml                  # Dependencies
└── README.md
```

---

## 9. Cơ sở dữ liệu

Ứng dụng dùng **SQLite cục bộ** (file `iot.db`) thông qua package `sqflite`. Hiện tại DB version **3**.

### Sơ đồ bảng

```
sensor                    pump_log
──────────────────        ──────────────────────
id       INTEGER PK       id       INTEGER PK
temp     REAL             pump     INTEGER
hum      REAL             start    TEXT (datetime)
soil1    INTEGER          end      TEXT (datetime, nullable)
soil2    INTEGER
soil3    INTEGER
time     TEXT (datetime)

schedule                  sensor_pump_map
──────────────────────    ──────────────────────
id         INTEGER PK     id         INTEGER PK
pump       INTEGER        sensor_id  TEXT
hour       INTEGER        pump       INTEGER
minute     INTEGER        threshold  INTEGER
duration   INTEGER
is_enabled INTEGER (0/1)

config                    notification
──────────────────        ──────────────────────
id      INTEGER PK        id       INTEGER PK
min     REAL              title    TEXT
max     REAL              content  TEXT
notify  INTEGER           time     TEXT (datetime)

sensor_config
──────────────────────
id         INTEGER PK
name       TEXT
created_at TEXT
```

### Chính sách lưu trữ

- Dữ liệu sensor được lưu **mỗi 30 giây**.
- Tự động **xóa dữ liệu cũ hơn 7 ngày** (sensor, notification, pump_log đã kết thúc) khi gọi `cleanupOldData()`.
- DB tự migrate qua `onUpgrade` khi nâng version.

---

## 10. Mô hình gợi ý thích ứng

Hệ thống sử dụng cơ chế **gợi ý tưới thích ứng** dựa trên rule-based kết hợp dữ liệu thời tiết thực tế:

### Nguyên lý hoạt động

```
[Độ ẩm đất hiện tại]
        │
        ▼
  ≤ threshold?  ──No──► Không làm gì
        │
       Yes
        │
        ▼
 [Kiểm tra thời tiết]
        │
   Mưa ≥ 50%? ──Yes──► Bỏ qua, gửi cảnh báo
        │
        No
        │
        ▼
 [Bật bơm tương ứng]
        │
   Sau 2 phút
        │
        ▼
 [Tắt bơm tự động]
```

### Thông số thích ứng

| Tham số | Mô tả | Cấu hình |
|---------|-------|----------|
| `threshold` | Ngưỡng độ ẩm đất bật bơm (%) | Cấu hình per-sensor qua sensor_pump_map |
| `moistureMin` | Ngưỡng thấp cảnh báo đất khô (%) | Cài trong Config page |
| `moistureMax` | Ngưỡng tắt cảnh báo (%) | Cài trong Config page |
| Rain threshold | Xác suất mưa tối thiểu để hủy tưới | Cố định 50% |
| Watering duration | Thời gian tưới mỗi lần auto | Cố định 2 phút |

### Mở rộng

Hiện tại mô hình dùng **rule-based đơn giản**. Có thể mở rộng bằng cách tích hợp học máy (TFLite) để dự đoán lịch tưới tối ưu dựa trên chuỗi dữ liệu lịch sử sensor.

---

## 11. API & Tài liệu kỹ thuật

### ESP32 HTTP Endpoints

| Method | Endpoint | Mô tả | Response |
|--------|----------|-------|----------|
| `GET` | `/data` | Lấy toàn bộ dữ liệu sensor & trạng thái relay | JSON |
| `GET` | `/toggle?r={0\|1\|2}` | Bật/tắt relay (index 0-based) | `200 OK` |
| `GET` | `/mode?m={manual\|auto}` | Chuyển chế độ điều khiển | `200 OK` |
| `GET` | `/addSchedule?pump=&hour=&minute=&duration=` | Thêm lịch tưới | `200 OK` |

### Cấu trúc JSON từ `/data`

```json
{
  "temp": 28.5,
  "hum": 65.0,
  "soil1": 45,
  "soil2": 38,
  "soil3": 72,
  "soil1_raw": 2100,
  "soil2_raw": 2350,
  "soil3_raw": 1800,
  "r1": false,
  "r2": false,
  "r3": true,
  "sensors": [
    { "id": "A1", "value": 45, "raw": 2100, "status": "ok" },
    { "id": "A2", "value": 38, "raw": 2350, "status": "ok" },
    { "id": "A3", "value": 72, "raw": 1800, "status": "error" }
  ]
}
```

### External APIs

**Open-Meteo – Dự báo mưa**
```
GET https://api.open-meteo.com/v1/forecast
  ?latitude={lat}&longitude={lon}
  &hourly=precipitation_probability
  &forecast_days=1
  &timezone=auto
```

**Open-Meteo – Geocoding**
```
GET https://geocoding-api.open-meteo.com/v1/search
  ?name={city}&count=1&language=vi&format=json
```

**Telegram – Gửi tin nhắn**
```
POST https://api.telegram.org/bot{TOKEN}/sendMessage
Body: { chat_id, text }
```

---

## 12. Kiểm thử

### 12.1 Kiểm thử thủ công

| Chức năng | Kịch bản | Kết quả mong đợi |
|-----------|----------|-----------------|
| Fetch dữ liệu | ESP32 online, poll 2s | Dữ liệu cập nhật liên tục |
| Toggle pump | Nhấn Pump 1 | Relay 1 bật/tắt, UI cập nhật |
| Auto watering | Soil ≤ threshold | Bơm tự bật, tắt sau 2 phút |
| Schedule | Đúng giờ đã cài | Bơm tự kích hoạt |
| Rain alert | Mưa ≥ 50% | Hỏi xác nhận trước khi bật |
| Offline mode | Tắt WiFi điện thoại | Vẫn điều khiển ESP32 bình thường |
| Export CSV | Chọn 7 ngày | File CSV lưu vào Downloads |

### 12.2 Kiểm thử kết nối

| Trạng thái | Hành vi kỳ vọng |
|-----------|-----------------|
| Online (đủ kết nối) | Tất cả tính năng hoạt động |
| Offline (WiFi ESP32 only) | Điều khiển OK, weather/Telegram bị tắt, banner thông báo |
| Timeout request | Xử lý exception, retry sau poll tiếp theo |

---

## 13. Triển khai

### Yêu cầu triển khai thực tế

1. **ESP32** nạp firmware, cấp nguồn, kết nối cùng mạng WiFi với điện thoại.
2. **App Android**: Build APK release và cài trực tiếp.
3. **Không cần server**: App giao tiếp thẳng với ESP32 qua LAN – không cần backend hay cloud.

### Build APK

```bash
flutter build apk --release --split-per-abi
# Output: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

### Lưu ý triển khai

- Đảm bảo điện thoại và ESP32 **cùng mạng WiFi**.
- Nếu ESP32 dùng **Access Point mode** (IP mặc định `192.168.4.1`), điện thoại cần kết nối trực tiếp vào WiFi của ESP32 → mất internet → offline chỉ hoạt động trên webserver.
- Dữ liệu SQLite lưu **cục bộ trên điện thoại**, không đồng bộ đa thiết bị.

---

## 14. Giao diện minh hoạ

> *(Thêm ảnh chụp màn hình vào đây)*

| Màn hình chính | Lập lịch | Thống kê | Cấu hình |
|:-:|:-:|:-:|:-:|
| ![home](docs/screenshots/home.png) | ![schedule](docs/screenshots/schedule.png) | ![stats](docs/screenshots/stats.png) | ![config](docs/screenshots/config.png) |

---

## 15. Tài liệu liên quan

- [Flutter Documentation](https://docs.flutter.dev)
- [ESP32 Arduino Core](https://github.com/espressif/arduino-esp32)
- [sqflite package](https://pub.dev/packages/sqflite)
- [fl_chart package](https://pub.dev/packages/fl_chart)
- [Open-Meteo API Docs](https://open-meteo.com/en/docs)
- [Telegram Bot API](https://core.telegram.org/bots/api)
- [DHT Sensor Library](https://github.com/adafruit/DHT-sensor-library)

---

## 16. Lời cảm ơn

Chúng tôi xin gửi lời cảm ơn chân thành đến:

- **[Tên GVHD]** đã hướng dẫn, định hướng và hỗ trợ trong suốt quá trình thực hiện đề tài.
- Khoa **[Tên khoa]** – Trường **[Tên trường]** đã tạo điều kiện cho nhóm hoàn thành đồ án.
- Cộng đồng **Flutter**, **ESP32 Arduino** và các tác giả của các package open-source đã được sử dụng trong dự án.

---

## 17. Trích dẫn

Nếu bạn sử dụng hoặc tham khảo dự án này, vui lòng trích dẫn:

```
[Tên nhóm]. (2025). Smart Garden – Hệ thống tưới cây thông minh.
Đồ án môn [Tên môn], [Tên trường].
GitHub: https://github.com/[username]/smart-garden
```

**Các nguồn tham khảo chính:**

[1] Espressif Systems. *ESP32 Technical Reference Manual*. https://www.espressif.com/en/support/documents/technical-documents

[2] Open-Meteo. *Free Weather API*. https://open-meteo.com

[3] Flutter Team. *Flutter – Build apps for any screen*. https://flutter.dev

[4] Adafruit Industries. *DHT Sensor Library*. https://github.com/adafruit/DHT-sensor-library

---

## 18. Liên hệ

| Thành viên | Email | GitHub |
|-----------|-------|--------|
| [Tên thành viên 1] | [email@example.com] | [@username] |
| [Tên thành viên 2] | [email@example.com] | [@username] |
| [Tên thành viên 3] | [email@example.com] | [@username] |

> Nếu có câu hỏi hoặc muốn đóng góp, vui lòng mở [Issue](https://github.com/[username]/smart-garden/issues) hoặc gửi [Pull Request](https://github.com/[username]/smart-garden/pulls).

---

<p align="center">Made with ❤️ by Smart Garden Team · 2025</p>
=======
# iot

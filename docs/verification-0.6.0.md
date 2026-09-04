# Orca Battery Guardian 0.6.0 Verification

ตรวจเมื่อ 4 กันยายน 2026 บน Apple Silicon และ macOS 26.0.1

## Build and tests

- `swift build`: ผ่าน
- `swift test`: ผ่าน 80 tests
- `swift test -c release`: ผ่าน 80 tests
- ตรวจไฟล์ `Localizable.strings` ด้วย `plutil`: ผ่านทั้ง English และไทย
- ทดสอบข้อความสถานะไทย การจำภาษาที่เลือก และการ register ฟอนต์ Sarabun: ผ่าน

## Installed app

- ติดตั้งและเปิดจาก `/Applications/OrcaBatteryGuardian.app`
- Version `0.6.0`, build `6`
- ตรวจลายเซ็นด้วย `codesign --verify --deep --strict`: ผ่าน
- ภายใน app bundle มีภาษา `en`/`th`, Sarabun Regular/Medium/SemiBold/Bold และไฟล์ OFL
- แอปทำงานเป็น process จาก `/Applications` หลังติดตั้ง
- หลังปล่อยผ่านรอบ refresh 30 วินาที ไม่พบ SwiftUI runtime issue เพิ่มเติม

## Live battery check

- `batt` daemon ตอบกลับและรองรับ charging control
- ช่วงที่ยืนยันจาก daemon: 50-80%
- ก่อนติดตั้งเครื่องใช้ไฟจาก AC ที่ 82% และไม่ได้ชาร์จ; ตอนตรวจรอบสุดท้าย Adapter ถูกถอดและเครื่องใช้ Battery Power ที่ 79%
- การติดตั้งรุ่นนี้ไม่ได้ reset benchmark หรือเปลี่ยนช่วงชาร์จที่ตั้งไว้

## Remaining checks

- ควรทดสอบการสลับภาษาและการตัดบรรทัดบน macOS 13, 15 และ 26 เพิ่มเติม
- Activity เก่าจะแสดงตามภาษาที่ใช้ตอนบันทึก ส่วนรายการใหม่ใช้ภาษาปัจจุบัน
- ยังต้องเก็บข้อมูล Benchmark หลายสัปดาห์จึงจะเห็นแนวโน้ม capacity ที่มีความหมาย

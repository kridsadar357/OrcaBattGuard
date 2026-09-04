# Orca Battery Guardian 0.8.0 Verification

ตรวจเมื่อ 4 กันยายน 2026 บน Apple Silicon และ macOS 26.0.1

## Build and tests

- `swift test`: ผ่าน 92 tests
- `swift build -c release --triple x86_64-apple-macosx13.0`: ผ่าน
- Intel CLI slice รันผ่าน Rosetta และอ่านข้อมูล IOKit ได้
- Intel diagnostics รายงาน Monitoring Mode และไม่เรียก `batt`
- native charge limit ถูกปิดบน Intel แม้ใช้ macOS รุ่นที่ใหม่กว่าขอบเขตที่รองรับ

## Universal app

- Version `0.8.0`, build `8`
- Release packaging สร้าง `arm64` และ `x86_64` แล้วรวมด้วย `lipo`
- ตรวจ architecture ของทั้ง GUI executable และ bundled CLI ด้วย `lipo -archs`
- ตรวจ app bundle และ nested CLI ด้วย `codesign --verify --deep --strict`

## Capability boundary

- Apple Silicon: รองรับ monitoring และใช้ `batt` เมื่อ daemon ยืนยัน charging-control capability
- Intel x86_64: รองรับ GUI, Menu Bar, notifications, history, benchmark, export, Simulation และ CLI
- Intel x86_64: hardware charge control และ Calibration เป็น Monitor Only
- ไม่มี direct SMC/BCLM write เพิ่มเข้ามาในรุ่นนี้

## Remaining checks

- ควรเปิด GUI และทดสอบ sleep/wake, launch at login และ battery telemetry บน Intel MacBook จริง
- ค่า temperature, health และ capacity บน Intel อาจต่างกันตามรุ่นและข้อมูลที่ IOKit เปิดให้

# Orca Battery Guardian 0.9.0 Verification

ตรวจเมื่อ 4 กันยายน 2026 บน Apple Silicon และ macOS 26.0.1

## Build and tests

- `swift test`: ผ่าน 102 tests
- `swift test -c release`: ผ่าน
- `swift build -c release --triple x86_64-apple-macosx13.0`: ผ่าน
- Intel CLI slice รันผ่าน Rosetta และอ่านข้อมูล IOKit ได้
- สคริปต์ติดตั้ง/ถอน Intel helper ผ่าน syntax check

## Intel controller

- macOS 13/14 ใช้ BCLM backend และรับค่าเพดาน 50-100%
- อ่านค่าจริงก่อนส่งคำสั่ง และอ่านกลับหลังเขียนทุกครั้ง
- ไม่รายงาน verified เมื่อคำสั่งล้มเหลว, timeout หรือ readback ไม่ตรง
- helper เป็น root-owned wrapper ที่รับเฉพาะ `read` และ `write <50...100>`
- ปิด Battery Protection หรือถอน helper แล้วคืน BCLM เป็น 100%
- macOS 15 ขึ้นไปไม่ส่งคำสั่งเขียน BCLM และไม่ขอให้ผู้ใช้ปิด SIP
- BCLM ไม่มี lower/resume threshold แยก จึงให้ SMC และ macOS ตัดสินใจเริ่มชาร์จ

## Universal app

- Version `0.9.0`, build `9`
- Release packaging สร้าง `arm64` และ `x86_64` แล้วรวมด้วย `lipo`
- ตรวจ architecture ของทั้ง GUI executable และ bundled CLI ด้วย `lipo -archs`
- ตรวจ app bundle และ nested CLI ด้วย `codesign --verify --deep --strict`

## Remaining checks

- ยังต้องติดตั้ง `bclm` และ helper บน Intel MacBook ที่ใช้ macOS 13/14 เพื่อยืนยันการเขียน SMC จริง
- ควรทดสอบ sleep/wake, launch at login และการคืนค่า 100% บน Intel hardware
- การ cross-build, Rosetta และ unit tests ยืนยันโค้ดกับเส้นทางคำสั่ง แต่ใช้แทนการทดสอบ SMC จริงไม่ได้

# Orca Battery Guardian 0.7.0 Verification

ตรวจเมื่อ 4 กันยายน 2026 บน Apple Silicon และ macOS 26.0.1

## Build and tests

- `swift test`: ผ่าน 90 tests
- `swift test -c release`: ผ่าน 90 tests
- ครอบคลุม Calibration capability/readback, update version comparison, Activity export และ startup recovery
- ตรวจ `Localizable.strings` ด้วย `plutil`: ผ่านทั้ง English และไทย
- ตรวจว่า key ภาษาไทยครบตามที่ UI เรียกใช้ และฟอนต์ Sarabun โหลดได้

## Packaging

- Version `0.7.0`, build `7`
- ติดตั้งและเปิดจาก `/Applications/OrcaBatteryGuardian.app`
- Release build มีทั้งแอปและ CLI แบบ read-only ที่ `Contents/MacOS/orca-battery`
- ตรวจ app bundle และ nested CLI ด้วย `codesign --verify --deep --strict`
- ตรวจคำสั่ง CLI สำหรับ status, diagnostics, calibration status, history export, benchmark export และ update check
- หลังเปิดผ่านรอบ refresh ไม่พบ error หรือ fault ของโปรเซสใน system log
- GitHub repository ยังไม่มี published release; update checker แสดงสถานะนี้แทนการแจ้งว่าเชื่อมต่อล้มเหลว

## Live battery safety

- `batt` client และ daemon ตอบกลับ พร้อม charging control และ Calibration capability
- ช่วงชาร์จจริงก่อนแพ็กคือ 50-80% และ Calibration อยู่ในสถานะ Idle
- ไม่ได้เริ่ม Calibration, force discharge หรือเปลี่ยนช่วงชาร์จระหว่างการทดสอบ
- GUI สั่ง Calibration ผ่าน `batt` เท่านั้น และยอมรับผลสำเร็จเมื่ออ่านสถานะกลับมาตรงกับคำสั่ง
- update checker เรียก GitHub Releases API เท่านั้น ไม่ดาวน์โหลดหรือรันไฟล์จากเครือข่าย

## Remaining checks

- ควรทดสอบเปิดต่อเนื่องหลายวัน รวม restart และ sleep/wake หลายรอบ
- ควรทดสอบ GUI ภาษาไทย/อังกฤษบน macOS 13, 15 และ 26 เพิ่มเติม
- Calibration จริงควรทดสอบแยกบนเครื่องทดสอบที่เสียบไฟ เปิดฝา และปิด sleep ตลอดกระบวนการ
- Benchmark ต้องเก็บหลายสัปดาห์จึงจะใช้ดูแนวโน้ม capacity ได้อย่างมีความหมาย

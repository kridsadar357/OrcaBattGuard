<p align="center">
  <img src="Sources/OrcaBatteryGuardian/Resources/orca-mascot.png" alt="Orca using a MacBook" width="140">
</p>

# Orca Battery Guardian

Orca Battery Guardian เป็นแอปเล็ก ๆ บน Menu Bar สำหรับดูแลการชาร์จ MacBook ผมทำขึ้นมาเพราะไม่อยากปล่อยให้เครื่องเสียบสายและค้างอยู่ที่ 100% ตลอดวัน แต่ก็ไม่อยากได้แอปที่มีหน้าต่างใหญ่หรือเมนูซับซ้อน

ตัวแอปเขียนด้วย Swift และ SwiftUI แสดงเปอร์เซ็นต์แบต แหล่งจ่ายไฟ อุณหภูมิ สุขภาพแบต และจำนวนรอบชาร์จเท่าที่ macOS อ่านได้ พร้อมตั้งช่วงชาร์จที่ต้องการจากหน้าเดียว

**เวอร์ชัน 0.4.0 (Beta) · macOS 13 ขึ้นไป · รองรับ Apple Silicon เป็นหลัก**

> การจำกัดการชาร์จจริงใช้ [batt](https://github.com/charlie0129/batt) ซึ่งต้องติดตั้งแยก หากไม่มี `batt` แอปยังดูข้อมูลแบตได้ แต่จะไม่สามารถเปลี่ยน charge limit ให้เครื่อง

## หน้าตาแอป

ภาพเหล่านี้มาจากแอปที่รันจริงในเวอร์ชัน 0.2.0 ส่วนเวอร์ชัน 0.3.0 ปรับข้อความสถานะและการตรวจสอบ controller ให้ตรงกับเครื่องมากขึ้น

<table>
  <tr>
    <th>Overview</th>
    <th>Menu Bar</th>
  </tr>
  <tr>
    <td valign="top"><a href="docs/images/overview.png"><img src="docs/images/overview.png" alt="Orca Battery Guardian overview" width="420"></a></td>
    <td valign="top"><a href="docs/images/menu-bar.png"><img src="docs/images/menu-bar.png" alt="Orca Battery Guardian menu bar" width="420"></a></td>
  </tr>
  <tr>
    <th>Activity</th>
    <th>Settings</th>
  </tr>
  <tr>
    <td valign="top"><a href="docs/images/activity.png"><img src="docs/images/activity.png" alt="Orca Battery Guardian activity history" width="420"></a></td>
    <td valign="top"><a href="docs/images/settings.png"><img src="docs/images/settings.png" alt="Orca Battery Guardian settings" width="420"></a></td>
  </tr>
</table>

## ทำอะไรได้บ้าง

- ดูสถานะแบตได้จาก Menu Bar โดยไม่ต้องเปิด System Settings
- เลือกช่วงชาร์จสำเร็จรูป หรือกำหนดช่วงเอง
- หยุดเติมไฟเมื่อถึงเพดาน โดยไม่บังคับระบายแบตลงมา
- พักการชาร์จเมื่ออุณหภูมิสูง และยอมให้ชาร์จเมื่อแบตต่ำมาก
- เปิดพร้อมเครื่องและแจ้งเตือนเมื่อสถานะสำคัญเปลี่ยน
- เก็บประวัติการทำงานไว้ดูย้อนหลัง
- มี Simulation Mode สำหรับลองหน้าจอและ state machine โดยไม่ส่งคำสั่งไปที่ฮาร์ดแวร์
- สั่งชาร์จถึง 100% ชั่วคราว 1, 2 หรือ 4 ชั่วโมง แล้วกลับไปใช้โหมดเดิมเอง
- ตรวจ `batt`, daemon, charge limit และความเข้ากันได้จากหน้า Diagnostics

## โหมดการชาร์จ

| โหมด | เริ่มชาร์จ | หยุดชาร์จ | เหมาะกับ |
| --- | ---: | ---: | --- |
| Maximum Life | 50% | 70% | เครื่องที่เสียบ Adapter อยู่กับโต๊ะเป็นส่วนใหญ่ |
| Balanced | 50% | 80% | ใช้งานทั่วไป และเป็นค่าเริ่มต้นของแอป |
| Travel | 20% | 100% | วันที่ต้องการแบตเต็มก่อนออกไปข้างนอก |
| Custom | กำหนดเอง | กำหนดเอง | คนที่ต้องการตั้งช่วงให้เข้ากับการใช้งานของตัวเอง |

ในโหมด Custom ค่าเริ่มและหยุดต้องห่างกันอย่างน้อย 5% ส่วน Travel จะปิด charge limit แล้วปล่อยให้ macOS จัดการการชาร์จตามปกติ ไม่ได้บังคับให้แบตวิ่งระหว่าง 20-100%

### ตั้งไว้ 80% แต่ทำไมแบตยังอยู่ 100%

เพราะ Orca ไม่ได้สั่งให้เครื่องใช้แบตทั้งที่ยังเสียบสายอยู่ ถ้าเปิดใช้ตอนแบตเต็ม เครื่องอาจรับไฟจาก Adapter โดยที่เปอร์เซ็นต์ยังค้างอยู่แถวเดิมได้

ถ้าต้องการเห็นผลทันที ให้ถอดสายและใช้งานจนแบตลดลงมาใกล้ช่วงที่ตั้งไว้ แล้วค่อยเสียบกลับ แอปไม่มีโหมดบังคับ discharge เพราะไม่ต้องการเพิ่มรอบแบตโดยไม่จำเป็น

### ชาร์จเต็มชั่วคราว

กด `Charge to 100%` แล้วเลือกระยะเวลา 1, 2 หรือ 4 ชั่วโมง Orca จะจำโหมดเดิมไว้และนำกลับมาใช้เมื่อแบตเต็ม, หมดเวลา, ยกเลิก หรือ Quit แอป เวลาที่เลือกไว้ยังอยู่หลังปิดแล้วเปิดแอปใหม่หากยังไม่หมดอายุ

ฟังก์ชันนี้ใช้ได้เมื่อเปิด Battery Protection และใช้ controller ของ Orca หากกำลังใช้ Charge Limit ของ macOS ให้ใช้คำสั่ง `Charge to Full Now` จากเมนูแบตเตอรี่ของระบบแทน

## ติดตั้งสำหรับใช้งานบนเครื่องตัวเอง

ต้องมี Xcode หรือ Command Line Tools ที่รองรับ Swift 6 ก่อน จากนั้นรัน:

```sh
git clone https://github.com/kridsadar357/OrcaBattGuard.git
cd OrcaBattGuard
swift test
./Scripts/package-app.sh
./Scripts/install-app.sh
```

`package-app.sh` จะสร้าง Release build ไว้ที่ `build/OrcaBatteryGuardian.app` และเซ็นแบบ ad-hoc สำหรับเครื่องที่ build ส่วน `install-app.sh` จะติดตั้งไปที่ `/Applications` แล้วเปิดแอปให้ หากมีเวอร์ชันเก่าอยู่ สคริปต์จะรอให้แอปปิดและสำรองไฟล์เดิมก่อนแทนที่

ระหว่างพัฒนาสามารถรันตรงจาก Swift Package ได้:

```sh
swift run OrcaBatteryGuardian
```

การรันคำสั่งนี้ยังควบคุมแบตจริงได้หากพบ `batt` ถ้าต้องการลองโดยไม่แตะค่าของเครื่อง ให้เปิด Simulation Mode ก่อน

## เปิดใช้การควบคุมการชาร์จจริง

โปรเจกต์นี้ไม่ได้เขียนค่า SMC โดยตรงและไม่มี privileged helper ของตัวเอง การควบคุม charge limit จึงอาศัย `batt` ที่ติดตั้งแยกต่างหาก

```sh
brew install batt
sudo brew services start batt
batt status --json
```

เมื่อติดตั้งเรียบร้อย ให้เปิด Orca แล้วเลือกโหมดที่ต้องการ แอปจะอ่านค่ากลับจาก daemon ก่อนแสดงคำว่า `Charge limits verified` ถ้า daemon หยุดทำงาน ตอบช้า หรือค่าที่อ่านกลับมาไม่ตรง หน้าจอจะแสดงว่า controller ยังไม่ผ่านการยืนยันและจะลองใหม่ในรอบถัดไป

ตรวจสถานะด้วยตัวเองได้จาก:

```sh
batt status --json
pmset -g batt
```

คำว่า `Verified` หมายถึงช่วงชาร์จใน `batt` ตรงกับค่าที่เลือก ไม่ได้แปลว่ากระแสชาร์จหยุดในวินาทีนั้นทันที ควรดู Power, State และ charge rate ประกอบด้วย

### กลับไปใช้การชาร์จแบบปกติ

ปิด Battery Protection ในแอป หรือ Quit Orca แล้วรัน:

```sh
batt disable
batt status --json
```

การ Quit แอปอย่างเดียวไม่ได้หยุด daemon และไม่ได้ล้างค่าที่ `batt` เก็บไว้ ส่วน Simulation Mode จะไม่เปลี่ยนค่าเดิมของฮาร์ดแวร์

## แอปทำงานอย่างไร

Orca รับเหตุการณ์จาก macOS ทันทีเมื่อแหล่งจ่ายไฟหรือสถานะแบตเปลี่ยน และตรวจซ้ำทุก 30 วินาทีเผื่อเหตุการณ์ตกหล่น รวมถึงตรวจใหม่หลังเครื่องตื่นจาก sleep ถ้าช่วงชาร์จไม่ตรงกับโหมดที่เลือก แอปจะส่งคำสั่งแก้แล้วอ่านค่ากลับอีกครั้ง จะแสดงว่า verified ก็ต่อเมื่อค่าตรงกันจริง

คำสั่ง `batt` และ `pmset` ทำงานเบื้องหลัง จึงไม่ทำให้หน้าต่างแอปค้างระหว่างรอ daemon แต่ละคำสั่งมีเวลาให้ทำงานไม่เกิน 3 วินาที งานเก่าจะถูกยกเลิกเมื่อสลับโหมด และไม่อนุญาตให้มีคำสั่งควบคุมหลายชุดทำงานซ้อนกัน

แอปไม่ได้บังคับ discharge ระหว่างช่วงล่างกับช่วงบน ถ้าเครื่องใช้ไฟจาก Adapter และไม่ได้ชาร์จ สถานะจะเป็น `Holding` จนกว่าจะต้องเริ่มชาร์จอีกครั้ง

### อุณหภูมิและแบตต่ำ

ค่าเริ่มต้นของ Cooling Pause คือ 38 C และ Critical Low คือ 15% เมื่อเครื่องร้อน Orca จะลดเพดานชาร์จชั่วคราวแล้วคืนค่าเดิมเมื่ออุณหภูมิลดลง หากแบตต่ำกว่า Critical Low ระบบจะให้ความสำคัญกับการชาร์จก่อน

นี่เป็นเพียงเงื่อนไขเสริมในระดับแอป ไม่ใช่ระบบป้องกันความร้อน และไม่แทนที่การป้องกันที่ macOS หรือฮาร์ดแวร์มีอยู่แล้ว

## ประวัติการทำงาน

Activity เก็บเหตุการณ์สำคัญ เช่น การเปลี่ยนโหมด, controller ใช้งานไม่ได้, controller กลับมาทำงาน และการคืนค่า charge limit ไฟล์อยู่ที่:

```text
~/Library/Application Support/OrcaBatteryGuardian/history.json
```

แอปเก็บไม่เกิน 500 รายการหรือ 512 KiB โดยลบรายการเก่าที่สุดก่อน ไฟล์นี้อยู่ในเครื่องเท่านั้นและไม่ได้ถูกส่งออกไปที่ไหน หากอ่านหรือเขียนไฟล์ไม่ได้ จะมีคำเตือนในหน้า Activity แทนการเขียนทับไฟล์เดิมเงียบ ๆ

## สำหรับนักพัฒนา

โค้ดแยกส่วนอ่านแบต, state machine, charge controller, process runner และ history store ออกจากกัน เพื่อให้ทดสอบ logic ได้โดยไม่ต้องส่งคำสั่งไปที่แบตจริง และยังสามารถเปลี่ยน backend เป็น privileged helper ของโปรเจกต์เองได้ในอนาคต

```text
Sources/OrcaBatteryGuardian/
├── Models/
├── Resources/
├── Services/
└── UI/
```

รันเทสต์ได้ทั้ง Debug และ Release:

```sh
swift test
swift test -c release
```

ตอนนี้มี 64 tests ครอบคลุม state machine, timeout, cancellation, daemon failure, ค่าที่ถูกเปลี่ยนจากภายนอก, Temporary Full Charge, Cooling Hysteresis, Diagnostics, power-source events, Simulation Mode และการบันทึกประวัติ เทสต์ของ controller ใช้ข้อมูลจำลอง ไม่หยุด daemon และไม่เปลี่ยน charge limit ของเครื่อง

ผลตรวจรุ่นปัจจุบันอยู่ใน [verification report 0.4.0](docs/verification-0.4.0.md) และยังเปิดดู [รายงานรุ่น 0.3.0](docs/verification-0.3.0.md) ได้

## ข้อจำกัดตอนนี้

- ยังไม่ได้ทดสอบกับ MacBook และ macOS ครบทุกรุ่น
- ยังไม่ได้ทดสอบเปิดต่อเนื่องหลายวัน, restart และ sleep/wake หลายรอบ
- ยังใช้ `batt` เป็น backend ภายนอก ไม่ได้รวมตัวควบคุมมากับแอป
- ยังไม่มี automatic update, export history และกราฟย้อนหลัง
- Cooling Pause เป็น policy ของแอป ไม่ใช่ระบบรับรองความปลอดภัยด้านอุณหภูมิ

Orca ยังเป็น Beta ผมแนะนำให้เปิดดูสถานะเป็นระยะ โดยเฉพาะช่วงแรกที่ลองกับ Mac รุ่นใหม่ แอปช่วยจัดช่วงชาร์จได้ แต่ไม่ได้ซ่อมแบตที่เสื่อมแล้วและไม่สามารถรับประกันอายุแบตได้

## Contributors

- [Kridsadar (@kridsadar357)](https://github.com/kridsadar357)

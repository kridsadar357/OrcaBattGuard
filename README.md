<p align="center">
  <img src="Sources/OrcaBatteryGuardian/Resources/orca-mascot.png" alt="Orca using a MacBook" width="140">
</p>

# Orca Battery Guardian

แอปจัดการแบตเตอรี่ MacBook แบบ compact dashboard และ Menu Bar เขียนด้วย **Swift + SwiftUI** ออกแบบสำหรับ Apple Silicon เป็นหลัก มีมาสคอตออร์ก้าใช้ MacBook พร้อมสถานะแบตเตอรี่ที่ดูได้ระหว่างทำงาน

**Version 0.2.0 · Early Beta · macOS 13+ · Swift 6**

> แอปควบคุม charge limit จริงผ่าน [batt](https://github.com/charlie0129/batt) เมื่อมี daemon ที่ตั้งค่าและทำงานอยู่ หากไม่มี backend ที่พร้อมใช้งาน จะอ่านข้อมูลแบตเตอรี่ได้ แต่ไม่สามารถควบคุมการชาร์จจริงได้ รุ่นนี้ยังมีข้อจำกัดด้านความน่าเชื่อถือที่ระบุไว้ด้านล่าง และยังไม่ใช่ production release

## ภาพจากการใช้งานจริง

ภาพทั้ง 4 ภาพด้านล่างเป็น screenshot จากตัวแอปที่รันจริง ไม่ใช่ design mockup คลิกที่ภาพเพื่อดูขนาดเต็ม

<table>
  <tr>
    <th>Overview</th>
    <th>Menu Bar</th>
  </tr>
  <tr>
    <td valign="top"><a href="docs/images/overview.png"><img src="docs/images/overview.png" alt="Overview showing 90 percent battery, Balanced mode and a 50-80 percent target range" width="420"></a></td>
    <td valign="top"><a href="docs/images/menu-bar.png"><img src="docs/images/menu-bar.png" alt="Compact menu bar panel with the orca mascot, battery status and protection toggle" width="420"></a></td>
  </tr>
  <tr>
    <th>Activity</th>
    <th>Settings</th>
  </tr>
  <tr>
    <td valign="top"><a href="docs/images/activity.png"><img src="docs/images/activity.png" alt="Activity view showing a timestamped battery protection event" width="420"></a></td>
    <td valign="top"><a href="docs/images/settings.png"><img src="docs/images/settings.png" alt="Settings view with charge thresholds, safety limits, notifications, login and simulation options" width="420"></a></td>
  </tr>
</table>

ค่าที่เห็นเป็นสถานะ ณ เวลาถ่ายภาพ ไม่ใช่ค่าปัจจุบันของเครื่อง และข้อความอย่าง `Holding` เป็นผลจาก policy ของแอป ซึ่งในรุ่นนี้อาจไม่ตรงกับสถานะการชาร์จจริงทุกกรณี โดยเฉพาะเมื่อใช้ไฟจากแบตเตอรี่ ดูหัวข้อข้อจำกัดก่อนใช้งาน

## แอปช่วยอะไร

Orca ตั้งเป้าจำกัดการเติมไฟเข้าแบตเมื่อถึงระดับที่เลือก โดยไม่บังคับให้แบตขึ้นลงเป็นรอบทั้งวันที่เสียบ Adapter เหมาะกับผู้ใช้ที่ต้องการกำหนดช่วงชาร์จเองและดูสถานะจาก Menu Bar ได้สะดวก

- **Overview:** แสดง Battery %, power source, สถานะจาก policy, อุณหภูมิ, battery health และ cycle count เท่าที่ระบบให้ข้อมูล
- **Charge profiles:** เลือก Maximum Life, Balanced, Travel หรือกำหนด lower/upper threshold เอง
- **Menu Bar:** ไอคอนออร์ก้าพร้อมเปอร์เซ็นต์ และ panel ย่อสำหรับดูสถานะ เปิด dashboard, refresh หรือ quit
- **Safety policy:** critical-low override และ cooling pause ตามค่าที่ตั้งไว้
- **Activity:** แสดงเหตุการณ์เปลี่ยนสถานะพร้อมเวลา เก็บสูงสุด 60 รายการใน session ปัจจุบัน
- **Preferences:** สวิตช์ protection, notifications, launch at login และ simulation
- **Simulation:** อ่านข้อมูลจำลองและใช้ no-op controller โดยไม่ส่งคำสั่งจากข้อมูลจำลองไปยังฮาร์ดแวร์
- **Custom artwork:** mascot, Menu Bar icon และ macOS application icon รวมอยู่ในโปรเจกต์

แอปไม่ได้ซ่อมแบตเตอรี่ที่เสื่อมแล้ว ไม่รับประกันอายุแบต และไม่ได้แทนที่ระบบป้องกันแบตเตอรี่ของ macOS หรือฮาร์ดแวร์

## Charge Profiles

| Profile | Lower threshold | Upper threshold | การใช้งาน |
| --- | --- | --- | --- |
| Maximum Life | 50% | 70% | เพดานต่ำสำหรับการทำงานที่เสียบ Adapter เป็นหลัก |
| Balanced | 50% | 80% | ค่าเริ่มต้นสำหรับการใช้งานทั่วไป |
| Travel | 20% | 100% | เตรียมชาร์จเต็มก่อนนำเครื่องออกไปใช้งาน |
| Custom | ตั้งค่าเอง | ตั้งค่าเอง | กำหนดช่วงให้เหมาะกับการใช้งาน |

ชื่อโปรไฟล์เป็น preset ของแอป ไม่ใช่คำรับประกันผลต่ออายุแบตเตอรี่ ค่า Custom ถูกปรับให้อยู่ในช่วงที่รองรับ โดย upper ต้องสูงกว่า lower อย่างน้อย 5 จุดเปอร์เซ็นต์

**ข้อสำคัญของ Travel:** backend ปัจจุบันใช้ `batt disable` เมื่อ upper เป็น 100% จึงคืนการจัดการ charge limit ให้ระบบ ไม่ได้บังคับวงรอบชาร์จจริง 20-100%

## หลักการทำงาน

ตัวอย่าง Balanced 50-80% เมื่อมี Adapter และ backend พร้อมใช้งาน:

1. เมื่อต่ำกว่า lower threshold ระบบสามารถเริ่มชาร์จได้ตาม policy
2. เมื่อถึง upper threshold ตัวควบคุมจำกัดการชาร์จโดยไม่สั่งตัดไฟจาก Adapter
3. ระหว่าง threshold ทั้งสอง `batt` ใช้ hysteresis เพื่อคงสถานะชาร์จเดิม ไม่สลับเปิด/ปิดทุกครั้งที่เปอร์เซ็นต์เปลี่ยน
4. แอปอ่านข้อมูลและประเมิน policy โดยปกติทุก 5 วินาทีขณะทำงาน การเปลี่ยนสถานะที่รายงานโดย backend อาจมีความหน่วง

### ทำไมตั้ง 80% แล้วแบตยังอยู่ 100%

**หยุดชาร์จไม่เท่ากับบังคับระบายแบต** หากเริ่มใช้ Orca ตอนแบตเต็ม เครื่องยังรับพลังงานจาก Adapter ได้ จึงไม่จำเป็นต้องลดลงถึง 80% ทันที

สามารถถอดสาย ใช้งานแบตลงมาใกล้ช่วงเป้าหมาย แล้วเสียบกลับเพื่อสังเกตพฤติกรรม รุ่นนี้ยังไม่มี `Drain to Limit` และไม่บังคับ discharge อัตโนมัติ

### Safety Policy

- ค่าเริ่มต้น critical low คือ **15%** และ cooling pause คือ **38 C**
- ตรรกะปัจจุบันให้ critical-low override มาก่อน cooling pause หากเข้าเงื่อนไขทั้งสองพร้อมกัน
- Cooling pause ใช้การลด upper charge limit ชั่วคราวผ่าน `batt` แล้วคืนช่วงที่เลือกเมื่อพ้นเงื่อนไขร้อน ไม่ได้สั่งควบคุมพัดลมหรือระบายความร้อนให้เครื่อง
- ต้องมีแหล่งจ่ายไฟจึงจะชาร์จได้ และต้องมีแอปทำงานเพื่อประเมินอุณหภูมิใหม่ นี่เป็น policy ระดับแอป ไม่ใช่ระบบป้องกันอุณหภูมิที่รับประกันได้

## Requirements

- MacBook ที่ใช้ **Apple Silicon** สำหรับ backend ควบคุมชาร์จที่รองรับ รุ่น Intel ยังไม่ใช่เป้าหมายที่ยืนยันการรองรับ
- **macOS 13 ขึ้นไป** ตาม deployment target ของแพ็กเกจ ไม่ได้หมายความว่าทดสอบแล้วครบทุก macOS/รุ่นเครื่อง
- **Swift 6 toolchain** และ Xcode หรือ Command Line Tools ที่มี macOS SDK สำหรับ build
- [Homebrew](https://brew.sh/) และ `batt` หากต้องการควบคุม charge limit จริง
- สิทธิ์ผู้ดูแลระบบสำหรับตั้งค่า service ของ `batt` และสิทธิ์ Notifications/Login Items ตามที่ macOS กำหนด

## Build & Run

```sh
git clone https://github.com/kridsadar357/OrcaBattGuard.git
cd OrcaBattGuard
swift test
./Scripts/package-app.sh
open build/OrcaBatteryGuardian.app
```

สคริปต์สร้าง `build/OrcaBatteryGuardian.app` พร้อม resource bundle และ `AppIcon.icns` แล้วเซ็นแบบ ad-hoc สำหรับใช้งานในเครื่อง ปัจจุบันใช้ **Debug build** และยังไม่ได้ Developer ID signing หรือ notarization

สำหรับรันระหว่างพัฒนา:

```sh
swift run OrcaBatteryGuardian
```

การรันแบบนี้ยังอ่านแบตและอาจส่งคำสั่งควบคุมจริงได้หากพบ `batt` แต่ปิดการเรียก Notifications เพราะไม่ได้รันใน `.app` bundle ควรใช้ bundle เมื่อต้องการทดสอบพฤติกรรมแอป macOS รวมถึง launch at login

## เปิดใช้ Charge Control จริง

Orca ไม่ได้รวม privileged helper ของตัวเองหรือ binary ของ `batt` มาให้ แอปเรียก backend แยกผ่าน `ChargeControlling` และไม่ได้เขียนค่า SMC โดยตรง แต่การควบคุมฮาร์ดแวร์ของ `batt` ยังเป็นกลไก third-party ที่ไม่ใช่ public charge-control API ของ Apple

แนวทาง Homebrew สำหรับ `batt` 0.8.0 ที่ตรวจสอบกับโปรเจกต์นี้:

```sh
brew install batt
sudo brew services start batt
batt status
```

Homebrew ระบุว่า service ต้องทำงานด้วยสิทธิ์ root ก่อนใช้คำสั่งส่วนใหญ่ อ่าน [เอกสารของ batt](https://github.com/charlie0129/batt) เพิ่มเติมสำหรับสิทธิ์เข้าถึง daemon และการตั้งค่าที่ตรงกับเวอร์ชันที่ติดตั้ง อย่ารัน GUI ของ Orca ด้วย `sudo`

หลังตั้งค่า backend ให้เปิด Orca ใหม่แล้วเลือกโปรไฟล์ ตรวจแยกได้จาก:

```sh
batt status
pmset -g batt
```

ควรพิจารณาร่วมกันทั้ง upper/lower limit, สถานะอนุญาตชาร์จ, แหล่งจ่ายไฟ และ charge rate ไม่ใช้แค่คำว่า `Connected` หรือ `Holding` ใน UI เป็นหลักฐานเพียงอย่างเดียว

หากไม่มี `batt` แอปจะลองอ่าน `pmset -g battlimit` เป็น fallback เท่านั้น ไม่ใช้คำสั่งนี้เขียน charge limit และบาง macOS อาจไม่มีข้อมูลดังกล่าว

### หยุดใช้ Charge Limit

การปิดหน้าต่างยังเหลือ Menu Bar และการ Quit Orca **ไม่ได้หยุด daemon หรือคืนค่าของ batt ให้อัตโนมัติ** หากต้องการคืนการชาร์จปกติ ให้ Quit Orca ก่อน แล้วใช้:

```sh
batt disable
batt status
```

การเปิด Simulation ก็ไม่ล้าง limit เดิมที่ daemon ถืออยู่ เพียงหยุดส่งคำสั่งฮาร์ดแวร์จากการจำลอง

## โครงสร้างโปรเจกต์

```text
OrcaBattGuard/
├── Package.swift
├── Packaging/Info.plist
├── Scripts/package-app.sh
├── Sources/
│   ├── OrcaBatteryGuardianApp/OrcaBatteryGuardianApp.swift
│   └── OrcaBatteryGuardian/
│       ├── Models/BatteryModels.swift
│       ├── Resources/orca-mascot.png
│       ├── Services/
│       │   ├── BatteryDataProvider.swift
│       │   ├── ChargeController.swift
│       │   ├── GuardianEngine.swift
│       │   ├── GuardianStateMachine.swift
│       │   ├── NotificationService.swift
│       │   └── SettingsStore.swift
│       └── UI/
│           ├── ContentView.swift
│           └── OrcaMascotView.swift
├── Tests/OrcaBatteryGuardianTests/GuardianStateMachineTests.swift
└── docs/images/
    ├── overview.png
    ├── menu-bar.png
    ├── activity.png
    └── settings.png
```

`BatteryDataProviding` แยกข้อมูลจริงจากข้อมูลจำลอง, `GuardianStateMachine` ตัดสิน policy, `GuardianEngine` ประสานการอัปเดต และ `ChargeControlling` เป็นจุดแยกสำหรับ backend ปัจจุบันหรือ privileged helper ในอนาคต

## Tests

```sh
swift test
```

ชุดทดสอบปัจจุบันมี 5 กรณี: upper threshold, lower threshold, critical-low priority, cooling pause และการแปลงค่าอุณหภูมิจาก AppleSmartBattery ชุดนี้ไม่ได้สั่งเปลี่ยน charge limit ของเครื่อง และยังไม่ครอบคลุมความล้มเหลวหรือ lifecycle ของ daemon

## ข้อจำกัดและงานถัดไป

- **ยืนยันสถานะฮาร์ดแวร์:** cache ของคำสั่งอาจทำให้แสดงว่าพร้อมใช้งานหลังคำสั่งล้มเหลว หรือเมื่อมีการเปลี่ยนค่าจากภายนอก ยังต้องเพิ่มการตรวจผลจริงและ retry
- **ความลื่นไหลของ UI:** คำสั่ง backend ยังรอผลบน main thread และไม่มี timeout จึงอาจทำให้ GUI ค้างหาก backend ไม่ตอบ
- **ความตรงของข้อความสถานะ:** state machine ยังอาจแสดง `Holding` ทั้งที่กำลังชาร์จในช่วงกลาง หรือเมื่อเครื่องใช้แบตอยู่ ต้องแยกสถานะที่ต้องการออกจากสถานะที่วัดได้
- **ประวัติถาวร:** Activity ยังไม่เขียนลงดิสก์และหายเมื่อ Quit ไม่มี export log หรือกราฟย้อนหลัง
- **Sleep และ startup:** ยังต้องทดสอบ sleep/wake, restart, daemon recovery และ launch at login อย่างครอบคลุม ก่อนรับรองการทำงานแบบ unattended
- **ความปลอดภัยของ policy:** ยังต้องปรับการจัดลำดับ low-battery/temperature, ตรวจค่าข้อมูลที่ไม่พร้อมใช้ และทดสอบการคืนค่าหลัง cooling pause
- **การเผยแพร่:** ต้องเพิ่ม Release packaging, signing/notarization และกระบวนการติดตั้งก่อนแจกเป็นแอปพร้อมใช้
- **Test coverage:** เพิ่มกรณี backend failure, timeout, cache invalidation, simulation isolation และ settings persistence

การ build หรือผ่าน unit tests ไม่ได้หมายความว่าทดสอบความทนทานระยะยาวหรือฮาร์ดแวร์ทุกรุ่นแล้ว ใช้เป็นรุ่นทดลองและตรวจสถานะจาก backend ประกอบ

## Contributors

- [Kridsadar (@kridsadar357)](https://github.com/kridsadar357)

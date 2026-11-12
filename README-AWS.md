# System Parking – Windows Server 2022 លើ AWS (Step by Step)

VPC 192.168.111.0/24 → Frontend (IIS HTTPS) · Backend (Node.js) · Database (MariaDB)

## អ្វីដែលបានកែក្នុង project (តេស្តជាមួយ MariaDB 10.11 ពិតប្រាកដ)
1. `backend/server..js` → `server.js`
2. `package.json` និង `.env` ផ្លាស់មក `backend/` root
3. `backend/config/db.js` បាត់ `module.exports` → បានបន្ថែម និងអាន `.env` ត្រឹមត្រូវ
4. Login: password ក្នុង DB ជា SHA2 តែ code ប្រៀបធៀបអក្សរធម្មតា → កែជា `SHA2(?,256)`
5. `DB/parking_db.sql`: ដាក់ `-` មួយ (comment ខុស) → កែជា `--`; view weekly បន្ថែម `report_year`, `report_week` ឲ្យត្រូវនឹងរបាយការណ៍
6. Frontend: `API_URL` ជា `/api/parking` (IIS proxy ទៅ Backend) ដូច្នេះ Backend មិនបាច់បើក Internet
7. `node_modules` ដាក់មកស្រាប់ (Backend គ្មាន Internet រត់ `npm install` មិនបាន)
8. `nginx.conf` ជំនួសដោយ `Frontend/web.config` (IIS)

Login: `admin` / `Admin123` (ប្តូរក្រោយ)  ·  DB user: `parking_app` / `Admin@123`

---
## ជំហាន ១ — បង្កើត VPC
VPC Console → Create VPC → **VPC only** → Name `parking-vpc`, IPv4 CIDR `192.168.111.0/24`.

## ជំហាន ២ — Subnets (AZ ដូចគ្នា)
| Name | CIDR |
|---|---|
| frontend-subnet | 192.168.111.0/26 |
| backend-subnet | 192.168.111.64/27 |
| database-subnet | 192.168.111.96/28 |

(AWS រក្សា IP ៥ ដំបូង/ចុងក្នុង subnet នីមួយៗ — .12, .70, .101 នៅតែប្រើបាន)

## ជំហាន ៣ — Internet Gateway និង Route Table
1. Create Internet Gateway `parking-igw` → Attach ទៅ `parking-vpc`
2. Route table `public-rt`: បន្ថែម `0.0.0.0/0 → igw` → Associate **តែ frontend-subnet**
3. Route table `private-rt` (ទុក local route ប៉ុណ្ណោះ **កុំដាក់ NAT / IGW**) → Associate backend-subnet និង database-subnet

## ជំហាន ៤ — Security Groups (ក្នុង parking-vpc)
បង្កើត ៣ ដោយមិនទាន់ដាក់ rule ឯកសាររួច ទើបបន្ថែម (ដើម្បីយោង SG គ្នាទៅវិញទៅមក)។

**sg-frontend**
- Inbound: HTTP 80 ← 0.0.0.0/0 · HTTPS 443 ← 0.0.0.0/0 · RDP 3389 ← **My IP**
- Outbound: All traffic (ទុកលំនាំដើម)

**sg-backend**
- Inbound: RDP 3389 ← sg-frontend · All ICMP-IPv4 ← sg-frontend · Custom TCP **5000** ← sg-frontend
- Outbound: **លុប rule លំនាំដើម** រួចដាក់ MySQL/Aurora **3306** → sg-db

**sg-db**
- Inbound: RDP 3389 ← sg-frontend · All ICMP-IPv4 ← sg-frontend · MySQL/Aurora **3306** ← sg-backend
- Outbound: **លុប rule លំនាំដើម** (គ្មានអ្វីសោះ)

## ជំហាន ៥ — Launch EC2 (Windows Server 2022 Base)
| VM | Subnet | Private IP | Public IP | SG |
|---|---|---|---|---|
| frontend | frontend-subnet | 192.168.111.12 | Enable | sg-frontend |
| backend | backend-subnet | 192.168.111.70 | Disable | sg-backend |
| database | database-subnet | 192.168.111.101 | Disable | sg-db |

- Instance type: t3.medium · Key pair: បង្កើតមួយ (.pem) សម្រាប់ទាញ Administrator password
- IP កំណត់ត្រង់ Network settings → Advanced → Primary IP
- Frontend: បន្ថែម **Elastic IP** ដើម្បីកុំឲ្យ IP ប្តូរ

## ជំហាន ៦ — RDP ចូល
1. EC2 → Connect → RDP client → **Get password** (upload .pem) សម្រាប់ម៉ាស៊ីននីមួយៗ
2. RDP ចូល **frontend** តាម Public IP
3. ពី frontend បើក `mstsc` ទៅ `192.168.111.70` និង `192.168.111.101` (ប្រើ password របស់ម៉ាស៊ីននោះ)

## ជំហាន ៧ — ទាញ installers លើ Frontend (មាន Internet) រួច copy ទៅ Backend/DB
ទាញលើ frontend ហើយ copy/paste តាម RDP clipboard៖
- Node.js LTS (.msi) → Backend
- MariaDB 10.11 (.msi) → Database
- NSSM (nssm.exe 64-bit) → Backend ដាក់ក្នុង `C:\nssm\nssm.exe`
- Copy **folder zip នេះទាំងមូល** ទៅ `C:\parking` លើម៉ាស៊ីនទាំង ៣ ហើយ Extract

## ជំហាន ៨ — Database (.101)
1. តំឡើង MariaDB (Next… កំណត់ root password, port 3306, UTF8)
2. PowerShell (Administrator):
   `Set-ExecutionPolicy -Scope Process Bypass`
   `C:\parking\scripts\01-database.ps1`  → បញ្ចូល root password ពេលសួរ

## ជំហាន ៩ — Backend (.70)
1. តំឡើង Node.js (Next…)
2. ដាក់ `nssm.exe` ក្នុង `C:\nssm\`
3. `Set-ExecutionPolicy -Scope Process Bypass` → `C:\parking\scripts\02-backend.ps1`
4. តេស្ត: `curl http://localhost:5000/api/parking/capacity` ត្រូវបាន JSON

## ជំហាន ១០ — Frontend (.12)
`Set-ExecutionPolicy -Scope Process Bypass` → `C:\parking\scripts\03-frontend.ps1`
បើក `https://<Elastic-IP>` (Browser ជូនដំណឹង certificate self-signed → Continue)

## ជំហាន ១១ — ផ្ទៀងផ្ទាត់ក្បួន Network
| តេស្ត | លទ្ធផល |
|---|---|
| Frontend: `ping 192.168.111.70` / `.101` | ✅ ឆ្លើយតប |
| Frontend: `mstsc` ទៅ .70 / .101 | ✅ ចូលបាន |
| Frontend: `Test-NetConnection 192.168.111.70 -Port 5000` | ✅ True |
| Backend: `Test-NetConnection 192.168.111.101 -Port 3306` | ✅ True |
| Frontend: `Test-NetConnection 192.168.111.101 -Port 3306` | ❌ False |
| Backend/DB: `ping 8.8.8.8` | ❌ Timeout |
| Backend/DB: ចូលពី Internet ផ្ទាល់ | ❌ គ្មាន Public IP |
| Browser → `https://<IP>` Login → Check-in | ✅ ដំណើរការ |

## សុវត្ថិភាព (ត្រូវធ្វើមុនប្រើពិតប្រាកដ)
- ប្តូរ `Admin@123` (ក្នុង SQL + `backend\.env`) និង password admin
- ប្រើ domain + certificate ពិតប្រាកដ (win-acme / ACM) ជំនួស self-signed
- កំណត់ RDP ឲ្យ My IP ប៉ុណ្ណោះ ឬប្រើ SSM Session Manager

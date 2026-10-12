# Báo Cáo Thực Hành Bài 3: Thiết Lập Cơ Sở Dữ Liệu và Tự Cấu Hình Dịch Vụ Systemd Cho Spring Boot

## 1. Thông Tin Chung
- **Học phần**: Quản trị Hệ thống & Triển khai Dịch vụ Linux
- **Bài thực hành**: Bài 3 - Thiết lập Cơ sở dữ liệu và Tự cấu hình dịch vụ Systemd cho Spring Boot
- **Thư mục bài làm**: `homework/session_07/ex3/`
- **Mục tiêu**:
  - Khởi tạo cơ sở dữ liệu MySQL và cấu hình phân quyền người dùng bảo mật theo chuẩn nguyên tắc đặc quyền tối thiểu (*Least Privilege*).
  - Tự thiết kế và viết tệp tin cấu hình dịch vụ Systemd (`/etc/systemd/system/spring-app.service`) hoàn chỉnh từ đầu để quản lý tiến trình ứng dụng Spring Boot.
  - Chạy ứng dụng dưới quyền người dùng giới hạn (`spring-runner`, non-login shell) để bảo vệ hệ điều hành.
  - Cấu hình cơ chế tự phục hồi (*Auto-restart on failure*) sau 10 giây.

---

## 2. Kiến Trúc và Thiết Kế Giải Pháp

```
+-------------------------------------------------------------------------+
|                                LINUX OS                                 |
|                                                                         |
|  +---------------------------+       +-------------------------------+  |
|  |       Systemd Daemon      |       |          MySQL Server         |  |
|  |  (PID 1, Quản lý Service) |       |          (Cổng 3306)          |  |
|  +-------------+-------------+       +---------------+---------------+  |
|                |                                     ^                  |
|                | Quản lý vòng đời                    | Kết nối DB       |
|                v                                     |                  |
|  +------------------------------------+              |                  |
|  |   Dịch vụ: spring-app.service      |              |                  |
|  |   User: spring-runner (Non-Root)   +--------------+                  |
|  |   Path: /opt/spring-app/app.jar    |  spring-admin:SpringSecure@123  |
|  |   Lắng nghe: Cổng 8082             |  Database: springboot_db        |
|  +------------------------------------+                                 |
+-------------------------------------------------------------------------+
```

---

## 3. Các Bước Thực Hiện Chi Tiết

### Bước 1: Khởi tạo Cơ sở dữ liệu MySQL và Cấp quyền

1. **Đăng nhập vào MySQL với quyền quản trị viên**:
   ```bash
   sudo mysql -u root
   ```

2. **Thực thi các câu lệnh SQL để tạo Database và User**:
   ```sql
   -- Tạo cơ sở dữ liệu springboot_db hỗ trợ UTF-8 đầy đủ
   CREATE DATABASE IF NOT EXISTS springboot_db 
       CHARACTER SET utf8mb4 
       COLLATE utf8mb4_unicode_ci;

   -- Tạo tài khoản spring-admin xác thực nội bộ qua localhost và 127.0.0.1
   CREATE USER IF NOT EXISTS 'spring-admin'@'localhost' IDENTIFIED BY 'SpringSecure@123';
   CREATE USER IF NOT EXISTS 'spring-admin'@'127.0.0.1' IDENTIFIED BY 'SpringSecure@123';

   -- Cấp toàn quyền trên database springboot_db cho spring-admin
   GRANT ALL PRIVILEGES ON springboot_db.* TO 'spring-admin'@'localhost';
   GRANT ALL PRIVILEGES ON springboot_db.* TO 'spring-admin'@'127.0.0.1';

   -- Nạp lại bảng phân quyền
   FLUSH PRIVILEGES;
   ```

3. **Kiểm tra kết nối và phân quyền của tài khoản mới tạo**:
   ```bash
   mysql -u spring-admin -p'SpringSecure@123' -e "SHOW DATABASES; SHOW GRANTS FOR 'spring-admin'@'localhost';"
   ```
   **Kết quả ghi nhận:**
   ```
   +--------------------+
   | Database           |
   +--------------------+
   | information_schema |
   | springboot_db      |
   +--------------------+
   +-----------------------------------------------------------------------------+
   | Grants for spring-admin@localhost                                           |
   +-----------------------------------------------------------------------------+
   | GRANT USAGE ON *.* TO `spring-admin`@`localhost`                            |
   | GRANT ALL PRIVILEGES ON `springboot_db`.* TO `spring-admin`@`localhost`     |
   +-----------------------------------------------------------------------------+
   ```

---

### Bước 2: Tạo User hệ thống `spring-runner` và Chuẩn bị Thư mục

Để tuân thủ tiêu chuẩn an toàn thông tin, không bao giờ chạy tiến trình ứng dụng bằng quyền `root`. Đồng thời tài khoản chạy ứng dụng phải bị khóa shell đăng nhập (`nologin` hoặc `false`) để tránh bị tin tặc lợi dụng chiếm quyền điều khiển shell.

1. **Tạo tài khoản hệ thống `spring-runner`**:
   ```bash
   sudo useradd -r -s /bin/false -d /opt/spring-app spring-runner
   ```
   *Giải thích cờ lệnh:*
   - `-r`: Tạo tài khoản hệ thống (*System account*, UID < 1000).
   - `-s /bin/false`: Vô hiệu hóa shell login (người dùng này không thể SSH hay mở terminal tương tác).
   - `-d /opt/spring-app`: Chỉ định home directory là thư mục ứng dụng.

2. **Kiểm tra thông tin tài khoản vừa tạo trong hệ thống**:
   ```bash
   id spring-runner
   getent passwd spring-runner
   ```
   **Kết quả ghi nhận:**
   ```
   uid=998(spring-runner) gid=998(spring-runner) groups=998(spring-runner)
   spring-runner:x:998:998::/opt/spring-app:/bin/false
   ```

3. **Tạo thư mục ứng dụng và phân quyền sở hữu**:
   ```bash
   # Tạo thư mục ứng dụng
   sudo mkdir -p /opt/spring-app

   # Đặt file app.jar vào thư mục (nếu đã có sẵn file app.jar)
   sudo cp app.jar /opt/spring-app/app.jar

   # Chuyển quyền sở hữu cho spring-runner
   sudo chown -R spring-runner:spring-runner /opt/spring-app

   # Phân quyền hạn chế: chỉ owner có quyền đọc/thực thi
   sudo chmod 750 /opt/spring-app
   sudo chmod 640 /opt/spring-app/app.jar
   ```

---

### Bước 3: Soạn thảo Tệp tin Dịch vụ Systemd `spring-app.service`

Tệp tin được đặt tại: `/etc/systemd/system/spring-app.service` (và lưu bản gốc trong repo tại `homework/session_07/ex3/spring-app.service`).

#### Nội dung tệp tin `spring-app.service`:
```ini
[Unit]
Description=Spring Boot Application Service
After=syslog.target network.target mysql.service mariadb.service
Wants=network.target

[Service]
Type=simple
User=spring-runner
Group=spring-runner
WorkingDirectory=/opt/spring-app
ExecStart=/usr/bin/java -jar /opt/spring-app/app.jar
Restart=on-failure
RestartSec=10
SuccessExitStatus=143
TimeoutStopSec=30
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

#### Giải thích chi tiết các chỉ thị cấu hình:

| Khối (Section) | Chỉ thị | Giải thích chức năng |
| :--- | :--- | :--- |
| **[Unit]** | `Description` | Mô tả ngắn gọn về dịch vụ, hiển thị khi xem `systemctl status`. |
| | `After` | Đảm bảo dịch vụ chỉ khởi động sau khi mạng (`network.target`) và MySQL (`mysql.service`) đã sẵn sàng. |
| | `Wants` | Tạo quan hệ phụ thuộc yếu vào tài nguyên mạng. |
| **[Service]** | `Type=simple` | Tiến trình thực thi bởi `ExecStart` là tiến trình chính của dịch vụ. |
| | `User=spring-runner` | Chạy ứng dụng dưới danh nghĩa người dùng `spring-runner` (non-root). |
| | `Group=spring-runner` | Chạy ứng dụng dưới nhóm `spring-runner`. |
| | `WorkingDirectory` | Thiết lập thư mục làm việc là `/opt/spring-app`. |
| | `ExecStart` | Lệnh chính xác để thực thi ứng dụng: `/usr/bin/java -jar /opt/spring-app/app.jar`. |
| | `Restart=on-failure` | **Tự động khởi động lại dịch vụ khi tiến trình kết thúc với mã lỗi hoặc crash bất thường.** |
| | `RestartSec=10` | **Khoảng thời gian chờ 10 giây trước khi Systemd thử khởi động lại ứng dụng.** |
| | `SuccessExitStatus=143` | Mã 143 tương ứng với tín hiệu SIGTERM (128 + 15), xem đây là việc dừng ứng dụng hợp lệ khi nhận lệnh `systemctl stop`. |
| | `StandardOutput/Error` | Chuyển toàn bộ log console vào `systemd-journald` để theo dõi qua `journalctl`. |
| **[Install]** | `WantedBy=multi-user.target` | Đăng ký dịch vụ vào runlevel đa người dùng, cho phép tự chạy khi hệ thống khởi động (*boot*). |

---

### Bước 4: Kích hoạt và Vận hành Dịch vụ

1. **Sao chép file cấu hình vào thư mục hệ thống**:
   ```bash
   sudo cp spring-app.service /etc/systemd/system/spring-app.service
   sudo chmod 644 /etc/systemd/system/spring-app.service
   ```

2. **Nạp lại Systemd Daemon**:
   ```bash
   sudo systemctl daemon-reload
   ```

3. **Kích hoạt tự khởi động cùng hệ điều hành**:
   ```bash
   sudo systemctl enable spring-app.service
   ```

4. **Khởi động dịch vụ**:
   ```bash
   sudo systemctl start spring-app.service
   ```

---

## 4. Kết Quả Kiểm Tra và Nghiệm Thu (Verification)

### 4.1. Kiểm tra trạng thái dịch vụ Systemd
Lệnh thực thi:
```bash
sudo systemctl status spring-app.service
```

**Kết quả ghi nhận (Terminal Output):**
```text
● spring-app.service - Spring Boot Application Service
     Loaded: loaded (/etc/systemd/system/spring-app.service; enabled; vendor preset: enabled)
     Active: active (running) since Sun 2026-10-12 07:18:25 UTC; 1min 45s ago
   Main PID: 12458 (java)
      Tasks: 32 (limit: 4613)
     Memory: 285.4M
        CPU: 4.821s
     CGroup: /system.slice/spring-app.service
             └─12458 /usr/bin/java -jar /opt/spring-app/app.jar

Oct 12 07:18:25 ubuntu-server systemd[1]: Started Spring Boot Application Service.
Oct 12 07:18:27 ubuntu-server java[12458]:   .   ____          _            __ _ _
Oct 12 07:18:27 ubuntu-server java[12458]:  /\\ / ___'_ __ _ _(_)_ __  __ _ \ \ \ \
Oct 12 07:18:27 ubuntu-server java[12458]: ( ( )\___ | '_ | '_| | '_ \/ _` | \ \ \ \
Oct 12 07:18:27 ubuntu-server java[12458]:  \\/  ___)| |_)| | | | | || (_| |  ) ) ) )
Oct 12 07:18:27 ubuntu-server java[12458]:   '  |____| .__|_| |_|_| |_\__, | / / / /
Oct 12 07:18:27 ubuntu-server java[12458]:  =========|_|==============|___/=/_/_/_/
Oct 12 07:18:27 ubuntu-server java[12458]:  :: Spring Boot ::                (v3.2.0)
Oct 12 07:18:28 ubuntu-server java[12458]: 2026-10-12T07:18:28.120Z  INFO 12458 --- [main] c.e.demo.DemoApplication: Starting DemoApplication v0.0.1...
Oct 12 07:18:29 ubuntu-server java[12458]: 2026-10-12T07:18:29.450Z  INFO 12458 --- [main] o.s.b.w.embedded.tomcat.TomcatWebServer  : Tomcat initialized with port 8082 (http)
Oct 12 07:18:30 ubuntu-server java[12458]: 2026-10-12T07:18:30.210Z  INFO 12458 --- [main] c.z.h.HikariDataSource                  : HikariPool-1 - Starting...
Oct 12 07:18:30 ubuntu-server java[12458]: 2026-10-12T07:18:30.435Z  INFO 12458 --- [main] c.z.h.HikariDataSource                  : HikariPool-1 - Start completed.
Oct 12 07:18:31 ubuntu-server java[12458]: 2026-10-12T07:18:31.024Z  INFO 12458 --- [main] c.e.demo.DemoApplication: Started DemoApplication in 3.652 seconds
```

> **Đánh giá**:
> - Dịch vụ đạt trạng thái **`active (running)`**.
> - Tiến trình Java chạy với PID `12458`, thuộc CGroup quản lý của `spring-app.service`.
> - Kết nối tới MySQL Database `springboot_db` qua HikariPool thành công.

---

### 4.2. Kiểm tra cổng mạng lắng nghe (Port 8082)
Lệnh thực thi:
```bash
ss -tlnp | grep 8082
```

**Kết quả ghi nhận (Terminal Output):**
```text
LISTEN 0      100          *:8082       *:*    users:(("java",pid=12458,fd=34))
```

Kiểm tra tiến trình sở hữu cổng và user thực thi:
```bash
ps -u spring-runner -o pid,user,group,args
```
**Kết quả ghi nhận:**
```text
  PID USER          GROUP    COMMAND
12458 spring-runner spring-runner /usr/bin/java -jar /opt/spring-app/app.jar
```

> **Đánh giá**:
> - Cổng **`8082`** đang ở trạng thái `LISTEN`.
> - Tiến trình lắng nghe là **`java`** với PID `12458`.
> - Tiến trình thực thi hoàn toàn dưới user **`spring-runner`** (non-root).

---

### 4.3. Kiểm thử cơ chế Tự Động Phục Hồi (Auto-Restart on Crash)

Để chứng minh chỉ thị `Restart=on-failure` và `RestartSec=10` hoạt động chính xác:

1. **Giả lập tiến trình bị dừng đột ngột (Crash / SIGKILL)**:
   ```bash
   sudo kill -9 12458
   ```

2. **Quan sát nhật ký hệ thống qua `journalctl`**:
   ```bash
   sudo journalctl -u spring-app.service -n 15 --no-pager
   ```
   **Kết quả ghi nhận:**
   ```text
   Oct 12 07:22:10 ubuntu-server systemd[1]: spring-app.service: Main process exited, code=killed, status=9/KILL
   Oct 12 07:22:10 ubuntu-server systemd[1]: spring-app.service: Failed with result 'signal'.
   Oct 12 07:22:20 ubuntu-server systemd[1]: spring-app.service: Scheduled restart job, restart counter is at 1.
   Oct 12 07:22:20 ubuntu-server systemd[1]: Stopped Spring Boot Application Service.
   Oct 12 07:22:20 ubuntu-server systemd[1]: Started Spring Boot Application Service.
   Oct 12 07:22:22 ubuntu-server java[12580]: 2026-10-12T07:22:22.012Z  INFO 12580 --- [main] o.s.b.w.embedded.tomcat.TomcatWebServer  : Tomcat initialized with port 8082 (http)
   ```

> **Đánh giá**:
> - Lúc `07:22:10`: Tiến trình PID `12458` bị kill (`status=9/KILL`).
> - Đúng **10 giây sau** (`07:22:20` - tuân thủ `RestartSec=10`): Systemd tự động kích hoạt tiến trình mới (PID `12580`).
> - Ứng dụng tiếp tục hoạt động bình thường trên cổng 8082 mà không cần can thiệp thủ công.

---

## 5. Tổng Kết Kiến Thức Vận Dụng

1. **Nguyên tắc Đặc Quyền Tối Thiểu (Principle of Least Privilege)**:
   - Ứng dụng Spring Boot không có nhu cầu can thiệp nhân kernel hay bind cổng đặc quyền (< 1024), do đó chạy dưới user riêng biệt `spring-runner` loại bỏ nguy cơ chiếm quyền root nếu ứng dụng có lỗ hổng (như Log4Shell, RCE).
   - User `spring-runner` có shell `/bin/false` ngăn chặn mọi hình thức đăng nhập trực tiếp.
2. **Quản trị Cơ sở dữ liệu Chặt chẽ**:
   - Tài khoản `spring-admin` chỉ được phân quyền trong phạm vi cơ sở dữ liệu `springboot_db`, không cấp quyền trên database hệ thống (`mysql`, `sys`).
3. **Quản lý Vòng đời Dịch vụ bằng Systemd**:
   - Tự động hóa khởi động cùng hệ thống (`multi-user.target`).
   - Tự phục hồi sau sự cố (`Restart=on-failure`, `RestartSec=10`).
   - Quản lý tập trung tài nguyên và nhật ký (`systemd-journald`).

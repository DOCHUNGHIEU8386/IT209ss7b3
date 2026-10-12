-- ===============================================================
-- Script khởi tạo Database và User cho Spring Boot
-- Bài 3: Thiết lập Cơ sở dữ liệu và Tự cấu hình dịch vụ Systemd
-- ===============================================================

-- 1. Tạo cơ sở dữ liệu springboot_db nếu chưa tồn tại
CREATE DATABASE IF NOT EXISTS springboot_db 
    CHARACTER SET utf8mb4 
    COLLATE utf8mb4_unicode_ci;

-- 2. Tạo tài khoản spring-admin với mật khẩu SpringSecure@123
CREATE USER IF NOT EXISTS 'spring-admin'@'localhost' IDENTIFIED BY 'SpringSecure@123';
CREATE USER IF NOT EXISTS 'spring-admin'@'127.0.0.1' IDENTIFIED BY 'SpringSecure@123';

-- 3. Cấp toàn bộ đặc quyền trên database springboot_db cho spring-admin
GRANT ALL PRIVILEGES ON springboot_db.* TO 'spring-admin'@'localhost';
GRANT ALL PRIVILEGES ON springboot_db.* TO 'spring-admin'@'127.0.0.1';

-- 4. Áp dụng các thay đổi phân quyền
FLUSH PRIVILEGES;

-- 5. Kiểm tra lại thông tin quyền vừa cấp
SHOW GRANTS FOR 'spring-admin'@'localhost';

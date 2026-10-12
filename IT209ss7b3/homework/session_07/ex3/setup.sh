#!/usr/bin/env bash
# ==============================================================================
# Script tự động triển khai Bài 3: Spring Boot Systemd & MySQL
# ==============================================================================
set -e

echo "[1/6] Thiết lập MySQL Database và Phân quyền người dùng..."
sudo mysql -u root < setup_db.sql || {
    echo "Nhập mật khẩu root MySQL nếu có:"
    mysql -u root -p < setup_db.sql
}
echo "=> Đã tạo cơ sở dữ liệu 'springboot_db' và cấp quyền cho 'spring-admin'."

echo ""
echo "[2/6] Tạo người dùng hệ thống non-login 'spring-runner'..."
if id "spring-runner" &>/dev/null; then
    echo "=> User 'spring-runner' đã tồn tại."
else
    sudo useradd -r -s /bin/false -d /opt/spring-app spring-runner
    echo "=> Đã tạo thành công user hệ thống 'spring-runner' (no login shell)."
fi

echo ""
echo "[3/6] Chuẩn bị thư mục triển khai /opt/spring-app..."
sudo mkdir -p /opt/spring-app

# Nếu có file app.jar ở thư mục hiện tại, copy vào /opt/spring-app
if [ -f "app.jar" ]; then
    echo "=> Đang copy app.jar vào /opt/spring-app/..."
    sudo cp app.jar /opt/spring-app/app.jar
fi

# Phân quyền cho spring-runner
sudo chown -R spring-runner:spring-runner /opt/spring-app
sudo chmod 750 /opt/spring-app
if [ -f "/opt/spring-app/app.jar" ]; then
    sudo chmod 640 /opt/spring-app/app.jar
fi
echo "=> Đã phân quyền thư mục /opt/spring-app cho user 'spring-runner'."

echo ""
echo "[4/6] Cài đặt file dịch vụ Systemd..."
sudo cp spring-app.service /etc/systemd/system/spring-app.service
sudo chmod 644 /etc/systemd/system/spring-app.service

echo ""
echo "[5/6] Nạp lại systemd daemon và kích hoạt dịch vụ..."
sudo systemctl daemon-reload
sudo systemctl enable spring-app.service
sudo systemctl restart spring-app.service
echo "=> Đã khởi động dịch vụ spring-app.service."

echo ""
echo "[6/6] Kiểm tra trạng thái dịch vụ và cổng mạng..."
sleep 3
echo "--- Trạng thái Systemd: ---"
sudo systemctl status spring-app.service --no-pager || true

echo ""
echo "--- Kiểm tra cổng lắng nghe (8082): ---"
ss -tlnp | grep 8082 || echo "Đang đợi ứng dụng khởi động hoàn tất..."

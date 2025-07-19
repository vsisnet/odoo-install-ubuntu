#!/bin/bash

# Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then
  echo "Vui lòng chạy script với quyền sudo hoặc root."
  exit 1
fi

# Yêu cầu người dùng nhập mật khẩu
echo "Nhập mật khẩu cho người dùng PostgreSQL (POSTGRES_PASSWORD):"
read -s POSTGRES_PASSWORD
echo
echo "Nhập mật khẩu quản trị viên Odoo (ADMIN_PASSWORD):"
read -s ADMIN_PASSWORD
echo

# Các biến cấu hình
ODOO_USER="odoo"
ODOO_HOME="/opt/odoo"
ODOO_VENV="$ODOO_HOME/venv"
ODOO_CONFIG="/etc/odoo/odoo.conf"
WKHTMLTOPDF_URL="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6-1/wkhtmltox_0.12.6-1.$(lsb_release -cs)_amd64.deb"

# Lấy địa chỉ IP của máy chủ
SERVER_IP=$(hostname -I | awk '{print $1}')

# Lấy phiên bản Odoo mới nhất từ nhánh main trên GitHub
echo "Kiểm tra phiên bản Odoo mới nhất..."
ODOO_VERSION=$(git ls-remote --refs --tags https://github.com/odoo/odoo.git | grep -o 'refs/tags/[0-9]*\.[0-9]*\.[0-9]*' | sort -V | tail -n1 | cut -d'/' -f3)
if [ -z "$ODOO_VERSION" ]; then
  echo "Không thể lấy phiên bản Odoo, sử dụng mặc định 18.0."
  ODOO_VERSION="18.0"
fi

# Xác định phiên bản Python tương thích (tối thiểu 3.10, ưu tiên 3.12)
PYTHON_VERSION="3.12"  # Mặc định thử 3.12, điều chỉnh nếu cần
echo "Cài đặt Python $PYTHON_VERSION..."
add-apt-repository ppa:deadsnakes/ppa -y
apt update
apt install -y python${PYTHON_VERSION} python${PYTHON_VERSION}-venv python${PYTHON_VERSION}-dev
update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 1

# Bước 1: Cập nhật hệ thống
echo "Cập nhật hệ thống..."
apt update && apt upgrade -y

# Bước 2: Cài đặt các phụ thuộc cơ bản
echo "Cài đặt các phụ thuộc..."
apt install -y software-properties-common python3-pip python3-dev python3-wheel libpq-dev \
    git build-essential wget nodejs npm libldap2-dev libsasl2-dev libssl-dev libxml2-dev libxslt1-dev zlib1g-dev

# Bước 3: Cài đặt và cấu hình PostgreSQL
echo "Cài đặt PostgreSQL..."
apt install -y postgresql
systemctl start postgresql
systemctl enable postgresql

echo "Tạo người dùng PostgreSQL cho Odoo..."
sudo -u postgres createuser --createdb $ODOO_USER
sudo -u postgres psql -c "ALTER USER $ODOO_USER WITH PASSWORD '$POSTGRES_PASSWORD';"

# Bước 4: Tạo người dùng hệ thống cho Odoo
echo "Tạo người dùng hệ thống Odoo..."
adduser --system --group --home $ODOO_HOME $ODOO_USER

# Bước 5: Tải mã nguồn Odoo
echo "Tải mã nguồn Odoo $ODOO_VERSION..."
git clone https://github.com/odoo/odoo.git $ODOO_HOME/odoo --depth 1 --branch $ODOO_VERSION
chown -R $ODOO_USER:$ODOO_USER $ODOO_HOME

# Bước 6: Tạo môi trường ảo với Python đã chọn
echo "Thiết lập môi trường ảo Python..."
python${PYTHON_VERSION} -m venv $ODOO_VENV
chown -R $ODOO_USER:$ODOO_USER $ODOO_VENV

# Bước 7: Cài đặt các thư viện Python và sửa requirements.txt
echo "Cài đặt các thư viện Python..."
source $ODOO_VENV/bin/activate
pip install --upgrade pip
pip install gevent==22.10.1 greenlet>=1.1.3,<2.0

# Sửa file requirements.txt để dùng gevent và greenlet tương thích
sed -i 's/gevent==21.8.0/gevent==22.10.1/' $ODOO_HOME/odoo/requirements.txt
sed -i 's/greenlet==1.1.2/greenlet>=1.1.3,<2.0/' $ODOO_HOME/odoo/requirements.txt
pip install -r $ODOO_HOME/odoo/requirements.txt
deactivate

# Bước 8: Cài đặt wkhtmltopdf
echo "Cài đặt wkhtmltopdf..."
wget $WKHTMLTOPDF_URL -O wkhtmltox.deb
dpkg -i wkhtmltox.deb
apt install -f -y
rm wkhtmltox.deb

# Bước 9: Cấu hình Odoo
echo "Tạo file cấu hình Odoo..."
mkdir /etc/odoo
cat > $ODOO_CONFIG <<EOL
[options]
admin_passwd = $ADMIN_PASSWORD
db_host = localhost
db_port = 5432
db_user = $ODOO_USER
db_password = $POSTGRES_PASSWORD
addons_path = $ODOO_HOME/odoo/addons
logfile = /var/log/odoo/odoo.log
xmlrpc_interface = 0.0.0.0
EOL

chown $ODOO_USER:$ODOO_USER $ODOO_CONFIG
chmod 640 $ODOO_CONFIG

echo "Tạo thư mục log..."
mkdir /var/log/odoo
chown $ODOO_USER:$ODOO_USER /var/log/odoo

# Bước 10: Thiết lập Odoo làm dịch vụ
echo "Thiết lập dịch vụ Odoo..."
cat > /etc/systemd/system/odoo.service <<EOL
[Unit]
Description=Odoo
After=network.target postgresql.service

[Service]
Type=simple
User=$ODOO_USER
Group=$ODOO_USER
ExecStart=$ODOO_VENV/bin/python3 $ODOO_HOME/odoo/odoo-bin -c $ODOO_CONFIG
Restart=always

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload
systemctl start odoo
systemctl enable odoo

# Bước 11: Kiểm tra trạng thái dịch vụ
echo "Kiểm tra trạng thái dịch vụ Odoo..."
systemctl status odoo --no-pager

# Thông báo hoàn tất
echo "Cài đặt Odoo hoàn tất!"
echo "Truy cập Odoo tại: http://$SERVER_IP:8069"
echo "Mật khẩu admin: $ADMIN_PASSWORD"
echo "Nếu cần thiết lập Nginx hoặc SSL, vui lòng cấu hình thêm."

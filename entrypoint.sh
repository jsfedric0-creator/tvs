#!/bin/bash
set -e

echo "=============================================="
echo "🎬 بدء تشغيل محطة الأطفال التلفزيونية"
echo "=============================================="

# إعداد متغيرات البيئة
export APP_HOME=${APP_HOME:-/app}
export LOG_DIR=${LOG_DIR:-/var/log/kidstv}

# إنشاء المجلدات إذا لم تكن موجودة
mkdir -p ${LOG_DIR}/{nginx,ffmpeg,scheduler,api}
mkdir -p /opt/streams/{live,recordings,playlists,cache}
mkdir -p /etc/schedule/{daily,weekly,monthly}

# تعيين الأذونات
chown -R www-data:www-data /opt/streams
chown -R kidstv:kidstv ${LOG_DIR}
chmod -R 755 ${LOG_DIR}

# تكوين Nginx
echo "🔧 تكوين Nginx..."
if [ ! -f /etc/nginx/ssl/cert.pem ]; then
    echo "📝 إنشاء شهادة SSL مؤقتة..."
    mkdir -p /etc/nginx/ssl
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/key.pem \
        -out /etc/nginx/ssl/cert.pem \
        -subj "/C=SA/ST=Riyadh/L=Riyadh/O=KidsTV/CN=kidstv.local" 2>/dev/null
fi

# اختبار تكوين Nginx
nginx -t

# تكوين قاعدة البيانات (إذا كانت تستخدم)
if [ "$DB_ENABLED" = "true" ]; then
    echo "🗄️ تكوين قاعدة البيانات..."
    python3 ${APP_HOME}/scripts/init_db.py
fi

# تحميل الجدولة
echo "📅 تحميل جدول البرامج..."
if [ -f "/etc/schedule/daily/today.json" ]; then
    cp "/etc/schedule/daily/today.json" "/etc/schedule/current.json"
else
    # استخدام الجدول الافتراضي
    cat > /etc/schedule/current.json << EOF
[
    {
        "id": 1,
        "time": "07:00",
        "name": "فطور مع النجوم",
        "type": "تعليمي",
        "stream_url": "https://educational.kids/tv1.m3u8",
        "duration": 60,
        "active": true
    },
    {
        "id": 2,
        "time": "08:00",
        "name": "أبطال الكرتون",
        "type": "ترفيهي",
        "stream_url": "https://cartoon.kids/tv2.m3u8",
        "duration": 120,
        "active": true
    }
]
EOF
fi

# بدء خدمات Cron
echo "⏰ بدء خدمة Cron..."
service cron start

# بدء تشغيل البرامج المقررة
echo "🚀 بدء تشغيل برامج الجدولة..."
python3 ${APP_HOME}/scheduler/init_schedule.py &

# إنشاء صفحة الصحة
cat > /var/www/html/health << 'EOF'
{
    "status": "healthy",
    "service": "kids-tv-station",
    "timestamp": "$(date -Iseconds)",
    "version": "1.0.0"
}
EOF

echo "✅ تم تهيئة النظام بنجاح"
echo "📺 الواجهة: http://localhost"
echo "🎮 لوحة التحكم: http://localhost:3000"
echo "📊 الإحصائيات: http://localhost:8080/stat"
echo "🔗 API: http://localhost:8000/api"

# تشغيل Supervisor
exec "$@"

# ==============================================
# محطة تلفزيونية للأطفال مع جدولة وأدوات بث
# ==============================================

# المرحلة 1: بناء التطبيق
FROM python:3.11-slim AS builder

# إعداد البيئة
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Riyadh \
    LANG=ar_SA.UTF-8 \
    LC_ALL=ar_SA.UTF-8

# تثبيت الاعتمادات الأساسية
RUN apt-get update && apt-get install -y \
    locales \
    tzdata \
    curl \
    wget \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

# إعداد اللغة العربية
RUN sed -i '/ar_SA.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen ar_SA.UTF-8

# تحديث pip
RUN pip install --upgrade pip

# نسخ ملفات المشروع
WORKDIR /app
COPY requirements.txt .

# تثبيت متطلبات Python
RUN pip install --no-cache-dir -r requirements.txt

# المرحلة 2: الصورة النهائية
FROM ubuntu:22.04

# ==============================================
# إعدادات البيئة
# ==============================================
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Riyadh \
    LANG=ar_SA.UTF-8 \
    LC_ALL=ar_SA.UTF-8 \
    APP_HOME=/app \
    NGINX_ROOT=/var/www/html \
    STREAM_DIR=/opt/streams \
    SCHEDULE_DIR=/etc/schedule \
    LOG_DIR=/var/log/kidstv

# ==============================================
# تثبيت الاعتمادات الأساسية
# ==============================================
RUN apt-get update && apt-get install -y \
    # أدوات النظام
    locales \
    tzdata \
    curl \
    wget \
    gnupg \
    software-properties-common \
    ca-certificates \
    apt-transport-https \
    # لغات
    language-pack-ar \
    fonts-arabeyes \
    # أدوات تطوير
    git \
    nano \
    htop \
    net-tools \
    iputils-ping \
    dnsutils \
    # إدارة العمليات
    supervisor \
    cron \
    logrotate \
    && rm -rf /var/lib/apt/lists/*

# ==============================================
# إعداد اللغة والوقت
# ==============================================
RUN locale-gen ar_SA.UTF-8 && \
    update-locale LANG=ar_SA.UTF-8 && \
    ln -fs /usr/share/zoneinfo/${TZ} /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata

# ==============================================
# تثبيت Nginx مع RTMP
# ==============================================
RUN apt-get update && apt-get install -y \
    nginx \
    nginx-extras \
    libnginx-mod-rtmp \
    && rm -rf /var/lib/apt/lists/*

# ==============================================
# تثبيت أدوات البث والوسائط
# ==============================================
RUN apt-get update && apt-get install -y \
    # FFmpeg للبث والتسجيل
    ffmpeg \
    # أدوات الوسائط
    mediainfo \
    mpv \
    # مشغلات الصوت
    mplayer \
    sox \
    # أدوات الشبكة
    iptables \
    netcat \
    socat \
    && rm -rf /var/lib/apt/lists/*

# ==============================================
# تثبيت Python والأدوات
# ==============================================
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# ==============================================
# إنشاء المستخدمين والمجلدات
# ==============================================
# إنشاء مستخدم خاص للتشغيل
RUN useradd -m -s /bin/bash -u 1000 kidstv && \
    usermod -aG www-data kidstv

# إنشاء المجلدات الأساسية
RUN mkdir -p \
    ${APP_HOME} \
    ${NGINX_ROOT} \
    ${STREAM_DIR}/{live,recordings,playlists,cache} \
    ${SCHEDULE_DIR}/{daily,weekly,monthly} \
    ${LOG_DIR}/{nginx,ffmpeg,scheduler,api} \
    /etc/nginx/{sites-available,sites-enabled,ssl} \
    /var/cache/nginx \
    && chown -R kidstv:kidstv ${APP_HOME} \
    && chown -R www-data:www-data ${STREAM_DIR} \
    && chown -R kidstv:kidstv ${LOG_DIR}

# ==============================================
# نسخ ملفات التطبيق من المرحلة الأولى
# ==============================================
WORKDIR ${APP_HOME}

# نسخ متطلبات Python والتطبيق
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin
COPY requirements.txt .

# نسخ ملفات المشروع
COPY scheduler/ ./scheduler/
COPY api/ ./api/
COPY scripts/ ./scripts/
COPY web/ ./web/
COPY config/ ./config/

# ==============================================
# تكوين Nginx
# ==============================================
# نسخ ملفات تكوين Nginx
COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/rtmp.conf /etc/nginx/modules-available/rtmp.conf
COPY nginx/sites/kidstv.conf /etc/nginx/sites-available/kidstv.conf
COPY nginx/sites/stream.conf /etc/nginx/sites-available/stream.conf

# تفعيل المواقع
RUN ln -sf /etc/nginx/sites-available/kidstv.conf /etc/nginx/sites-enabled/ && \
    ln -sf /etc/nginx/sites-available/stream.conf /etc/nginx/sites-enabled/ && \
    rm -f /etc/nginx/sites-enabled/default

# ==============================================
# تكوين Supervisor
# ==============================================
COPY supervisor/supervisord.conf /etc/supervisor/supervisord.conf
COPY supervisor/conf.d/ /etc/supervisor/conf.d/

# ==============================================
# تكوين Cron للجدولة
# ==============================================
COPY cron/kidstv-cron /etc/cron.d/kidstv-cron
RUN chmod 0644 /etc/cron.d/kidstv-cron && \
    crontab /etc/cron.d/kidstv-cron

# ==============================================
# تكوين النظام
# ==============================================
# صفحة Nginx الأساسية
COPY web/ ${NGINX_ROOT}/

# ملفات الجدولة الافتراضية
COPY schedule/ ${SCHEDULE_DIR}/

# قوائم التشغيل الافتراضية
COPY playlists/ ${STREAM_DIR}/playlists/

# ==============================================
# تعيين الأذونات
# ==============================================
RUN chmod +x ${APP_HOME}/scripts/*.sh && \
    chmod +x ${APP_HOME}/scheduler/*.py && \
    chmod +x ${APP_HOME}/api/*.py && \
    chown -R kidstv:kidstv ${APP_HOME} && \
    chown -R www-data:www-data ${NGINX_ROOT} && \
    chown -R www-data:www-data /var/cache/nginx && \
    chown -R www-data:www-data /var/log/nginx

# ==============================================
# فتح المنافذ
# ==============================================
# 80: HTTP
# 443: HTTPS
# 1935: RTMP للبث المباشر
# 8080: إحصائيات البث
# 8000: واجهة API
# 3000: لوحة التحكم
EXPOSE 80 443 1935 8080 8000 3000

# ==============================================
# إعدادات الصحة (Health Check)
# ==============================================
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -f http://localhost/health || exit 1

# ==============================================
# نقطة الدخول
# ==============================================
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

# ==============================================
# الأمر الافتراضي
# ==============================================
CMD ["supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]

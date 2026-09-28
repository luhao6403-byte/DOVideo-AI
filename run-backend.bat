@echo off
cd /d "C:\Users\35022\Doubao\chats\2026-09-12\new-chat\DOVideo-AI\server"

echo ========================================
echo   Setting environment variables...
echo ========================================

set DB_USERNAME=dovideo
set DB_PASSWORD=Hhka8AFo7bnjXudx
set DB_URL=jdbc:mysql://localhost:3307/media_db?useSSL=false^&serverTimezone=Asia/Shanghai^&characterEncoding=utf-8^&allowPublicKeyRetrieval=true
set SILICONFLOW_API_KEY=sk-whxjdvbbeqvkcgqrwwyzowceuabglwctznawxjyyjpezgptc
set SILICONFLOW_BASE_URL=https://api.siliconflow.cn/v1
set MINIO_ACCESS_KEY=dovideo
set MINIO_SECRET_KEY=pabsfEj4QO3LHdSZk0qT
set MINIO_ENDPOINT=http://localhost:9000
set MINIO_BUCKET=media
set REDIS_PASSWORD=jWNuYSRslqKaUImy
set REDIS_PORT=16379
set QDRANT_API_KEY=rvA4U8P6ZNIceLgM
set ROCKETMQ_NAME_SERVER=127.0.0.1:9914

echo DB_USERNAME=%DB_USERNAME%
echo ROCKETMQ=%ROCKETMQ_NAME_SERVER%
echo ========================================
echo   Starting backend on port 9090
echo   Wait for "Started ServerApplication"
echo ========================================

call mvnw.cmd spring-boot:run
pause

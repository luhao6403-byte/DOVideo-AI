# DOVideo-AI 后端启动脚本（自动加载 .env）
$ErrorActionPreference = "Stop"

# 切换到项目根目录
Set-Location "C:\Users\35022\Doubao\chats\2026-09-12\new-chat\DOVideo-AI"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Loading .env ..." -ForegroundColor Cyan

# 加载 .env 到当前进程环境变量
Get-Content ".env" | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
        $idx = $line.IndexOf("=")
        $key = $line.Substring(0, $idx).Trim()
        $val = $line.Substring($idx + 1).Trim().Trim("'").Trim('"')
        [Environment]::SetEnvironmentVariable($key, $val, "Process")
    }
}

Write-Host "  DB_USERNAME = $env:DB_USERNAME" -ForegroundColor Green
Write-Host "  ROCKETMQ = $env:ROCKETMQ_NAME_SERVER" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Starting backend (port 9090)..." -ForegroundColor Cyan
Write-Host "  Wait for 'Started ServerApplication'" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan

# 启动后端
Set-Location "server"
& .\mvnw.cmd spring-boot:run

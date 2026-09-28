# Day1 学习笔记：用户模块与认证链路

## 学习日期
2026-09-29

## 核心结论
- 本项目用 Redis 会话 Token，不是 JWT。
- 密码用 PBKDF2WithHmacSHA256 存储，210000 次迭代，16 字节随机盐，256 bit 输出。
- 登录成功生成 32 字节随机 token，Redis 里存 `auth:session:<sha256(token)> -> userId`，TTL 24 小时。
- 想踢人下线 = 删除该 Redis key。
- 登录失败限流：`auth:login-failures:<username>`，10 分钟内超过 8 次返回 429。

## 注册链路
POST /user/register
  -> @Validated(Register) 参数校验
  -> AuthService.register
  -> normalizeUsername 规范化用户名
  -> 查重 username
  -> hashPassword 存 PBKDF2 哈希
  -> UserMapper.insert

## 登录链路
POST /user/login
  -> AuthService.login
  -> loginAttemptAllowed 限流检查
  -> UserMapper.selectOne 查用户
  -> passwordMatches 重算哈希并常量时间比较
  -> createSession 生成 token 并写入 Redis 24h
  -> 返回 token 给前端

## 受保护接口
GET /media/list
  -> AuthInterceptor.preHandle
  -> resolveUser(Authorization)
  -> sessionKey(token) 查 Redis
  -> 拿到 userId 放入 request attribute
  -> 控制器继续执行

## 为什么不用 JWT
- JWT 无状态，服务端无法主动吊销。
- Redis 会话可以删 key 实现踢人和退出。
- Redis 本来就在项目里负责限流、幂等、任务状态，会话也放 Redis 更自然。

## 注册参数校验
- 用户名：3-32 位，字母/数字/下划线。
- 密码：注册时 8-128 位；登录时只要求非空和不超过 128 位。
- 昵称：最多 50 位。
- 登录和注册用不同校验分组，避免历史弱密码账号无法登录。

## 统一响应
- `{ code, message, data }`
- `code == 0` 表示成功。
- 错误码前三位和 HTTP 对齐，后两位细分场景，例如 `UNAUTHORIZED(40100)`。
- 全局异常处理器统一转成 `Result`，避免接口手写状态和响应体。

## 前端 token 处理
- token 存 localStorage：`authToken`。
- `api.js` 每次请求自动加 `Authorization: Bearer <token>`。
- 收到 401 且不是 `/user/` 接口时清 token 并派发 `auth-expired` 事件。
- 非 JSON 响应（SSE、音频）原样透传，不触碰 body。

## 验证记录
- 2026-09-28 已用测试账号 coder_day1 / study123 跑通：
  注册 -> 登录 -> 带 token 调 /media/list

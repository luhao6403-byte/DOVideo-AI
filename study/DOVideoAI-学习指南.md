# DOVideoAI 七天学习指南（读源码版）

> 配套文件：`study/DOVideoAI-系统架构图.html`（浏览器打开）
> 仓库根目录：`C:\Users\35022\Doubao\chats\2026-09-12\new-chat\DOVideo-AI`
> 核对时间：2026-09-22（所有类名、路径、端口均以本机仓库实测为准）

---

## 0. 开局核验：与你原计划的 4 处差异（先改认知，再动手）

| # | 你的计划 | 仓库实际（已实测） | 影响 |
|---|---------|-------------------|------|
| 1 | JDK 17 | **JDK 21**（Spring Boot 3.5.9） | 本机已装 21.0.12，直接用 |
| 2 | JWT 登录 | **PBKDF2 密码哈希 + Redis 会话 Token**（24h 过期，服务端可吊销），另有登录失败限流 8 次/10 分钟 | Day1 重点改成看懂"Redis 会话方案"，面试反而更好讲 |
| 3 | 默认端口 | **全部非默认**：MySQL `3307`、Redis `16379`、RocketMQ `9914`、MinIO `9000/9001`、Qdrant `6333`、后端 `9090`、前端 `5173` | 配置错一个就连不上 |
| 4 | ASR 具体实现 | **硅基流动 `TeleAI/TeleSpeechASR`**（代码类名 `AliyunAsrUtils` 是历史遗留）；LLM 默认 `deepseek-ai/DeepSeek-V3.2`，走硅基 OpenAI 兼容端点；Embedding 用 `BAAI/bge-m3` | 密钥只填 `SILICONFLOW_API_KEY` 一个就够 |

**环境实测结果（本机已就绪 ✅）**：Docker 29.7.2 + Compose v5.5.1 / JDK 21.0.12 / Node 22.23.2 / FFmpeg 9.0.1 / Tesseract 5.4（已装 `chi_sim` + `eng` 语言包）。仓库自带 `mvnw`，不装 Maven 也能跑。

---

## 1. 全仓地图（先建立包结构心智模型）

```
DOVideo-AI/
├── README.md                    # 必读：含完整 mermaid 时序图
├── docker-compose.yml           # 5 个中间件编排（端口见上表）
├── .env.example                 # 复制成 .env 填密钥
├── start-backend.ps1 / run-backend.bat   # 作者给的启动脚本
├── scripts/dev-up.sh            # Linux/mac 中间件一键启动
├── server/src/main/java/com/example/server/
│   ├── ServerApplication.java   # 启动类
│   ├── controller/              # User / Media / Analysis / Admin / Health
│   ├── service/                 # 业务核心（见每日清单）
│   ├── service/mode/            # Agent 四模式路由
│   ├── mapper/ + entity/        # MyBatis-Plus
│   ├── repository/              # Checkpoint 持久化
│   ├── consumer/                # RocketMQ 消费者（解析入口）
│   ├── dto/                     # 所有传输/领域对象
│   ├── config/                  # AuthInterceptor / Minio / Redis / 线程池
│   ├── common/ + exception/     # Result 统一返回 / 错误码 / 异常
│   └── utils/                   # FFmpeg / ASR / OCR / Embedding / DeepSeek / Minio
├── server/src/main/resources/
│   ├── application.properties   # 全部配置项（含密钥注入点）
│   └── db/migration/            # Flyway：V1/V2/V3
├── server/src/test/             # 已有 3 个 Agent 相关单测（Day7 直接跑）
└── client/src/                  # Vue3 平铺结构
    ├── chunkUpload.js           # 5MB 分片切割 + 断点续传 + 进度
    ├── taskEvents.js + taskEventsPolicy.js   # SSE 接收 + 重连策略
    ├── useAnalysisWorkspace.js  # Agent 工作台
    ├── api.js                   # 所有 HTTP 请求
    └── App.vue                  # 登录/路由
```

**数据库 4 张表**（V1 建，V2/V3 加列）：`users`（PBKDF2 密码）、`media_files`（视频元数据+转写结果）、`agent_checkpoints`（Agent 断点，复合主键 media_id+checkpoint_key）、`failed_analysis_tasks`（失败任务，可重投）。

---

## 2. 七天每日清单（A：源码阅读清单 + C：自测题）

> 阅读规则：文件路径都从仓库根目录写起；先跑通功能再精读代码；卡壳超 2 小时就注释模块用 Mock 数据，Day7 回头补。

### Day 0（今晚）：前置准备

**要做的事**
1. `Copy-Item .env.example .env`，编辑 `.env`：改 `DB_PASSWORD`、`REDIS_PASSWORD`、`MINIO_SECRET_KEY`、`QDRANT_API_KEY` 为强密码，填 `SILICONFLOW_API_KEY`（硅基流动申请，控制台新建 API Key，免费额度够调试）
2. 启动中间件：`docker compose --env-file .env up -d`，然后 `docker compose --env-file .env ps` 确认 5 个服务 healthy（MySQL 启动最慢，等 20-30 秒）
3. 读 `README.md` 全文，重点看 mermaid 时序图，把主流程抄一遍：上传→MQ→消费→双分支解析→VideoContext→检索→Agent→SSE
4. 验证命令：`curl http://localhost:9090/health`（后端没启动会失败，Day1 再验）

**自测题**
- [ ] 本项目要求的 JDK 版本是多少？为什么不是 17？
- [ ] 5 个中间件各自的宿主机端口是多少？哪个和默认端口差别最大？
- [ ] `.env` 里必须配置的密钥有哪些？`SILICONFLOW_API_KEY` 一个 Key 能覆盖哪些能力（LLM/ASR/Embedding）？
- [ ] 后端、前端默认端口？Vite 代理配置在哪个文件、目标是什么？
- [ ] Flyway 的 `baseline-on-migrate=true` + `baseline-version=0` 是什么意思？为什么新库需要它？

---

### Day 1：源码骨架 & 用户模块 + Flyway

**上午：后端跑通**
1. 后端启动：`cd server; .\mvnw.cmd spring-boot:run`（Maven 镜像报错时按 README 用 `-s .mvn/central-settings.xml`）
2. 读包结构：`ServerApplication.java` → 看 `@MapperScan` 扫哪个包
3. 精读用户模块（按依赖顺序）：
   - `server/src/main/java/com/example/server/controller/UserController.java`（`/user/register` `/user/login` `/user/logout`）
   - `service/AuthService.java` —— **重点**：PBKDF2 210k 迭代、Redis 会话 Token（24h）、登录失败限流 8 次/10min，全程无 JWT
   - `dto/AuthRequest.java` / `AuthResponse.java` / `AuthData.java`
   - `entity/User.java` / `mapper/UserMapper.java`（MyBatis-Plus 用法）
   - `config/AuthInterceptor.java` + `config/WebConfig.java`（拦截器注册与放行规则）
   - `common/Result.java` / `common/ErrorCode.java` / `exception/BusinessException.java` / `controller/ApiExceptionHandler.java`
4. Flyway：`application.properties` 的 flyway 配置段 → `resources/db/migration/V1__create_core_tables.sql`（4 张表）→ V2/V3 增量脚本
5. Postman 调通：`POST /user/register` → `POST /user/login` 拿 token → 带 `Authorization: Bearer <token>` 调 `/media/list`

**下午：前端跑通**
1. `cd client; npm ci; npm run dev`，浏览器开 `http://localhost:5173`
2. 读 `client/src/api.js`（token 怎么存、请求头怎么带）和 `client/src/App.vue`（登录成功跳转逻辑）
3. 画出整体业务流程图（可参照架构图），把看不懂的类名记到本文件末尾的"待办清单"

**✅ 当日交付**：前后端都起来，能注册登录进主页；能说出 4 张表结构和"为什么用 Redis 会话而不是 JWT"

**自测题**
- [ ] 密码是怎么存储的？（算法+迭代次数+盐）为什么不能明文/MD5？
- [ ] 登录成功后 token 存哪里、有效期多久？服务端想踢人下线怎么做？
- [ ] AuthInterceptor 拦截了哪些路径？登录注册为什么能放行？token 校验失败返回什么？
- [ ] Flyway V1 建了哪几张表？`agent_checkpoints` 为什么用复合主键？
- [ ] 注册校验规则有哪些？（用户名长度、密码长度、失败限流）限流在 Redis 里怎么实现的？
- [ ] 统一返回结构 `Result` 长什么样？全局异常处理器捕获了哪几类异常？

---

### Day 2：文件上传 MinIO + 分片 + 断点续传

**上午：后端**
1. `controller/MediaController.java` 接口全览：`/media/init-upload` `/upload-status` `/upload-chunk` `/complete-upload` `/upload`（单文件兜底）
2. 精读 `service/ChunkUploadService.java` —— **重点**：分片接收→校验（大小/序号）→临时落盘→`complete-upload` 合并→`MinioUtils` 上传；注意 Redisson 锁怎么防止并发合并
3. `utils/MinioUtils.java` + `config/MinioConfig.java`（endpoint/ak/sk/bucket 注入）
4. `utils/AnalysisTaskKeys.java`（Redis 分片记录 key 设计，断点续传的数据结构）

**下午：前端 + 实测**
1. `client/src/chunkUpload.js` —— **重点**：`slice()` 按 5MB 切分、逐个上传、进度条百分比怎么算、断点怎么续（先查 `/upload-status` 跳过已传分片）
2. 上传一个真实视频，MinIO 控制台 `http://localhost:9001`（账号 `.env` 的 MINIO_ACCESS_KEY/SECRET_KEY）看 bucket `media` 里的文件
3. 手动断一次网/停掉前端，重传验证断点续传是否生效

**✅ 当日交付**：页面成功上传视频；能口述"分片上传→Redis 记进度→合并→MinIO"完整链路

**自测题**
- [ ] 分片大小多少、由谁决定？`init-upload` 返回什么给前端？
- [ ] `upload-status` 的作用？断点续传的原理（传了 3/8 片断了，重传怎么跳过）？
- [ ] 后端校验分片的哪些维度？合并时怎么保证分片顺序？
- [ ] 视频最终存在哪（MinIO bucket）？Redis 在这里存了哪些 key、生命周期多长？
- [ ] 单文件 `/media/upload` 和分片流程是什么关系？
- [ ] 合并分片为什么需要加锁？不加锁可能出什么问题？

---

### Day 3：视频解析流水线 FFmpeg + ASR + OCR

**上午：解析入口 + 音频/ASR**
1. `consumer/VideoAnalysisConsumer.java`（RocketMQ 消费入口，看消息体 `dto/AnalysisTaskMsg.java` 和任务状态流转）
2. `service/AnalysisDispatchService.java`（解析编排：双分支怎么调度）
3. `service/AudioExportService.java` —— **重点**：FFmpeg 命令怎么拼、60s 切片、15 分钟超时
4. `utils/AliyunAsrUtils.java`（硅基 TeleSpeechASR 调用，注意重试策略）+ `service/SegmentedTranscriptionService.java`（分段转写拼回时间戳）

**下午：视觉分支 + 入库 + 单测**
1. `service/VideoChunkingService.java` —— **重点**：FFmpeg 场景变化检测抽关键帧 + 30s 保底采样；`utils/OcrUtils.java`（tesseract chi_sim+eng 命令封装）
2. 相邻画面感知哈希去重逻辑（在 VideoChunkingService 或相关类里找）
3. 结果模型：`dto/TranscriptSegment.java` / `dto/VideoContext.java`（时间区间+ASR文本+OCR文本+关键帧的 unified segment）
4. 入库：`service/MediaService.java` 把 transcript_text/ai_summary/status 写回 MySQL
5. 写一个最小单测：参考 `server/src/test/java/com/example/server/service/AgentExecutionBudgetTest.java` 的写法，单独测 ASR 或 OCR 工具类（可用 Mock 输入）

**✅ 当日交付**：上传视频后自动完成 ASR+OCR，`media_files` 表能查到转写文本；能口述 FFmpeg 命令封装

**自测题**
- [ ] 谁触发了解析任务？为什么不在上传接口里同步解析？
- [ ] 音频切片策略？（时长/超时）关键帧策略？（场景检测+保底采样）
- [ ] ASR 用的什么模型、哪家平台？失败重试策略是什么？
- [ ] OCR 用的什么命令和语言包？相邻帧怎么去重、为什么省成本？
- [ ] VideoContext 里一个 segment 包含哪些字段？
- [ ] 双分支并行怎么实现？ASR 挂了 OCR 还能出结果吗？
- [ ] 解析结果写到 MySQL 的哪些字段？任务状态机怎么流转（UPLOADED→PROCESSING→COMPLETED/FAILED）？

---

### Day 4：大模型基础问答 + LangChain4j

**上午：后端调用**
1. `pom.xml` 确认 `langchain4j-open-ai` 依赖（用 OpenAI 兼容协议接硅基）
2. `service/AiService.java` —— **重点**：问答入口，Prompt 怎么组装（系统 Prompt 要求输出固定结构：结论+证据+建议）
3. `utils/DeepSeekUtils.java`：模型名、base-url、超时（`LLM_TIMEOUT_SECONDS=300`）、温度参数
4. `service/mode/ModeRouter.java` + `ModeRegistry.java` + `ModeProfile.java` —— **重点**：自动模式路由（GENERAL/LEARN/REVIEW/CREATE），路由失败回退 GENERAL

**下午：联调**
1. 前端 `client/src/useAnalysisWorkspace.js` + `api.js` 里问答请求的组装
2. 选择已解析视频提问，验证返回结构；换不同模式的目标（"帮我学习""帮我审查逻辑漏洞"）看产物差异
3. 小改造（可选）：改 `ModeProfile` 或系统 Prompt 里的某句要求，观察输出变化

**✅ 当日交付**：对已解析视频提问能拿到答案；掌握 LangChain4j 接 OpenAI 兼容 API 的写法

**自测题**
- [ ] 大模型调用入口在哪？LangChain4j 在这里封装了什么？
- [ ] 系统 Prompt 要求模型输出什么固定结构？为什么不能自由发挥？
- [ ] 四种分析模式各产出什么？路由怎么决策、失败怎么办？
- [ ] 模型/温度/超时在哪配置？默认模型名是什么？
- [ ] 怎么控制调用成本？（分块检索只带相关证据 + 预算参数）
- [ ] 不带任何检索，直接把整个转写文本丢给模型会有什么问题？（Token 超限、成本爆炸）

---

### Day 5：向量库 Qdrant & RAG 检索核心

**上午：入库链路**
1. `service/VideoChunkingService.java`（5 分钟分块 + 摘要 + 关键词生成）
2. `utils/EmbeddingUtils.java`（BGE-M3 通过硅基调用，看向量维度）
3. `service/QdrantVectorStore.java` —— **重点**：OkHttp 直连 Qdrant REST（upsert/query），collection 名 `video_chunks`，payload 里带什么元数据
4. 在 Qdrant 控制台/API 确认向量已写入：`curl http://localhost:6333/collections/video_chunks`

**下午：检索链路 + 对比实验**
1. `service/VideoEvidenceRetrievalService.java` —— **重点**：混合检索（关键词 + Qdrant 语义召回 TopK）+ `dto/VideoEvidenceHit.java`
2. 用户问题向量化 → Qdrant 相似度召回 → 片段+问题拼 Prompt（看 AiService 里怎么拼）
3. 做对比实验：同一问题，A 路直接问全文、B 路走 RAG，比较回答质量与 Token 消耗
4. 降级实验（可选）：临时把 `QDRANT_ENABLED=false` 重启，验证关键词降级路径

**✅ 当日交付**：RAG 问答正常，AI 只基于当前视频内容回答；理解"切分→向量化→召回→拼接"完整链路

**自测题**
- [ ] 文本怎么分块？每块带哪些元数据（时间范围/摘要/关键词）？
- [ ] Embedding 模型是什么、在哪调用？向量写进 Qdrant 哪个 collection？
- [ ] 检索时关键词和向量怎么混合？TopK 取多少？
- [ ] 为什么"问题向量化→召回 TopK→拼上下文"优于"全文本直接丢模型"？
- [ ] Qdrant 挂了系统会怎样？降级路径在哪实现？
- [ ] 检索到的证据怎么保证和用户问题相关？（相关性阈值/排序逻辑）
- [ ] 你能设计一个指标来对比"带 RAG"和"不带 RAG"的回答质量吗？

---

### Day 6：异步任务 RocketMQ + SSE + Redis 分布式锁

**上午：MQ 与状态机**
1. `controller/AnalysisController.java` / `MediaProcessingController.java`：任务提交接口，看返回（202 + 任务 ID）
2. `service/AnalysisDispatchService.java` —— **重点**：生产者发送 `AnalysisTaskMsg`，消息体字段
3. `consumer/VideoAnalysisConsumer.java` —— **重点**：消费幂等（Redisson 按 内容指纹+目标 加锁）、失败重试、死信 topic
4. `dto/TaskStatus.java` / `TaskStage.java` / `TaskEvent.java`：状态与阶段枚举

**下午：SSE + 锁 + 失败恢复**
1. `service/TaskEventService.java` + `config/TaskEventRedisConfig.java` —— **重点**：Redis Pub/Sub → 监听 → `SseEmitter` 推给前端；`utils/AnalysisTaskKeys.java` 的事件 key
2. 前端 `client/src/taskEvents.js` + `taskEventsPolicy.js`：SSE 怎么接、断线重连策略
3. `config/ThreadPoolConfig.java`：有界线程池参数（ASR/OCR 并行）
4. `service/FailedAnalysisTaskService.java` + `controller/AdminController.java`：失败任务重投
5. 实测：提交两个相同视频+相同目标，验证不会重复解析（观察 Redis 锁 key）

**✅ 当日交付**：提交任务后页面实时看到解析进度；重复提交不重复执行

**自测题**
- [ ] 任务提交后 HTTP 返回什么？为什么不等解析完再返回？
- [ ] 消息体 `AnalysisTaskMsg` 有哪些字段？Topic 和死信 Topic 是什么？
- [ ] 消费端怎么防重复？（锁的粒度是什么——"内容指纹+分析目标"）
- [ ] 任务状态有哪些？画出状态流转图
- [ ] SSE 底层链路是什么（Redis Pub/Sub 还是直接 SseEmitter）？为什么不用前端轮询？
- [ ] 前端断线怎么处理？（重连/去重策略在 taskEventsPolicy.js）
- [ ] 解析失败怎么兜底？（死信 + failed_analysis_tasks 表 + 管理接口重投）
- [ ] 用户级+全局令牌桶限流在哪个类实现？防的是什么？

---

### Day 7：Agent 模块 + 全链路联调 + 复盘

**上午：Agent 核心**
1. `service/AgentLoopService.java` —— **重点**：Planner→Executor→Critic 循环、最多 2 轮、每轮输出 `dto/AgentState.java`、反馈 `dto/AgentFeedback.java`
2. `service/EvidenceVerificationService.java` —— **重点**：时间戳证据校验（结论必须绑定 VideoContext 里的真实时间区间）
3. `service/AgentExecutionBudget.java` —— **重点**：轮数 2 / 时长 120s / Token 50000 的强制预算
4. `service/mode/` 四模式产物生成；`service/AgentCheckpointService.java` + `repository/AgentCheckpointRepository.java`（MySQL 真源 + Redis 热缓存）
5. 直接跑现有单测：`server\src\test\java\com\example\server\service\` 下 `AgentExecutionBudgetTest` / `EvidenceVerificationServiceTest` / `AgentCheckpointServiceTest`

**下午：全链路 + 复盘**
1. 完整走一遍：注册登录 → 上传视频 → 观察 SSE 进度 → RAG 问答 → Agent 多轮问答（含追问）
2. 记录 bug/优化点（启动报错、超时、Key 额度等），写进"项目复盘笔记"
3. 用架构图对着口述整套系统（10 分钟版），直到不看图能讲清

**✅ 当日交付**：完整吃透全部模块；能独立口述架构、技术难点、每处设计取舍

**自测题**
- [ ] Planner/Executor/Critic 各自职责？Critic 不通过时返回什么、触发什么动作？
- [ ] 时间戳证据校验的规则？（结论必须能定位到哪个时间区间，找不到会怎样）
- [ ] 预算控制有哪些维度、默认值？超了会发生什么？
- [ ] Checkpoint 断点恢复：MySQL 和 Redis 各存什么？为什么 MySQL 是"真源"？
- [ ] 三个现成单测分别测了什么逻辑？
- [ ] 全链路里哪个环节最容易失败？日志里怎么定位（health/日志关键字）？
- [ ] 如果让你加一个功能（如导出 PDF 报告），你会动哪几个类？
- [ ] 口述挑战：3 分钟内讲完"为什么这个项目要用 RocketMQ+Redis+Qdrant 三件套"

---

## 3. 设计思路速查表（面试核心素材，全部来自 README 与源码核实）

| 技术选型 | 为什么 | 不这样做的代价 |
|---------|--------|--------------|
| RocketMQ 异步解析 | 长视频解析分钟级，提交即返回 202，请求线程不被占住 | 同步处理：接口超时、并发一多就崩 |
| Redisson 分布式锁 | 按"内容指纹+分析目标"加锁，防并发与重复消费 | 同一视频重复解析=重复烧 ASR/LLM 钱 |
| Redis 会话 Token（非 JWT） | 服务端可控（可踢人、可限流计数），天然配合登录失败限流 | JWT 无法吊销，暴力破解难拦截 |
| 令牌桶限流（用户级+全局） | 控制第三方 AI 调用速率与成本 | API Key 额度被刷爆 |
| SSE 进度推送 | 解析阶段（上传/ASR/OCR/检索/Agent）实时可见，连接单向够用 | 轮询浪费请求、延迟高 |
| Qdrant + 关键词混合检索 | 语义召回 + 关键词兜底；Qdrant/Embedding 挂了降级到本地排序 | 纯语义：冷门词召回差；纯关键词：同义表达漏召回 |
| 60s 音频切片 + 关键帧（场景检测+30s 保底） | 长视频 ASR/OCR 成本与完整性平衡 | 整段 ASR：Token 爆炸；漏抽帧：板书/PPT 全丢 |
| 感知哈希帧去重 | 相邻画面几乎相同，去重省 OCR 次数 | OCR 成本翻倍 |
| 双分支并行 + 单路容错 | ASR 与 OCR 独立线程池，一路失败另一路仍有效 | 音轨坏/画面糊就全盘失败 |
| Agent 2 轮上限 + 预算控制 | 允许定向修正，同时约束延迟与 Token 成本 | 无限循环 = 延迟和账单失控 |
| Checkpoint 断点恢复 | MySQL 为恢复真源、Redis 为热缓存，失败不重算 | 解析到一半挂掉全部重来 |
| 统一 VideoContext 结构 | 语音/OCR/时间戳融合成统一段，检索与校验不再依赖底层模型格式 | 换 ASR 模型就要改全链路 |

---

## 4. 简历项目描述文案（B）

> 说明：你还没跑完，先用下面的底稿，Day7 复盘后按实际完成度微调"个人职责"与量化数字。括号内为需要你填的占位。

### 一句话定位
基于 SpringBoot + LangChain4j + Qdrant 实现的**长视频 Video RAG Agent 系统**：视频上传后自动完成多模态解析，支持带时间戳证据的 Agent 多轮问答。

### 项目描述（可直接放简历，约 130 字）
面向长视频内容理解的 Video RAG Agent 系统。视频经 FFmpeg 抽音频（60s 切片）与关键帧（场景检测+30s 保底），并行调用硅基 ASR 与 Tesseract OCR 生成时序多模态 VideoContext；文本按 5 分钟分块后生成摘要、关键词与 BGE-M3 Embedding 写入 Qdrant，问答时混合检索召回 TopK 证据；Agent 以 Planner-Executor-Critic 三轮闭环生成结论，每条结论绑定可核验的时间戳证据，并通过 RocketMQ 异步解析、Redis 会话鉴权与断点恢复、SSE 实时推送任务进度。

### 技术亮点（面试陈述用，5 条）
1. **大文件可靠上传**：前端 5MB 分片 + Redis 断点续传，弱网中断可续传，合并后入 MinIO。
2. **异步削峰与幂等**：RocketMQ 将解析任务剥离请求线程（提交即返回）；Redisson 按"内容指纹+分析目标"加锁，杜绝重复消费重复烧钱。
3. **多模态时序上下文**：FFmpeg 双分支（音频切片 + 关键帧抽取）并行解析，ASR/OCR 结果与时间戳融合为统一 VideoSegment，感知哈希去重省成本。
4. **混合检索 RAG**：Qdrant 语义召回 + 关键词匹配双通道，Qdrant 不可用时优雅降级，保证主链路不中断。
5. **有证据约束的 Agent**：Planner→Executor→Critic 闭环，Critic 校验目标覆盖与时间戳证据，不通过则定向补检；轮次/时长/Token 三重预算控制。

### 个人职责（Day7 后按真实情况填）
- 负责视频解析流水线的（ASR/OCR/FFmpeg 命令封装/入库）模块，独立调试硅基 ASR 接口与 Tesseract 中文识别参数
- 负责（RAG 检索链路 / Agent 循环 / SSE 进度推送）的源码走读与二次开发，完成小改造：（如修改抽帧频率 / 调整系统 Prompt / 增加某模式产物）
- 搭建本地环境（Docker Compose 编排 5 个中间件），定位并解决（XX 问题，如 RocketMQ 连接 / 模型超时）

### 3 分钟面试讲解结构
1. **一句话**：这是什么系统，解决什么问题（长视频 → 可检索可追溯的知识）。
2. **主链路 30 秒**：上传→MQ→双分支解析→VideoContext→分块向量化→混合检索→Agent→SSE。
3. **2 个技术难点深挖**：挑"异步幂等"和"证据约束 Agent"各讲 1 分钟（为什么这么做、不这么做会怎样）。
4. **1 个失败案例**：讲一个你实际踩的坑（如硅基模型被禁用返回 Model disabled、端口连错），展示排查过程。

### 高频追问预测（提前准备）
- 为什么用 Redis 会话不用 JWT？（可吊销/限流/防暴力破解）
- Qdrant 和 MySQL LIKE / Elasticsearch 的区别？（向量相似度 vs 关键词，语义召回）
- Agent 怎么防幻觉？（证据必须绑定时间戳区间，Critic 校验，不通过定向补检）
- RocketMQ 消费怎么保证不丢不重？（Redisson 幂等锁 + 死信 + failed 表重投）
- 长视频 2 小时，为什么不全量喂给模型？（Token 预算 50k，分块检索只带相关证据）

---

## 5. 每天看完后的小改造建议（任选其一加深理解）

| 天 | 小改造 | 改动位置 |
|----|--------|---------|
| 1 | 把会话有效期 24h 改成 1h 并重启验证 | `AuthService.java` 的 `SESSION_HOURS` |
| 2 | 分片大小 5MB 改成 2MB，验证断点续传仍正常 | `client/src/chunkUpload.js` |
| 3 | 关键帧保底采样 30s 改成 15s（成本翻倍观察） | `service/VideoChunkingService.java` |
| 4 | 改一条系统 Prompt 要求（如"必须用中文回答"） | `AiService.java` 或 `DeepSeekUtils.java` |
| 5 | 把 TopK 从 5 改成 10，对比回答变化 | `service/VideoEvidenceRetrievalService.java` |
| 6 | 令牌桶速率调小，观察限流生效 | 限流配置（`application.properties` 或对应类） |
| 7 | 给 Agent 加第 3 轮（改 `AGENT_MAX_ROUNDS`），观察成本 | `.env` |

---

## 6. 待办/疑问清单（读源码时随手记）

- [x] Day1 遗留看不懂的类：无（已按 Day1 清单读完）
- [x] Day3 需要新建的解析单测：`OcrUtilsTest`（server/src/test/java/com/example/server/utils/），2026-09-22 已通过
- [ ] 遇到的 bug/报错（现象→原因→解法）：______
- [ ] 简历量化数字（解析耗时 / 支持视频时长 / 提问响应时间）：______

---

## 7. Day3 实测勘误（2026-09-22 学习后补充，以本机仓库为准）

> 指南第 2 节 Day3 的类名/职责与实际源码有出入，按实测修正：

| 指南描述 | 实测位置 | 说明 |
|---------|---------|------|
| 双分支调度在 `AnalysisDispatchService` | `VideoContextService.build()`（`asrExecutor` + `ocrExecutor` 两个线程池并行） | `AnalysisDispatchService` 只负责投递 MQ + 令牌桶限流，不跑解析 |
| 关键帧抽取在 `VideoChunkingService` | `VideoContextService.extractKeyFrames()` | FFmpeg 滤镜 `select=eq(n\\,0)+gt(scene\\,0.35)+gte(t-prev_selected_t\\,30)`，`-fps_mode vfr`，showinfo 解析 pts_time |
| 感知哈希去重在"VideoChunkingService 或相关类" | `VideoContextService.differenceHash()` | 64 位 dHash（9×8 灰度相邻比较），Hamming 距离 ≤5 跳过相邻帧 |
| 入库（transcript_text/ai_summary）在 `MediaService` | `AiService.persistResult()`（transcript_text 在 asyncAnalyze 第 102 行写入） | `MediaService` 只管上传/列表/删除/哈希 |
| `VideoChunkingService` 是 Day3 内容 | 它是 **5 分钟文本分块 + 摘要 + 关键词 + Embedding**（实为 Day5 内容） | Day3 不要读它，Day5 再读 |
| 60s 切片在 `AudioExportService` | `SegmentedTranscriptionService.runFfmpeg()`：`ffmpeg -f segment -segment_time 60 -reset_timestamps 1 audio_%03d.mp3` | `AudioExportService` 只是整段转 MP3（`-q:a 2`，15 分钟超时） |
| ASR 类名 AliyunAsrUtils 是历史遗留 | 硅基 `TeleAI/TeleSpeechASR`，multipart 上传 + Bearer Key | 响应取 `text` 字段；空文本抛 IllegalStateException；仅 429/5xx 重试 3 次（退避 1s/2s） |

**实测结论（端到端已验证）**：
- 无语音视频（8s 测试片）：ASR 分支 `ASR 返回空文本` 失败 → OCR 分支单路出结果，Agent 照常完成（证据 `[00:30] OCR：…`）——双分支单路容错真实生效。
- 带人声视频（45s TTS 合成片）：`media_files` 表 `transcript_text` 写入 164 字完整转写，`ai_summary` 生成带 `[00:08]/[00:15]/[00:18]` 时间戳证据的结构化报告——全链路贯通。

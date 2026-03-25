# BabelDOC 翻译服务 API 接口文档

> **版本**: 1.0.0  
> **Base URL**: `http://<your-server>:8000`  
> **协议**: HTTP/HTTPS  
> **数据格式**: JSON

---

## 目录

1. [全局说明](#1-全局说明)
2. [健康检查 / 连通性](#2-健康检查--连通性)
3. [密钥验证](#3-密钥验证)
4. [获取上传地址](#4-获取上传地址)
5. [上传 PDF 文件](#5-上传-pdf-文件)
6. [创建翻译任务](#6-创建翻译任务)
7. [查询翻译进度](#7-查询翻译进度)
8. [获取翻译结果下载链接](#8-获取翻译结果下载链接)
9. [下载翻译后的 PDF](#9-下载翻译后的-pdf)
10. [翻译记录列表](#10-翻译记录列表)
11. [翻译计数](#11-翻译计数)
12. [完整调用流程](#12-完整调用流程)
13. [错误码说明](#13-错误码说明)
14. [环境变量配置](#14-环境变量配置)
15. [用量限制接入指南](#15-用量限制接入指南)

---

## 1. 全局说明

### 1.1 通用响应格式

**成功响应**:

```json
{
  "code": 0,
  "data": <any>
}
```

**错误响应**:

```json
{
  "code": 1,
  "message": "错误描述"
}
```

### 1.2 认证方式

所有需要认证的接口通过 HTTP Header 传递 Bearer Token：

```
Authorization: Bearer <AUTH_KEY>
```

- 如果服务端 `AUTH_KEY` 环境变量为空字符串，则**跳过认证**（所有请求均放行）。
- 如果设置了 `AUTH_KEY`，未提供或不匹配的 Token 将返回 `401` / `403`。

### 1.3 请求约定

- `Content-Type: application/json`（除上传接口外）
- 路径参数使用 `{param}` 表示
- 查询参数使用 `?key=value` 表示

---

## 2. 健康检查 / 连通性

### 2.1 服务根路径

```
GET /
```

**认证**: 不需要

**响应**:

```json
{
  "message": "BabelDOC Zotero API Server",
  "version": "1.0.0"
}
```

### 2.2 连通性检查

```
GET /connectivity_check
```

**认证**: 不需要

**响应**:

```json
{
  "status": "ok"
}
```

**用途**: 客户端启动时检测服务是否可达。

---

## 3. 密钥验证

```
GET /zotero/check-key
```

**认证**: 需要

**查询参数**:

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `apiKey` | string | 否 | 传入的 API Key（兼容字段，实际认证走 Header） |

**请求示例**:

```bash
curl -X GET "http://localhost:8000/zotero/check-key?apiKey=my-key" \
  -H "Authorization: Bearer <AUTH_KEY>"
```

**成功响应**:

```json
{
  "code": 0,
  "data": true
}
```

**错误响应**:

| HTTP 状态码 | 说明 |
|------------|------|
| 401 | 未提供 Authorization Header |
| 403 | Token 不匹配 |

---

## 4. 获取上传地址

```
GET /zotero/pdf-upload-url
```

**认证**: 需要

**说明**: 获取一个用于上传 PDF 文件的预签名 URL 和对象标识。客户端拿到后使用 PUT 方法将 PDF 二进制内容上传到该 URL。

**请求示例**:

```bash
curl -X GET "http://localhost:8000/zotero/pdf-upload-url" \
  -H "Authorization: Bearer <AUTH_KEY>"
```

**成功响应**:

```json
{
  "code": 0,
  "data": {
    "result": {
      "objectKey": "550e8400-e29b-41d4-a716-446655440000",
      "preSignedURL": "http://localhost:8000/zotero/upload/550e8400-e29b-41d4-a716-446655440000",
      "imgUrl": ""
    },
    "id": 0,
    "exception": "",
    "status": "ok",
    "isCanceled": false,
    "isCompleted": true,
    "isCompletedSuccessfully": true,
    "creationOptions": 0,
    "asyncState": null,
    "isFaulted": false
  }
}
```

**响应字段说明**:

| 字段 | 类型 | 说明 |
|------|------|------|
| `result.objectKey` | string (UUID) | 文件唯一标识，后续创建任务时需要传入 |
| `result.preSignedURL` | string | 文件上传目标 URL，使用 PUT 方法上传 |
| `result.imgUrl` | string | 预留字段，当前为空 |

---

## 5. 上传 PDF 文件

```
PUT /zotero/upload/{object_key}
```

**认证**: 不需要

**路径参数**:

| 参数 | 类型 | 说明 |
|------|------|------|
| `object_key` | string (UUID) | 由「获取上传地址」接口返回的 `objectKey` |

**请求头**:

```
Content-Type: application/pdf
```

**请求体**: PDF 文件的**原始二进制内容**（不是 multipart/form-data）

**请求示例**:

```bash
curl -X PUT "http://localhost:8000/zotero/upload/550e8400-e29b-41d4-a716-446655440000" \
  -H "Content-Type: application/pdf" \
  --data-binary @paper.pdf
```

**成功响应**:

```
HTTP/1.1 200 OK
```

（无 Body）

**错误响应**:

| HTTP 状态码 | 说明 |
|------------|------|
| 400 | 请求体为空（Empty body） |

---

## 6. 创建翻译任务

```
POST /zotero/backend-babel-pdf
```

**认证**: 需要

**请求头**:

```
Content-Type: application/json
Authorization: Bearer <AUTH_KEY>
```

**请求体**:

```json
{
  "objectKey": "550e8400-e29b-41d4-a716-446655440000",
  "fileName": "paper.pdf",
  "targetLanguage": "zh-CN",
  "requestModel": "",
  "enhance_compatibility": false,
  "OCRWorkaround": false,
  "autoEnableOcrWorkAround": false,
  "autoExtractGlossary": true,
  "disable_rich_text_translate": false,
  "primaryFontFamily": "",
  "dual_mode": "lort",
  "customSystemPrompt": null,
  "layout_model_id": "version_3",
  "pdfOptions": null
}
```

**请求字段说明**:

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `objectKey` | string | **是** | — | 上传文件时返回的文件标识 |
| `fileName` | string | 否 | `""` | 原始文件名（用于记录，不影响翻译） |
| `targetLanguage` | string | 否 | `"zh"` | 目标语言代码。常用值：`zh`、`zh-CN`、`zh-TW`、`ja`、`ko`、`fr`、`de`、`es`、`ru` |
| `requestModel` | string | 否 | `""` | 预留字段（当前翻译模型由服务端 `.env` 配置） |
| `enhance_compatibility` | bool | 否 | `false` | 增强 PDF 兼容性模式 |
| `OCRWorkaround` | bool | 否 | `false` | 启用 OCR 修复（针对扫描件 PDF） |
| `autoEnableOcrWorkAround` | bool | 否 | `false` | 自动检测并启用 OCR 修复 |
| `autoExtractGlossary` | bool | 否 | `true` | 自动提取术语表 |
| `disable_rich_text_translate` | bool | 否 | `false` | 禁用富文本翻译 |
| `primaryFontFamily` | string | 否 | `""` | 译文字体。可选值：`"serif"`、`"sans-serif"`、`"script"`，空或 `"none"` 为自动选择 |
| `dual_mode` | string | 否 | `"lort"` | 双语对照模式。`"lort"` = 左原文右译文，`"utdo"` / `"uodt"` = 上下交替 |
| `customSystemPrompt` | string\|null | 否 | `null` | 自定义翻译 System Prompt |
| `layout_model_id` | string | 否 | `"version_3"` | 版面分析模型版本 |
| `pdfOptions` | object\|null | 否 | `null` | 预留的 PDF 处理选项 |

**请求示例**:

```bash
curl -X POST "http://localhost:8000/zotero/backend-babel-pdf" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <AUTH_KEY>" \
  -d '{
    "objectKey": "550e8400-e29b-41d4-a716-446655440000",
    "fileName": "paper.pdf",
    "targetLanguage": "zh-CN",
    "autoExtractGlossary": true,
    "dual_mode": "lort"
  }'
```

**成功响应**:

```json
{
  "code": 0,
  "data": "9b2c19ad-ad0f-4210-8099-7aab7dfd4cc1"
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `data` | string (UUID) | 翻译任务 ID（`pdf_id`），用于后续查询进度和获取结果 |

**错误响应**:

| HTTP 状态码 | code | 说明 |
|------------|------|------|
| 404 | 1 | 未找到已上传的 PDF（`objectKey` 不存在） |
| 401 | — | 未认证 |
| 403 | — | 认证失败 |

---

## 7. 查询翻译进度

```
GET /zotero/pdf/{pdf_id}/process
```

**认证**: 需要

**路径参数**:

| 参数 | 类型 | 说明 |
|------|------|------|
| `pdf_id` | string (UUID) | 创建翻译任务时返回的任务 ID |

**请求示例**:

```bash
curl -X GET "http://localhost:8000/zotero/pdf/9b2c19ad-ad0f-4210-8099-7aab7dfd4cc1/process" \
  -H "Authorization: Bearer <AUTH_KEY>"
```

**成功响应**:

```json
{
  "code": 0,
  "data": {
    "overall_progress": 65,
    "currentStageName": "translating",
    "status": "ok",
    "message": "",
    "num_pages": 0
  }
}
```

**响应字段说明**:

| 字段 | 类型 | 说明 |
|------|------|------|
| `overall_progress` | int (0-100) | 翻译总进度百分比。`0` = 刚开始，`1-99` = 进行中，`100` = 完成 |
| `currentStageName` | string | 当前阶段名称。可能的值：`"queued"`、`"translating"`、`"completed"` 等 |
| `status` | string | 任务状态。`"ok"` = 正常/已完成，`"error"` = 失败 |
| `message` | string | 错误信息（仅在 `status == "error"` 时有值） |
| `num_pages` | int | 页数（预留字段，当前为 0） |

**轮询策略建议**:

- 建议每 **2-3 秒** 轮询一次
- 当 `overall_progress == 100` 且 `status == "ok"` 时表示翻译完成，可以请求下载链接
- 当 `status == "error"` 时停止轮询，读取 `message` 获取错误原因

**任务状态流转**:

```
queued → translating → completed (progress: 100)
                    ↘ error
```

**错误响应**:

| HTTP 状态码 | code | 说明 |
|------------|------|------|
| 404 | 1 | 任务不存在 |

---

## 8. 获取翻译结果下载链接

```
GET /zotero/pdf/{pdf_id}/temp-url
```

**认证**: 需要

**前置条件**: 翻译进度 `overall_progress == 100` 且 `status == "ok"`

**路径参数**:

| 参数 | 类型 | 说明 |
|------|------|------|
| `pdf_id` | string (UUID) | 翻译任务 ID |

**请求示例**:

```bash
curl -X GET "http://localhost:8000/zotero/pdf/9b2c19ad-ad0f-4210-8099-7aab7dfd4cc1/temp-url" \
  -H "Authorization: Bearer <AUTH_KEY>"
```

**成功响应**:

```json
{
  "code": 0,
  "data": {
    "translationDualPdfOssUrl": "http://localhost:8000/zotero/download/9b2c19ad-ad0f-4210-8099-7aab7dfd4cc1/xxx.no_watermark.zh-CN.dual.pdf",
    "translationOnlyPdfOssUrl": "http://localhost:8000/zotero/download/9b2c19ad-ad0f-4210-8099-7aab7dfd4cc1/xxx.no_watermark.zh-CN.mono.pdf",
    "waterMask": false,
    "monoFileUrl": ""
  }
}
```

**响应字段说明**:

| 字段 | 类型 | 说明 |
|------|------|------|
| `translationDualPdfOssUrl` | string | **双语对照 PDF** 下载链接（原文+译文交替/并排） |
| `translationOnlyPdfOssUrl` | string | **纯译文 PDF** 下载链接（仅翻译后的内容） |
| `waterMask` | bool | 是否有水印（当前始终为 `false`） |
| `monoFileUrl` | string | 预留字段，当前为空 |

**错误响应**:

| HTTP 状态码 | code | 说明 |
|------------|------|------|
| 400 | 1 | 翻译尚未完成 |
| 404 | 1 | 任务不存在 |

---

## 9. 下载翻译后的 PDF

```
GET /zotero/download/{pdf_id}/{filename}
```

**认证**: 不需要

**路径参数**:

| 参数 | 类型 | 说明 |
|------|------|------|
| `pdf_id` | string (UUID) | 翻译任务 ID |
| `filename` | string | PDF 文件名（从 `temp-url` 接口的链接中提取） |

**请求示例**:

```bash
curl -X GET "http://localhost:8000/zotero/download/9b2c19ad-ad0f-4210-8099-7aab7dfd4cc1/xxx.no_watermark.zh-CN.dual.pdf" \
  -o translated.pdf
```

**成功响应**:

```
HTTP/1.1 200 OK
Content-Type: application/pdf
Content-Disposition: attachment; filename="xxx.no_watermark.zh-CN.dual.pdf"

<PDF 二进制内容>
```

**文件名命名规则**:

```
{objectKey}.no_watermark.{targetLanguage}.{type}.pdf
```

- `type` = `mono`（纯译文）或 `dual`（双语对照）

**错误响应**:

| HTTP 状态码 | 说明 |
|------------|------|
| 404 | 任务不存在或文件不存在 |

---

## 10. 翻译记录列表

```
GET /zotero/pdf/record-list
```

**认证**: 需要

**查询参数**:

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `page` | int | 否 | `1` | 页码 |
| `pageSize` | int | 否 | `20` | 每页条数 |

**请求示例**:

```bash
curl -X GET "http://localhost:8000/zotero/pdf/record-list?page=1&pageSize=20" \
  -H "Authorization: Bearer <AUTH_KEY>"
```

**成功响应**:

```json
{
  "code": 0,
  "data": {
    "total": 0,
    "list": []
  }
}
```

> **注意**: 当前版本未实现持久化存储，此接口始终返回空列表。

---

## 11. 翻译计数

```
GET /zotero/pdf-count
```

**认证**: 需要

**请求示例**:

```bash
curl -X GET "http://localhost:8000/zotero/pdf-count" \
  -H "Authorization: Bearer <AUTH_KEY>"
```

**成功响应**:

```json
{
  "code": 0,
  "data": 0
}
```

> **注意**: 当前版本未实现持久化计数，此接口始终返回 0。

---

## 12. 完整调用流程

### 12.1 流程图

```
┌────────────────────────────────────────────────────────────────┐
│                        客户端调用流程                            │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  Step 1: 连通性检查                                              │
│  GET /connectivity_check                                       │
│  └─→ {"status": "ok"}                                         │
│                                                                │
│  Step 2: 验证密钥（可选）                                         │
│  GET /zotero/check-key?apiKey=xxx                              │
│  └─→ {"code": 0, "data": true}                                │
│                                                                │
│  Step 3: 获取上传地址                                             │
│  GET /zotero/pdf-upload-url                                    │
│  └─→ 拿到 objectKey + preSignedURL                              │
│                                                                │
│  Step 4: 上传 PDF                                               │
│  PUT {preSignedURL}                                            │
│  Body: PDF 二进制                                                │
│  └─→ 200 OK                                                   │
│                                                                │
│  Step 5: 创建翻译任务                                             │
│  POST /zotero/backend-babel-pdf                                │
│  Body: {"objectKey": "...", "targetLanguage": "zh-CN", ...}    │
│  └─→ 拿到 pdf_id                                               │
│                                                                │
│  Step 6: 轮询翻译进度（每 2-3 秒）                                 │
│  GET /zotero/pdf/{pdf_id}/process                              │
│  └─→ overall_progress: 0 → 99 → 100                           │
│                                                                │
│  Step 7: 获取下载链接（progress == 100 时）                        │
│  GET /zotero/pdf/{pdf_id}/temp-url                             │
│  └─→ 拿到 dual / mono PDF URL                                  │
│                                                                │
│  Step 8: 下载文件                                                │
│  GET /zotero/download/{pdf_id}/{filename}                      │
│  └─→ PDF 文件流                                                 │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### 12.2 代码示例（Python）

```python
import time
import requests

BASE_URL = "http://localhost:8000"
AUTH_KEY = "your-auth-key"  # 如果服务端未设置，可以留空
HEADERS = {"Authorization": f"Bearer {AUTH_KEY}"}


def translate_pdf(pdf_path: str, target_lang: str = "zh-CN") -> dict:
    """完整翻译一个 PDF 文件并返回下载链接。"""

    # Step 1: 获取上传地址
    resp = requests.get(f"{BASE_URL}/zotero/pdf-upload-url", headers=HEADERS)
    resp.raise_for_status()
    upload_data = resp.json()["data"]["result"]
    object_key = upload_data["objectKey"]
    upload_url = upload_data["preSignedURL"]

    # Step 2: 上传 PDF
    with open(pdf_path, "rb") as f:
        resp = requests.put(upload_url, data=f.read(),
                            headers={"Content-Type": "application/pdf"})
        resp.raise_for_status()

    # Step 3: 创建翻译任务
    resp = requests.post(f"{BASE_URL}/zotero/backend-babel-pdf",
                         json={
                             "objectKey": object_key,
                             "fileName": pdf_path.split("/")[-1],
                             "targetLanguage": target_lang,
                             "autoExtractGlossary": True,
                             "dual_mode": "lort",
                         },
                         headers={**HEADERS, "Content-Type": "application/json"})
    resp.raise_for_status()
    pdf_id = resp.json()["data"]
    print(f"任务已创建: {pdf_id}")

    # Step 4: 轮询进度
    while True:
        resp = requests.get(f"{BASE_URL}/zotero/pdf/{pdf_id}/process",
                            headers=HEADERS)
        resp.raise_for_status()
        status_data = resp.json()["data"]

        progress = status_data["overall_progress"]
        stage = status_data["currentStageName"]
        print(f"  进度: {progress}% | 阶段: {stage}")

        if status_data["status"] == "error":
            raise RuntimeError(f"翻译失败: {status_data['message']}")

        if progress >= 100:
            break

        time.sleep(3)

    # Step 5: 获取下载链接
    resp = requests.get(f"{BASE_URL}/zotero/pdf/{pdf_id}/temp-url",
                        headers=HEADERS)
    resp.raise_for_status()
    result = resp.json()["data"]

    return {
        "dual_pdf_url": result["translationDualPdfOssUrl"],
        "mono_pdf_url": result["translationOnlyPdfOssUrl"],
    }


def download_file(url: str, save_path: str):
    """下载文件到本地。"""
    resp = requests.get(url, stream=True)
    resp.raise_for_status()
    with open(save_path, "wb") as f:
        for chunk in resp.iter_content(chunk_size=8192):
            f.write(chunk)
    print(f"已保存: {save_path}")


# 使用示例
if __name__ == "__main__":
    result = translate_pdf("paper.pdf", target_lang="zh-CN")
    download_file(result["dual_pdf_url"], "paper_dual.pdf")
    download_file(result["mono_pdf_url"], "paper_mono.pdf")
```

### 12.3 代码示例（Node.js / TypeScript）

```typescript
import fs from "fs";

const BASE_URL = "http://localhost:8000";
const AUTH_KEY = "your-auth-key";
const HEADERS = { Authorization: `Bearer ${AUTH_KEY}` };

async function translatePdf(
  pdfPath: string,
  targetLang = "zh-CN"
): Promise<{ dualUrl: string; monoUrl: string }> {
  // Step 1: 获取上传地址
  const uploadRes = await fetch(`${BASE_URL}/zotero/pdf-upload-url`, {
    headers: HEADERS,
  });
  const uploadData = (await uploadRes.json()).data.result;
  const { objectKey, preSignedURL } = uploadData;

  // Step 2: 上传 PDF
  const pdfBuffer = fs.readFileSync(pdfPath);
  await fetch(preSignedURL, {
    method: "PUT",
    body: pdfBuffer,
    headers: { "Content-Type": "application/pdf" },
  });

  // Step 3: 创建翻译任务
  const taskRes = await fetch(`${BASE_URL}/zotero/backend-babel-pdf`, {
    method: "POST",
    headers: { ...HEADERS, "Content-Type": "application/json" },
    body: JSON.stringify({
      objectKey,
      fileName: pdfPath.split("/").pop(),
      targetLanguage: targetLang,
      autoExtractGlossary: true,
      dual_mode: "lort",
    }),
  });
  const pdfId: string = (await taskRes.json()).data;
  console.log(`任务已创建: ${pdfId}`);

  // Step 4: 轮询进度
  while (true) {
    const statusRes = await fetch(
      `${BASE_URL}/zotero/pdf/${pdfId}/process`,
      { headers: HEADERS }
    );
    const statusData = (await statusRes.json()).data;

    console.log(
      `  进度: ${statusData.overall_progress}% | 阶段: ${statusData.currentStageName}`
    );

    if (statusData.status === "error") {
      throw new Error(`翻译失败: ${statusData.message}`);
    }
    if (statusData.overall_progress >= 100) break;

    await new Promise((r) => setTimeout(r, 3000));
  }

  // Step 5: 获取下载链接
  const resultRes = await fetch(
    `${BASE_URL}/zotero/pdf/${pdfId}/temp-url`,
    { headers: HEADERS }
  );
  const result = (await resultRes.json()).data;

  return {
    dualUrl: result.translationDualPdfOssUrl,
    monoUrl: result.translationOnlyPdfOssUrl,
  };
}
```

### 12.4 代码示例（cURL 脚本）

```bash
#!/bin/bash
BASE_URL="http://localhost:8000"
AUTH="Authorization: Bearer your-auth-key"
PDF_FILE="paper.pdf"

# Step 1: 获取上传地址
echo ">>> 获取上传地址..."
UPLOAD_RESP=$(curl -s -H "$AUTH" "$BASE_URL/zotero/pdf-upload-url")
OBJECT_KEY=$(echo "$UPLOAD_RESP" | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['result']['objectKey'])")
UPLOAD_URL=$(echo "$UPLOAD_RESP" | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['result']['preSignedURL'])")
echo "    objectKey: $OBJECT_KEY"

# Step 2: 上传 PDF
echo ">>> 上传 PDF..."
curl -s -X PUT "$UPLOAD_URL" \
  -H "Content-Type: application/pdf" \
  --data-binary @"$PDF_FILE"
echo "    上传完成"

# Step 3: 创建翻译任务
echo ">>> 创建翻译任务..."
TASK_RESP=$(curl -s -X POST "$BASE_URL/zotero/backend-babel-pdf" \
  -H "$AUTH" \
  -H "Content-Type: application/json" \
  -d "{\"objectKey\":\"$OBJECT_KEY\",\"targetLanguage\":\"zh-CN\",\"dual_mode\":\"lort\"}")
PDF_ID=$(echo "$TASK_RESP" | python3 -c "import json,sys; print(json.load(sys.stdin)['data'])")
echo "    任务 ID: $PDF_ID"

# Step 4: 轮询进度
echo ">>> 等待翻译完成..."
while true; do
  STATUS=$(curl -s -H "$AUTH" "$BASE_URL/zotero/pdf/$PDF_ID/process")
  PROGRESS=$(echo "$STATUS" | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['overall_progress'])")
  STAGE=$(echo "$STATUS" | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['currentStageName'])")
  echo "    进度: ${PROGRESS}% | 阶段: $STAGE"
  [ "$PROGRESS" = "100" ] && break
  sleep 3
done

# Step 5: 获取下载链接
echo ">>> 获取下载链接..."
RESULT=$(curl -s -H "$AUTH" "$BASE_URL/zotero/pdf/$PDF_ID/temp-url")
DUAL_URL=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['translationDualPdfOssUrl'])")
MONO_URL=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['translationOnlyPdfOssUrl'])")

# Step 6: 下载
echo ">>> 下载翻译结果..."
curl -s -o "paper_dual.pdf" "$DUAL_URL"
curl -s -o "paper_mono.pdf" "$MONO_URL"
echo ">>> 完成！"
```

---

## 13. 错误码说明

### 13.1 业务错误码（`code` 字段）

| code | 说明 |
|------|------|
| `0` | 成功 |
| `1` | 通用业务错误（详见 `message` 字段） |

### 13.2 HTTP 状态码

| HTTP 状态码 | 场景 |
|------------|------|
| 200 | 成功 |
| 400 | 请求参数错误 / 翻译未完成就请求下载 / 空文件上传 |
| 401 | 未提供 Authorization Header |
| 403 | Token 验证失败 |
| 404 | 任务不存在 / 文件不存在 / objectKey 无效 |
| 500 | 服务内部错误 |

### 13.3 翻译任务 status 枚举

| status | 说明 |
|--------|------|
| `"ok"` | 正常运行中 或 翻译成功完成 |
| `"error"` | 翻译失败，错误原因见 `message` |

---

## 14. 环境变量配置

服务端通过 `.env` 文件配置：

| 变量 | 必填 | 默认值 | 说明 |
|------|------|--------|------|
| `OPENAI_API_KEY` | **是** | — | LLM API Key |
| `OPENAI_BASE_URL` | 否 | `https://api.openai.com/v1` | LLM API 地址（兼容 OpenAI 格式的任意服务） |
| `OPENAI_MODEL` | 否 | `gpt-4o-mini` | 翻译使用的模型名称 |
| `SERVER_HOST` | 否 | `http://localhost:8000` | 服务对外可达地址（用于生成下载链接） |
| `LANG_IN` | 否 | `en` | 源语言（全局默认值） |
| `QPS` | 否 | `4` | 翻译 API 并发请求数 |
| `AUTH_KEY` | 否 | `""` | 接口认证密钥。为空则不启用认证 |
| `UPLOAD_DIR` | 否 | `./data/uploads` | PDF 上传存储路径 |
| `OUTPUT_DIR` | 否 | `./data/output` | 翻译输出存储路径 |

### 14.1 支持的目标语言代码

| 代码 | 语言 |
|------|------|
| `zh` / `zh-CN` | 简体中文 |
| `zh-TW` | 繁体中文 |
| `en` | 英语 |
| `ja` | 日语 |
| `ko` | 韩语 |
| `fr` | 法语 |
| `de` | 德语 |
| `es` | 西班牙语 |
| `ru` | 俄语 |
| `pt` | 葡萄牙语 |
| `it` | 意大利语 |
| `ar` | 阿拉伯语 |

---

## 15. 用量限制接入指南

BabelDOC 翻译服务本身**不实现用户配额逻辑**，配额管控由上游的统一 API 网关/中转服务负责。本节说明对接方如何正确实施**按用户限制 PDF 翻译数量**的策略。

### 15.1 限制维度

**限制的是"翻译 PDF 的篇数"，不是 API 请求数。**

一次完整的 PDF 翻译涉及 5+ 次 API 调用（获取上传地址、上传文件、创建任务、轮询进度、获取下载链接、下载文件），但这些调用都为同一篇 PDF 服务，应该只计为 **1 次翻译**。

### 15.2 计量节点

在整个调用链中，**只需要在一个接口上做计量拦截**：

```
POST /zotero/backend-babel-pdf    ← 唯一的计量点
```

**原因**：
- 这是创建翻译任务的唯一入口
- 一次调用 = 一篇 PDF 翻译
- 调用成功后返回 `pdf_id`，后续所有操作都围绕这个 ID
- 上传文件、轮询进度、下载结果等接口无需单独计量

**不应该限制的接口**：

| 接口 | 原因 |
|------|------|
| `GET /zotero/pdf-upload-url` | 获取上传地址不代表会实际翻译 |
| `PUT /zotero/upload/{object_key}` | 上传文件不代表会创建任务 |
| `GET /zotero/pdf/{pdf_id}/process` | 轮询进度，同一篇 PDF 会调用几十次 |
| `GET /zotero/pdf/{pdf_id}/temp-url` | 获取下载链接，属于翻译结果的一部分 |
| `GET /zotero/download/{pdf_id}/{filename}` | 下载文件，属于翻译结果的一部分 |

### 15.3 推荐的计量实现方式

#### 方式 A：网关层前置拦截（推荐）

在统一 API 网关中，针对 `POST /zotero/backend-babel-pdf` 做前置拦截：

```
客户端 → API 网关（计量 + 鉴权） → BabelDOC 服务
```

```python
# 网关伪代码
@app.post("/zotero/backend-babel-pdf")
async def proxy_create_task(request, user_id: str):
    # 1. 查询用户剩余额度
    quota = get_user_quota(user_id)
    if quota.used >= quota.limit:
        return {"code": 4029, "message": "翻译额度已用完"}

    # 2. 转发请求到 BabelDOC 服务
    response = await forward_to_babeldoc(request)

    # 3. 创建成功后才扣减额度
    if response["code"] == 0:
        increment_user_usage(user_id)

    return response
```

**关键点**：只在 BabelDOC 返回 `code: 0`（任务创建成功）后才扣减额度，避免因上游错误导致误扣。

#### 方式 B：回调式计量

如果网关不方便做同步拦截，可以异步计量：

```
客户端 → BabelDOC 服务 → 翻译完成
                             ↓
                      网关轮询 /process
                             ↓
                   progress == 100 → 计量 +1
```

这种方式只对**翻译成功完成**的 PDF 计量，更精确但实现更复杂。

### 15.4 计量字段参考

中转服务需要记录的字段：

| 字段 | 来源 | 说明 |
|------|------|------|
| `user_id` | 网关自行管理 | 用户唯一标识 |
| `pdf_id` | `POST /zotero/backend-babel-pdf` 响应的 `data` | 翻译任务 ID |
| `created_at` | 网关记录 | 任务创建时间（用于按周期统计） |
| `status` | `GET /zotero/pdf/{pdf_id}/process` 的 `status` | 任务最终状态（`ok` / `error`） |
| `file_name` | 请求体的 `fileName` | 原始文件名（用于展示） |
| `target_language` | 请求体的 `targetLanguage` | 目标语言 |

### 15.5 配额周期建议

| 周期 | 说明 | 适用场景 |
|------|------|---------|
| `monthly` | 每月 1 日 00:00 重置 | 订阅制用户 |
| `daily` | 每日 00:00 重置 | 免费试用用户 |
| `total` | 不重置，用完即止 | 一次性额度包 |

### 15.6 配额不足时的建议响应

当用户额度用完时，网关应返回以下格式（与 BabelDOC 的错误响应格式一致）：

```json
{
  "code": 4029,
  "message": "翻译额度已用完，本月已翻译 50/50 篇。请升级套餐或等待下月重置。"
}
```

建议使用 HTTP 状态码 `429 Too Many Requests`。

### 15.7 请求头传递用户标识

网关转发请求到 BabelDOC 时，建议通过自定义请求头传递用户信息（BabelDOC 服务会忽略这些头，不影响功能）：

```
X-User-Id: user_12345
X-User-Plan: pro
X-Quota-Remaining: 42
```

这样在 BabelDOC 的日志中也能追踪到是哪个用户的请求。

### 15.8 完整计量流程图

```
┌─────────┐     ┌──────────────┐     ┌─────────────────┐
│  客户端   │────→│  API 网关     │────→│  BabelDOC 服务   │
│ (Zotero) │     │ (配额管控)    │     │  (纯翻译引擎)    │
└─────────┘     └──────────────┘     └─────────────────┘
                       │
                 ┌─────┴─────┐
                 │  配额检查   │
                 │           │
           额度充足？        │
            ├── 是 ──→ 转发请求到 BabelDOC
            │              │
            │        创建成功？(code==0)
            │          ├── 是 ──→ 扣减额度，返回 pdf_id
            │          └── 否 ──→ 不扣减，透传错误
            │
            └── 否 ──→ 返回 429 + "额度已用完"
```

---

## 附录：接口速查表

| 方法 | 路径 | 认证 | 说明 |
|------|------|------|------|
| GET | `/` | 否 | 服务信息 |
| GET | `/connectivity_check` | 否 | 连通性检查 |
| GET | `/zotero/check-key` | 是 | 验证密钥 |
| GET | `/zotero/pdf-upload-url` | 是 | 获取上传地址 |
| PUT | `/zotero/upload/{object_key}` | 否 | 上传 PDF |
| POST | `/zotero/backend-babel-pdf` | 是 | 创建翻译任务 |
| GET | `/zotero/pdf/{pdf_id}/process` | 是 | 查询翻译进度 |
| GET | `/zotero/pdf/{pdf_id}/temp-url` | 是 | 获取下载链接 |
| GET | `/zotero/download/{pdf_id}/{filename}` | 否 | 下载 PDF |
| GET | `/zotero/pdf/record-list` | 是 | 翻译记录列表 |
| GET | `/zotero/pdf-count` | 是 | 翻译计数 |

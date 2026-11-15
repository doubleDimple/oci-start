export type HttpMethod = 'GET' | 'POST'
export type OpenApiLocale = 'zh' | 'en'

export interface OpenApiParam {
  name: string
  in: 'query' | 'header'
  type: 'integer' | 'string' | 'boolean'
  required: boolean
  defaultValue: string
  description: Record<OpenApiLocale, string>
}

export interface OpenApiBodyField {
  name: string
  type: string
  required: boolean
  description: Record<OpenApiLocale, string>
}

export interface OpenApiEndpoint {
  id: string
  group: 'ai' | 'storage'
  method: HttpMethod
  path: string
  summary: Record<OpenApiLocale, string>
  description: Record<OpenApiLocale, string>
  auditTitle: string
  supportsStream?: boolean
  parameters: OpenApiParam[]
  bodyFields: OpenApiBodyField[]
  defaultBody?: Record<string, unknown>
  responseExample: string
  streamExample?: string
}

export const OPEN_API_GROUPS: Record<'ai' | 'storage', Record<OpenApiLocale, string>> = {
  ai: { zh: 'AI 与 OpenAI 兼容接口', en: 'AI & OpenAI-compatible' },
  storage: { zh: 'OCI 对象存储接口', en: 'OCI Object Storage' },
}

export const OPEN_API_ENDPOINTS: readonly OpenApiEndpoint[] = [
  {
    id: 'ai-chat',
    group: 'ai',
    method: 'POST',
    path: '/oci-start/open-api/v1/chat',
    summary: { zh: 'AI 对话', en: 'AI chat' },
    description: {
      zh: '使用已配置的 AI 模型发起单轮或多轮对话请求，返回统一 ApiResponse 结构。',
      en: 'Send a chat prompt using the configured AI service and receive an ApiResponse envelope.',
    },
    auditTitle: 'ai聊天',
    parameters: [],
    bodyFields: [
      { name: 'userId', type: 'string', required: true, description: { zh: '调用方用户唯一标识', en: 'Caller unique user identifier' } },
      { name: 'message', type: 'string', required: true, description: { zh: '输入的消息内容', en: 'User prompt message' } },
    ],
    defaultBody: {
      userId: 'user_12345',
      message: '你好，请介绍一下当前支持的功能',
    },
    responseExample: JSON.stringify({
      success: true,
      code: 200,
      message: 'success',
      data: '你好！我可以协助完成对话问答与资源信息查询。',
    }, null, 2),
  },
  {
    id: 'openai-chat-completions',
    group: 'ai',
    method: 'POST',
    path: '/oci-start/open-api/v1/chat/completions',
    summary: { zh: 'OpenAI 兼容对话', en: 'OpenAI chat completions' },
    description: {
      zh: '完全兼容 OpenAI `/v1/chat/completions` 请求与响应格式，支持 `stream: true`（SSE 流式）和 `stream: false`（一次性 JSON）。',
      en: 'OpenAI-compatible `/v1/chat/completions` endpoint supporting both `stream: true` (SSE) and `stream: false` JSON responses.',
    },
    auditTitle: 'OpenAI兼容聊天接口',
    supportsStream: true,
    parameters: [
      {
        name: 'X-User-Id',
        in: 'header',
        type: 'string',
        required: false,
        defaultValue: 'admin',
        description: { zh: '可选会话用户标识，默认 admin', en: 'Optional caller user identifier (defaults to admin)' },
      },
    ],
    bodyFields: [
      { name: 'model', type: 'string', required: true, description: { zh: '模型 ID（可通过 /models 获取）', en: 'Target model ID from /models' } },
      { name: 'messages', type: 'array<ChatMessage>', required: true, description: { zh: '标准 OpenAI 消息列表（role / content）', en: 'OpenAI chat messages array (role / content)' } },
      { name: 'stream', type: 'boolean', required: false, description: { zh: '是否开启 SSE 流式输出', en: 'Enable Server-Sent Events streaming' } },
      { name: 'temperature', type: 'number', required: false, description: { zh: '采样温度（0 ~ 2）', en: 'Sampling temperature (0 to 2)' } },
      { name: 'max_tokens', type: 'integer', required: false, description: { zh: '最大生成 Token 数', en: 'Maximum generated tokens' } },
      { name: 'tools', type: 'array<Tool>', required: false, description: { zh: '可选 Function Calling 工具定义列表', en: 'Optional tool function definitions' } },
      { name: 'tool_choice', type: 'object | string', required: false, description: { zh: '可选工具调用策略', en: 'Optional tool selection strategy' } },
    ],
    defaultBody: {
      model: 'gpt-4o-mini',
      messages: [
        { role: 'system', content: 'You are a helpful assistant.' },
        { role: 'user', content: 'Hello! Reply with one short sentence.' },
      ],
      stream: false,
      temperature: 0.7,
    },
    responseExample: JSON.stringify({
      id: 'chatcmpl-9x123456',
      object: 'chat.completion',
      created: 1763164800,
      model: 'gpt-4o-mini',
      choices: [
        {
          index: 0,
          message: { role: 'assistant', content: 'Hello! Everything is ready.' },
          finish_reason: 'stop',
        },
      ],
    }, null, 2),
    streamExample: [
      'data: {"id":"chatcmpl-9x123","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"role":"assistant","content":"Hello"}}]}',
      '',
      'data: {"id":"chatcmpl-9x123","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"!"},"finish_reason":"stop"}]}',
      '',
      'data: [DONE]',
    ].join('\n'),
  },
  {
    id: 'openai-models',
    group: 'ai',
    method: 'GET',
    path: '/oci-start/open-api/v1/models',
    summary: { zh: '获取可用模型列表', en: 'List available models' },
    description: {
      zh: '返回符合 OpenAI 标准的已启用模型清单，可直接对接 new-api 等第三方客户端。',
      en: 'Returns enabled models in OpenAI `/v1/models` format for new-api and compatible clients.',
    },
    auditTitle: '获取模型列表',
    parameters: [],
    bodyFields: [],
    responseExample: JSON.stringify({
      object: 'list',
      data: [
        { id: 'gpt-4o-mini', object: 'model', owned_by: 'oci-start' },
      ],
    }, null, 2),
  },
  {
    id: 'storage-buckets',
    group: 'storage',
    method: 'GET',
    path: '/oci-start/open-api/v1/storage/buckets',
    summary: { zh: '获取存储桶列表', en: 'List OCI buckets' },
    description: {
      zh: '查询指定 OCI 租户默认区域下的所有对象存储桶名称、命名空间与公开访问权限。',
      en: 'List OCI Object Storage buckets, namespaces, and access levels for a tenant.',
    },
    auditTitle: '获取存储桶列表',
    parameters: [
      {
        name: 'tenantId',
        in: 'query',
        type: 'integer',
        required: true,
        defaultValue: '1',
        description: { zh: 'OCI 租户主键 ID', en: 'OCI tenant numeric ID' },
      },
    ],
    bodyFields: [],
    responseExample: JSON.stringify({
      success: true,
      code: 200,
      message: 'success',
      data: [
        {
          name: 'backup-bucket',
          namespace: 'axxxxxxxxxxx',
          timeCreated: '2026-01-15T08:00:00Z',
          publicAccess: 'NoPublicAccess',
        },
      ],
    }, null, 2),
  },
  {
    id: 'storage-objects',
    group: 'storage',
    method: 'GET',
    path: '/oci-start/open-api/v1/storage/objects',
    summary: { zh: '获取存储桶对象列表', en: 'List bucket objects' },
    description: {
      zh: '列出指定存储桶中的文件对象清单，支持按路径前缀 `prefix` 过滤。',
      en: 'List objects inside a specific OCI bucket with optional `prefix` filtering.',
    },
    auditTitle: '获取对象列表',
    parameters: [
      {
        name: 'tenantId',
        in: 'query',
        type: 'integer',
        required: true,
        defaultValue: '1',
        description: { zh: 'OCI 租户主键 ID', en: 'OCI tenant numeric ID' },
      },
      {
        name: 'namespace',
        in: 'query',
        type: 'string',
        required: true,
        defaultValue: 'axxxxxxxxxxx',
        description: { zh: '对象存储命名空间', en: 'Object Storage namespace' },
      },
      {
        name: 'bucketName',
        in: 'query',
        type: 'string',
        required: true,
        defaultValue: 'backup-bucket',
        description: { zh: '存储桶名称', en: 'Bucket name' },
      },
      {
        name: 'prefix',
        in: 'query',
        type: 'string',
        required: false,
        defaultValue: '',
        description: { zh: '对象名称前缀筛选（选填）', en: 'Optional object key prefix filter' },
      },
    ],
    bodyFields: [],
    responseExample: JSON.stringify({
      success: true,
      code: 200,
      message: 'success',
      data: [
        {
          name: 'archives/db-2026-11-15.tar.gz',
          size: 1048576,
          timeModified: '2026-11-15T00:00:00Z',
        },
      ],
    }, null, 2),
  },
  {
    id: 'storage-presigned',
    group: 'storage',
    method: 'POST',
    path: '/oci-start/open-api/v1/storage/object/presigned',
    summary: { zh: '生成对象预签名 URL', en: 'Generate presigned URL' },
    description: {
      zh: '为指定存储桶内的私有对象生成带时效的临时预签名访问链接（PAR）。',
      en: 'Create a temporary Pre-Authenticated Request URL for a private OCI object.',
    },
    auditTitle: '生成预签名URL',
    parameters: [],
    bodyFields: [
      { name: 'tenantId', type: 'integer', required: true, description: { zh: 'OCI 租户主键 ID', en: 'OCI tenant numeric ID' } },
      { name: 'namespace', type: 'string', required: true, description: { zh: '对象存储命名空间', en: 'Object Storage namespace' } },
      { name: 'bucketName', type: 'string', required: true, description: { zh: '存储桶名称', en: 'Bucket name' } },
      { name: 'objectName', type: 'string', required: true, description: { zh: '目标对象名称 / 路径', en: 'Target object key / path' } },
      { name: 'validitySeconds', type: 'integer', required: false, description: { zh: '有效时长（秒），默认 3600', en: 'Validity in seconds (default 3600)' } },
    ],
    defaultBody: {
      tenantId: 1,
      namespace: 'axxxxxxxxxxx',
      bucketName: 'backup-bucket',
      objectName: 'archives/db-2026-11-15.tar.gz',
      validitySeconds: 3600,
    },
    responseExample: JSON.stringify({
      success: true,
      code: 200,
      message: 'success',
      data: {
        url: 'https://objectstorage.us-phoenix-1.oraclecloud.com/p/.../o/archives/db-2026-11-15.tar.gz',
      },
    }, null, 2),
  },
]

export function resolveRequestUrl(
  origin: string,
  endpoint: OpenApiEndpoint,
  queryValues: Record<string, string>,
): string {
  const cleanOrigin = origin.replace(/\/+$/, '')
  const queryParams = new URLSearchParams()
  for (const param of endpoint.parameters) {
    if (param.in !== 'query') continue
    const val = (queryValues[param.name] ?? '').trim()
    if (val) queryParams.set(param.name, val)
  }
  const qs = queryParams.toString()
  return `${cleanOrigin}${endpoint.path}${qs ? `?${qs}` : ''}`
}

function shellQuote(value: string): string {
  return `'${value.replace(/'/g, "'\"'\"'")}'`
}

export function buildCurlCommand(options: {
  origin: string
  endpoint: OpenApiEndpoint
  token: string
  queryValues: Record<string, string>
  headerValues: Record<string, string>
  bodyText: string
}): string {
  const url = resolveRequestUrl(options.origin || 'http://localhost:9856', options.endpoint, options.queryValues)
  const tokenValue = options.token.trim() || '<YOUR_API_TOKEN>'
  const parts = [
    `curl --request ${options.endpoint.method} ${shellQuote(url)}`,
    `  --header ${shellQuote(`Authorization: Bearer ${tokenValue}`)}`,
  ]
  for (const param of options.endpoint.parameters) {
    if (param.in !== 'header') continue
    const value = (options.headerValues[param.name] ?? '').trim()
    if (value) parts.push(`  --header ${shellQuote(`${param.name}: ${value}`)}`)
  }
  if (options.endpoint.method === 'POST') {
    parts.push(`  --header 'Content-Type: application/json'`)
    const payload = options.bodyText.trim() || '{}'
    parts.push(`  --data-raw ${shellQuote(payload)}`)
  }
  return parts.join(' \\\n')
}

export function buildOpenApiDocument(serverUrl = '') {
  const paths: Record<string, Record<string, unknown>> = {}

  for (const ep of OPEN_API_ENDPOINTS) {
    const methodKey = ep.method.toLowerCase()
    const parameters = ep.parameters.map(param => ({
      name: param.name,
      in: param.in,
      required: param.required,
      description: `${param.description.zh} / ${param.description.en}`,
      schema: {
        type: param.type,
        ...(param.defaultValue ? { example: param.type === 'integer' ? Number(param.defaultValue) || 1 : param.defaultValue } : {}),
      },
    }))

    const properties: Record<string, unknown> = {}
    const requiredFields: string[] = []
    for (const field of ep.bodyFields) {
      if (field.required) requiredFields.push(field.name)
      properties[field.name] = {
        type: field.type.startsWith('array') ? 'array' : field.type.includes('object') ? 'object' : field.type,
        description: `${field.description.zh} / ${field.description.en}`,
      }
    }

    const operation: Record<string, unknown> = {
      tags: [OPEN_API_GROUPS[ep.group].zh],
      summary: ep.summary.zh,
      description: ep.description.zh,
      operationId: ep.id,
      security: [{ bearerAuth: [] }],
      ...(parameters.length ? { parameters } : {}),
      ...(ep.method === 'POST' ? {
        requestBody: {
          required: true,
          content: {
            'application/json': {
              schema: {
                type: 'object',
                ...(requiredFields.length ? { required: requiredFields } : {}),
                properties,
              },
              ...(ep.defaultBody ? { example: ep.defaultBody } : {}),
            },
          },
        },
      } : {}),
      responses: {
        '200': {
          description: 'OK',
          content: {
            'application/json': {
              example: JSON.parse(ep.responseExample),
            },
          },
        },
        '401': {
          description: 'Missing or invalid API Token',
        },
      },
    }

    paths[ep.path] = {
      ...(paths[ep.path] || {}),
      [methodKey]: operation,
    }
  }

  return {
    openapi: '3.0.3',
    info: {
      title: 'OCI-START Open API',
      version: '1.0.0',
      description: 'OCI-START 开放平台接口规范（由登录态后台安全导出）',
    },
    ...(serverUrl ? { servers: [{ url: serverUrl }] } : {}),
    components: {
      securitySchemes: {
        bearerAuth: {
          type: 'http',
          scheme: 'bearer',
          bearerFormat: 'OCI-START API Token',
        },
      },
    },
    paths,
  }
}

export function downloadOpenApiJson(serverUrl = '') {
  const doc = buildOpenApiDocument(serverUrl)
  const blob = new Blob([JSON.stringify(doc, null, 2)], { type: 'application/json;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = 'oci-start-openapi.json'
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}

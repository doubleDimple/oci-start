import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import ts from 'typescript'

const specSource = await readFile(new URL('../src/views/settings/api-tokens/openApiSpec.ts', import.meta.url), 'utf8')
const specJs = ts.transpileModule(specSource, {
  compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
}).outputText
const {
  OPEN_API_ENDPOINTS,
  buildOpenApiDocument,
  buildCurlCommand,
  resolveRequestUrl,
} = await import(`data:text/javascript;base64,${Buffer.from(specJs).toString('base64')}`)

test('custom OpenAPI catalog covers all 6 OpenApiController endpoints and builds valid OpenAPI 3.0.3 JSON', async () => {
  assert.equal(OPEN_API_ENDPOINTS.length, 6)
  const doc = buildOpenApiDocument('https://ops.example.com')
  assert.equal(doc.openapi, '3.0.3')
  assert.deepEqual(doc.servers, [{ url: 'https://ops.example.com' }])
  assert.ok(doc.components.securitySchemes.bearerAuth)
  assert.deepEqual(Object.keys(doc.paths), [
    '/oci-start/open-api/v1/chat',
    '/oci-start/open-api/v1/chat/completions',
    '/oci-start/open-api/v1/models',
    '/oci-start/open-api/v1/storage/buckets',
    '/oci-start/open-api/v1/storage/objects',
    '/oci-start/open-api/v1/storage/object/presigned',
  ])

  const buckets = OPEN_API_ENDPOINTS.find(ep => ep.id === 'storage-buckets')
  assert.equal(
    resolveRequestUrl('https://ops.example.com', buckets, { tenantId: '42' }),
    'https://ops.example.com/oci-start/open-api/v1/storage/buckets?tenantId=42',
  )

  const chat = OPEN_API_ENDPOINTS.find(ep => ep.id === 'ai-chat')
  const curl = buildCurlCommand({
    origin: 'https://ops.example.com',
    endpoint: chat,
    token: 'oci-start_api_demo',
    queryValues: {},
    headerValues: {},
    bodyText: '{"userId":"u1","message":"hi"}',
  })
  assert.match(curl, /Authorization: Bearer oci-start_api_demo/)
  assert.match(curl, /\/oci-start\/open-api\/v1\/chat/)
})

test('Swagger and springdoc anonymous endpoints are completely removed from backend and router protects /system/apiDocs', async () => {
  const saToken = await readFile(new URL('../../oci-server/src/main/java/com/doubledimple/ociserver/config/SaTokenConfig.java', import.meta.url), 'utf8')
  const appYml = await readFile(new URL('../../oci-server/src/main/resources/application.yml', import.meta.url), 'utf8')
  const router = await readFile(new URL('../src/router/index.ts', import.meta.url), 'utf8')

  assert.doesNotMatch(saToken, /swagger|v3\/api-docs|webjars/)
  assert.doesNotMatch(appYml, /springdoc|swagger-ui/)
  assert.match(router, /path:\s*'system\/apiDocs'[\s\S]*ApiDocsView\.vue/)
})

package com.doubledimple.ociserver.utils.google;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;
import reactor.core.publisher.Flux;

import javax.annotation.Resource;
import java.io.FileInputStream;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Google Gemini API工具类，提供AI对话和内容生成功能
 *
 * @version 1.0.0
 * @author doubleDimple
 * @date 2025-01-15
 */
@Component
@Slf4j
public class GeminiApiUtil {

    @Resource
    GcpApiUtil gcpApiUtil;

    // Gemini API 相关常量
    private static final String VERTEX_AI_ENDPOINT = "https://{location}-aiplatform.googleapis.com/v1/projects/{projectId}/locations/{location}/publishers/google/models/{modelId}:generateContent";
    private static final String VERTEX_AI_STREAM_ENDPOINT = "https://{location}-aiplatform.googleapis.com/v1/projects/{projectId}/locations/{location}/publishers/google/models/{modelId}:streamGenerateContent";
    private static final String OAUTH_TOKEN_URL = "https://oauth2.googleapis.com/token";
    private static final String SCOPE = "https://www.googleapis.com/auth/cloud-platform";

    // 支持的模型列表
    private static final List<String> SUPPORTED_MODELS = Arrays.asList(
            "gemini-1.5-pro", "gemini-1.5-flash", "gemini-1.0-pro", "gemini-1.0-pro-vision"
    );

    // 默认参数配置
    private static final double DEFAULT_TEMPERATURE = 0.7;
    private static final int DEFAULT_MAX_TOKENS = 8192;
    private static final double DEFAULT_TOP_P = 0.95;
    private static final int DEFAULT_TOP_K = 40;

    private final RestTemplate restTemplate;
    private final ObjectMapper objectMapper;

    // 缓存访问令牌，避免频繁获取
    private final Map<String, TokenInfo> tokenCache = new ConcurrentHashMap<>();

    public GeminiApiUtil() {
        this.restTemplate = new RestTemplate();
        this.objectMapper = new ObjectMapper();
    }

    /**
     * 令牌信息缓存类
     */
    private static class TokenInfo {
        private final String token;
        private final long expiryTime;

        public TokenInfo(String token, long expiryTime) {
            this.token = token;
            this.expiryTime = expiryTime;
        }

        public boolean isExpired() {
            return System.currentTimeMillis() >= expiryTime;
        }

        public String getToken() {
            return token;
        }
    }

    /**
     * 简单对话接口 - 单轮对话
     *
     * @param projectId GCP项目ID
     * @param location 区域位置（如：us-central1）
     * @param message 用户消息
     * @param modelId 模型ID（如：gemini-1.5-pro）
     * @param credentialsPath 服务账号密钥文件路径
     * @return AI回复
     */
    public String chat(String projectId, String location, String message, String modelId, String credentialsPath) {
        try {
            // 验证模型支持
            validateModel(modelId);

            // 构建请求内容
            Map<String, Object> request = buildSimpleChatRequest(message);

            // 发送请求并获取响应
            String response = sendGenerateContentRequest(projectId, location, modelId, request, credentialsPath);

            // 解析响应内容
            return extractTextFromResponse(response);

        } catch (Exception e) {
            log.error("Gemini对话失败: {}", e.getMessage(), e);
            return "抱歉，AI服务暂时不可用：" + e.getMessage();
        }
    }

    /**
     * 多轮对话接口 - 支持对话历史
     *
     * @param projectId GCP项目ID
     * @param location 区域位置
     * @param messages 对话历史消息列表
     * @param modelId 模型ID
     * @param credentialsPath 服务账号密钥文件路径
     * @return AI回复
     */
    public String chatWithHistory(String projectId, String location, List<Map<String, String>> messages,
                                  String modelId, String credentialsPath) {
        try {
            validateModel(modelId);

            // 构建带历史的请求内容
            Map<String, Object> request = buildChatWithHistoryRequest(messages);

            // 发送请求并获取响应
            String response = sendGenerateContentRequest(projectId, location, modelId, request, credentialsPath);

            return extractTextFromResponse(response);

        } catch (Exception e) {
            log.error("Gemini多轮对话失败: {}", e.getMessage(), e);
            return "抱歉，多轮对话服务暂时不可用：" + e.getMessage();
        }
    }

    /**
     * 流式对话接口 - 实时返回生成内容
     *
     * @param projectId GCP项目ID
     * @param location 区域位置
     * @param message 用户消息
     * @param modelId 模型ID
     * @param credentialsPath 服务账号密钥文件路径
     * @return 流式响应
     */
    public Flux<String> chatStream(String projectId, String location, String message,
                                   String modelId, String credentialsPath) {
        return Flux.create(sink -> {
            try {
                validateModel(modelId);

                Map<String, Object> request = buildSimpleChatRequest(message);
                String response = sendStreamGenerateContentRequest(projectId, location, modelId, request, credentialsPath);

                // 解析流式响应
                parseStreamResponse(response, sink);

            } catch (Exception e) {
                log.error("Gemini流式对话失败: {}", e.getMessage(), e);
                sink.error(e);
            }
        });
    }

    /**
     * 多模态对话接口 - 支持图片+文本
     *
     * @param projectId GCP项目ID
     * @param location 区域位置
     * @param textMessage 文本消息
     * @param imageData 图片数据（Base64编码）
     * @param mimeType 图片MIME类型（如：image/jpeg）
     * @param modelId 模型ID（建议使用gemini-1.5-pro）
     * @param credentialsPath 服务账号密钥文件路径
     * @return AI回复
     */
    public String chatWithImage(String projectId, String location, String textMessage,
                                String imageData, String mimeType, String modelId, String credentialsPath) {
        try {
            validateModel(modelId);

            // 构建多模态请求内容
            Map<String, Object> request = buildMultiModalRequest(textMessage, imageData, mimeType);

            String response = sendGenerateContentRequest(projectId, location, modelId, request, credentialsPath);

            return extractTextFromResponse(response);

        } catch (Exception e) {
            log.error("Gemini多模态对话失败: {}", e.getMessage(), e);
            return "抱歉，图像分析服务暂时不可用：" + e.getMessage();
        }
    }

    /**
     * 高级对话接口 - 支持自定义参数
     *
     * @param projectId GCP项目ID
     * @param location 区域位置
     * @param message 用户消息
     * @param modelId 模型ID
     * @param temperature 温度参数（0.0-1.0）
     * @param maxTokens 最大令牌数
     * @param topP Top-p参数
     * @param topK Top-k参数
     * @param credentialsPath 服务账号密钥文件路径
     * @return AI回复
     */
    public String chatWithParams(String projectId, String location, String message, String modelId,
                                 Double temperature, Integer maxTokens, Double topP, Integer topK,
                                 String credentialsPath) {
        try {
            validateModel(modelId);

            Map<String, Object> request = buildAdvancedChatRequest(message, temperature, maxTokens, topP, topK);

            String response = sendGenerateContentRequest(projectId, location, modelId, request, credentialsPath);

            return extractTextFromResponse(response);

        } catch (Exception e) {
            log.error("Gemini高级对话失败: {}", e.getMessage(), e);
            return "抱歉，AI服务暂时不可用：" + e.getMessage();
        }
    }

    /**
     * 构建简单对话请求
     */
    private Map<String, Object> buildSimpleChatRequest(String message) {
        Map<String, Object> request = new HashMap<>();

        // 构建内容部分
        List<Map<String, Object>> contents = new ArrayList<>();
        Map<String, Object> content = new HashMap<>();

        List<Map<String, Object>> parts = new ArrayList<>();
        Map<String, Object> part = new HashMap<>();
        part.put("text", message);
        parts.add(part);

        content.put("parts", parts);
        contents.add(content);

        request.put("contents", contents);

        // 添加生成配置
        Map<String, Object> generationConfig = new HashMap<>();
        generationConfig.put("temperature", DEFAULT_TEMPERATURE);
        generationConfig.put("maxOutputTokens", DEFAULT_MAX_TOKENS);
        generationConfig.put("topP", DEFAULT_TOP_P);
        generationConfig.put("topK", DEFAULT_TOP_K);

        request.put("generationConfig", generationConfig);

        return request;
    }

    /**
     * 构建带历史的对话请求
     */
    private Map<String, Object> buildChatWithHistoryRequest(List<Map<String, String>> messages) {
        Map<String, Object> request = new HashMap<>();

        List<Map<String, Object>> contents = new ArrayList<>();

        // 限制历史消息数量，避免超过token限制
        int maxHistorySize = 10;
        int startIndex = Math.max(0, messages.size() - maxHistorySize);

        for (int i = startIndex; i < messages.size(); i++) {
            Map<String, String> msg = messages.get(i);
            String role = msg.get("role");
            String content = msg.get("content");

            Map<String, Object> geminiContent = new HashMap<>();

            // 转换角色格式
            if ("user".equals(role)) {
                geminiContent.put("role", "user");
            } else if ("assistant".equals(role)) {
                geminiContent.put("role", "model");
            } else {
                continue; // 跳过不支持的角色
            }

            List<Map<String, Object>> parts = new ArrayList<>();
            Map<String, Object> part = new HashMap<>();
            part.put("text", content);
            parts.add(part);

            geminiContent.put("parts", parts);
            contents.add(geminiContent);
        }

        request.put("contents", contents);

        // 添加生成配置
        Map<String, Object> generationConfig = new HashMap<>();
        generationConfig.put("temperature", DEFAULT_TEMPERATURE);
        generationConfig.put("maxOutputTokens", DEFAULT_MAX_TOKENS);
        generationConfig.put("topP", DEFAULT_TOP_P);
        generationConfig.put("topK", DEFAULT_TOP_K);

        request.put("generationConfig", generationConfig);

        return request;
    }

    /**
     * 构建多模态请求
     */
    private Map<String, Object> buildMultiModalRequest(String textMessage, String imageData, String mimeType) {
        Map<String, Object> request = new HashMap<>();

        List<Map<String, Object>> contents = new ArrayList<>();
        Map<String, Object> content = new HashMap<>();

        List<Map<String, Object>> parts = new ArrayList<>();

        // 添加文本部分
        if (textMessage != null && !textMessage.trim().isEmpty()) {
            Map<String, Object> textPart = new HashMap<>();
            textPart.put("text", textMessage);
            parts.add(textPart);
        }

        // 添加图像部分
        Map<String, Object> imagePart = new HashMap<>();
        Map<String, Object> inlineData = new HashMap<>();
        inlineData.put("mimeType", mimeType);
        inlineData.put("data", imageData);
        imagePart.put("inlineData", inlineData);
        parts.add(imagePart);

        content.put("parts", parts);
        contents.add(content);

        request.put("contents", contents);

        // 多模态请求的生成配置
        Map<String, Object> generationConfig = new HashMap<>();
        generationConfig.put("temperature", DEFAULT_TEMPERATURE);
        generationConfig.put("maxOutputTokens", DEFAULT_MAX_TOKENS);
        generationConfig.put("topP", DEFAULT_TOP_P);
        generationConfig.put("topK", DEFAULT_TOP_K);

        request.put("generationConfig", generationConfig);

        return request;
    }

    /**
     * 构建高级对话请求
     */
    private Map<String, Object> buildAdvancedChatRequest(String message, Double temperature,
                                                         Integer maxTokens, Double topP, Integer topK) {
        Map<String, Object> request = buildSimpleChatRequest(message);

        // 自定义生成配置
        Map<String, Object> generationConfig = new HashMap<>();
        generationConfig.put("temperature", temperature != null ? temperature : DEFAULT_TEMPERATURE);
        generationConfig.put("maxOutputTokens", maxTokens != null ? maxTokens : DEFAULT_MAX_TOKENS);
        generationConfig.put("topP", topP != null ? topP : DEFAULT_TOP_P);
        generationConfig.put("topK", topK != null ? topK : DEFAULT_TOP_K);

        request.put("generationConfig", generationConfig);

        return request;
    }

    /**
     * 发送生成内容请求
     */
    private String sendGenerateContentRequest(String projectId, String location, String modelId,
                                              Map<String, Object> request, String credentialsPath) throws IOException {
        String accessToken = getAccessToken(credentialsPath);

        HttpHeaders headers = new HttpHeaders();
        headers.set("Authorization", "Bearer " + accessToken);
        headers.setContentType(MediaType.APPLICATION_JSON);

        String requestBody = objectMapper.writeValueAsString(request);
        HttpEntity<String> entity = new HttpEntity<>(requestBody, headers);

        String url = VERTEX_AI_ENDPOINT
                .replace("{location}", location)
                .replace("{projectId}", projectId)
                .replace("{modelId}", modelId);

        ResponseEntity<String> response = restTemplate.exchange(
                url, HttpMethod.POST, entity, String.class);

        return response.getBody();
    }

    /**
     * 发送流式生成内容请求
     */
    private String sendStreamGenerateContentRequest(String projectId, String location, String modelId,
                                                    Map<String, Object> request, String credentialsPath) throws IOException {
        String accessToken = getAccessToken(credentialsPath);

        HttpHeaders headers = new HttpHeaders();
        headers.set("Authorization", "Bearer " + accessToken);
        headers.setContentType(MediaType.APPLICATION_JSON);

        String requestBody = objectMapper.writeValueAsString(request);
        HttpEntity<String> entity = new HttpEntity<>(requestBody, headers);

        String url = VERTEX_AI_STREAM_ENDPOINT
                .replace("{location}", location)
                .replace("{projectId}", projectId)
                .replace("{modelId}", modelId);

        ResponseEntity<String> response = restTemplate.exchange(
                url, HttpMethod.POST, entity, String.class);

        return response.getBody();
    }

    /**
     * 从响应中提取文本内容
     */
    private String extractTextFromResponse(String response) {
        try {
            JSONObject jsonResponse = JSON.parseObject(response);
            JSONArray candidates = jsonResponse.getJSONArray("candidates");

            if (candidates != null && !candidates.isEmpty()) {
                JSONObject candidate = candidates.getJSONObject(0);
                JSONObject content = candidate.getJSONObject("content");
                JSONArray parts = content.getJSONArray("parts");

                if (parts != null && !parts.isEmpty()) {
                    JSONObject part = parts.getJSONObject(0);
                    return part.getString("text");
                }
            }

            log.warn("无法从Gemini响应中提取文本内容: {}", response);
            return "收到了回复，但无法解析文本内容。";

        } catch (Exception e) {
            log.error("解析Gemini响应失败: {}", e.getMessage(), e);
            return "解析AI回复时出现错误。";
        }
    }

    /**
     * 解析流式响应
     */
    private void parseStreamResponse(String response, reactor.core.publisher.FluxSink<String> sink) {
        try {
            // 流式响应通常是换行分隔的JSON
            String[] lines = response.split("\n");

            for (String line : lines) {
                line = line.trim();
                if (line.isEmpty() || line.startsWith("data: ")) {
                    if (line.startsWith("data: ")) {
                        line = line.substring(6);
                    }

                    if (!line.isEmpty() && !line.equals("[DONE]")) {
                        try {
                            String text = extractTextFromResponse(line);
                            if (text != null && !text.isEmpty()) {
                                sink.next(text);
                            }
                        } catch (Exception e) {
                            log.debug("跳过无法解析的流式响应行: {}", line);
                        }
                    }
                }
            }

            sink.complete();

        } catch (Exception e) {
            log.error("解析流式响应失败: {}", e.getMessage(), e);
            sink.error(e);
        }
    }

    /**
     * 获取访问令牌（带缓存）
     */
    private String getAccessToken(String credentialsPath) throws IOException {
        // 检查缓存
        TokenInfo tokenInfo = tokenCache.get(credentialsPath);
        if (tokenInfo != null && !tokenInfo.isExpired()) {
            return tokenInfo.getToken();
        }

        // 从服务账号密钥文件获取访问令牌
        Map<String, Object> credentialsJson;
        try (FileInputStream fileInputStream = new FileInputStream(credentialsPath)) {
            credentialsJson = objectMapper.readValue(fileInputStream, new TypeReference<Map<String, Object>>() {});
        }

        String clientEmail = (String) credentialsJson.get("client_email");
        String privateKeyPem = (String) credentialsJson.get("private_key");

        // 创建JWT令牌
        String jwt = gcpApiUtil.createJwtToken(clientEmail, privateKeyPem);

        // 获取访问令牌
        HttpHeaders headers = new HttpHeaders();
        headers.set("Content-Type", "application/x-www-form-urlencoded");

        String requestBody = "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=" + jwt;
        HttpEntity<String> request = new HttpEntity<>(requestBody, headers);

        ResponseEntity<String> response = restTemplate.postForEntity(OAUTH_TOKEN_URL, request, String.class);
        Map<String, Object> tokenResponse = objectMapper.readValue(response.getBody(), new TypeReference<Map<String, Object>>() {});

        String accessToken = (String) tokenResponse.get("access_token");
        Integer expiresIn = (Integer) tokenResponse.get("expires_in");

        // 缓存令牌（提前5分钟过期）
        long expiryTime = System.currentTimeMillis() + (expiresIn - 300) * 1000L;
        tokenCache.put(credentialsPath, new TokenInfo(accessToken, expiryTime));

        return accessToken;
    }


    /**
     * 验证模型是否支持
     */
    private void validateModel(String modelId) {
        if (!SUPPORTED_MODELS.contains(modelId)) {
            log.warn("使用了未在支持列表中的模型: {}，支持的模型: {}", modelId, SUPPORTED_MODELS);
        }
    }

    /**
     * 检查Gemini服务是否可用
     */
    public boolean isGeminiServiceAvailable(String projectId, String location, String modelId, String credentialsPath) {
        try {
            String testMessage = "Hello";
            String response = chat(projectId, location, testMessage, modelId, credentialsPath);
            return response != null && !response.contains("暂时不可用");
        } catch (Exception e) {
            log.error("检查Gemini服务可用性失败: {}", e.getMessage());
            return false;
        }
    }

    /**
     * 预热客户端连接
     */
    public void warmupClient(String projectId, String location, String credentialsPath) {
        try {
            getAccessToken(credentialsPath);
            log.info("预热Gemini客户端成功 - 项目: {}, 区域: {}", projectId, location);
        } catch (Exception e) {
            log.error("预热Gemini客户端失败 - 项目: {}, 区域: {}", projectId, location, e);
        }
    }

    /**
     * 清理令牌缓存
     */
    public void clearTokenCache() {
        tokenCache.clear();
        log.info("Gemini令牌缓存已清理");
    }

    /**
     * 获取支持的模型列表
     */
    public List<String> getSupportedModels() {
        return new ArrayList<>(SUPPORTED_MODELS);
    }
}

package com.doubledimple.ociserver.utils;

import com.doubledimple.ociserver.pojo.request.EdgeOneConfigRequest;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.tencentcloudapi.teo.v20220901.TeoClient;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.web.client.RestTemplate;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.HashMap;
import java.util.Map;
import java.util.TimeZone;

import static com.doubledimple.ocicommon.utils.AesUtils.bytesToHex;
import static com.doubledimple.ocicommon.utils.AesUtils.hmacSha256;
import static com.doubledimple.ocicommon.utils.AesUtils.sha256Hex;

/**
 * @version 1.0.0
 * @ClassName EdgeUtils
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-07-27 11:16
 */
@Slf4j
public class EdgeUtils {

    public static Map<String, Object> testEdgeOneConnection(EdgeOneConfigRequest request) {
        Map<String, Object> result = new HashMap<>();

        try {
            // 验证必填参数
            if (StringUtils.isEmpty(request.getSecretId())) {
                throw new IllegalArgumentException("SecretId不能为空");
            }
            if (StringUtils.isEmpty(request.getSecretKey())) {
                throw new IllegalArgumentException("SecretKey不能为空");
            }

            String secretId = request.getSecretId().trim();
            String secretKey = request.getSecretKey().trim();

            log.info("开始测试腾讯云EdgeOne连接，SecretId: {}", secretId.substring(0, 8) + "***");

            // 调用腾讯云API验证连接
            boolean isValid = validateTencentCloudCredentials(secretId, secretKey);

            if (isValid) {
                result.put("success", true);
                result.put("message", "腾讯云EdgeOne API连接成功");
                log.info("腾讯云EdgeOne连接测试成功");
            } else {
                result.put("success", false);
                result.put("message", "SecretId或SecretKey验证失败，请检查是否正确");
                log.warn("腾讯云EdgeOne API验证失败");
            }

        } catch (IllegalArgumentException e) {
            result.put("success", false);
            result.put("message", e.getMessage());
            log.warn("腾讯云EdgeOne连接测试参数错误: {}", e.getMessage());
        } catch (Exception e) {
            log.error("测试腾讯云EdgeOne连接失败: {}", e.getMessage(), e);
            result.put("success", false);
            result.put("message", "连接失败: " + e.getMessage());
        }

        return result;
    }

    public static boolean validateTencentCloudCredentials(String secretId, String secretKey) {
        try {
            // 腾讯云API调用参数
            String service = "teo"; // EdgeOne服务
            String version = "2022-09-01";
            String action = "DescribeZones";
            String region = ""; // EdgeOne是全球服务，不需要指定region
            String host = "teo.tencentcloudapi.com";

            // 构建请求
            String url = "https://" + host;
            String httpMethod = "POST";
            String canonicalUri = "/";
            String canonicalQueryString = "";

            // 请求体
            String payload = "{}";

            // 当前时间戳
            long timestamp = System.currentTimeMillis() / 1000;

            // 日期格式
            SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd");
            sdf.setTimeZone(TimeZone.getTimeZone("UTC"));
            String date = sdf.format(new Date(timestamp * 1000));

            // 构建签名
            String algorithm = "TC3-HMAC-SHA256";
            String credentialScope = date + "/" + service + "/tc3_request";

            // 构建规范请求
            String hashedPayload = sha256Hex(payload);
            String canonicalHeaders = "content-type:application/json; charset=utf-8\n" +
                    "host:" + host + "\n" +
                    "x-tc-action:" + action.toLowerCase() + "\n" +
                    "x-tc-timestamp:" + timestamp + "\n" +
                    "x-tc-version:" + version + "\n";
            String signedHeaders = "content-type;host;x-tc-action;x-tc-timestamp;x-tc-version";

            String canonicalRequest = httpMethod + "\n" +
                    canonicalUri + "\n" +
                    canonicalQueryString + "\n" +
                    canonicalHeaders + "\n" +
                    signedHeaders + "\n" +
                    hashedPayload;

            // 构建待签名字符串
            String hashedCanonicalRequest = sha256Hex(canonicalRequest);
            String stringToSign = algorithm + "\n" +
                    timestamp + "\n" +
                    credentialScope + "\n" +
                    hashedCanonicalRequest;

            // 计算签名
            byte[] secretDate = hmacSha256(("TC3" + secretKey).getBytes(), date);
            byte[] secretService = hmacSha256(secretDate, service);
            byte[] secretSigning = hmacSha256(secretService, "tc3_request");
            String signature = bytesToHex(hmacSha256(secretSigning, stringToSign));

            // 构建Authorization
            String authorization = algorithm + " " +
                    "Credential=" + secretId + "/" + credentialScope + ", " +
                    "SignedHeaders=" + signedHeaders + ", " +
                    "Signature=" + signature;

            // 创建请求头
            HttpHeaders headers = new HttpHeaders();
            headers.set("Authorization", authorization);
            headers.set("Content-Type", "application/json; charset=utf-8");
            headers.set("Host", host);
            headers.set("X-TC-Action", action);
            headers.set("X-TC-Timestamp", String.valueOf(timestamp));
            headers.set("X-TC-Version", version);
            if (!region.isEmpty()) {
                headers.set("X-TC-Region", region);
            }

            HttpEntity<String> entity = new HttpEntity<>(payload, headers);

            RestTemplate restTemplate = new RestTemplate();

            try {
                ResponseEntity<String> response = restTemplate.exchange(url, HttpMethod.POST, entity, String.class);

                log.info("腾讯云EdgeOne API响应状态: {}", response.getStatusCode());
                log.debug("腾讯云EdgeOne API响应体: {}", response.getBody());

                // 解析响应
                ObjectMapper mapper = new ObjectMapper();
                JsonNode jsonNode = mapper.readTree(response.getBody());

                // 检查是否有错误
                JsonNode error = jsonNode.get("Response").get("Error");
                if (error != null) {
                    String errorCode = error.get("Code").asText();
                    String errorMessage = error.get("Message").asText();
                    log.error("腾讯云EdgeOne API错误: Code={}, Message={}", errorCode, errorMessage);
                    return false;
                }

                // 检查是否有正常的响应数据
                JsonNode responseNode = jsonNode.get("Response");
                if (responseNode != null && responseNode.get("RequestId") != null) {
                    log.info("腾讯云EdgeOne API验证成功");
                    return true;
                }

                return false;

            } catch (org.springframework.web.client.HttpClientErrorException e) {
                log.error("腾讯云EdgeOne API请求失败 - 状态码: {}, 响应: {}", e.getStatusCode(), e.getResponseBodyAsString());
                return false;
            }

        } catch (Exception e) {
            log.error("验证腾讯云EdgeOne凭证失败: {}", e.getMessage(), e);
            return false;
        }
    }
}

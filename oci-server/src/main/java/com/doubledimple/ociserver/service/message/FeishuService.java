package com.doubledimple.ociserver.service.message;

import com.doubledimple.dao.repository.SystemConfigRepository;
import com.doubledimple.ociserver.pojo.domain.dto.OracleInstanceDetail;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import javax.annotation.Resource;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.util.Base64;
import java.util.HashMap;
import java.util.Map;

import static com.doubledimple.ocicommon.template.MessageTemplate.MESSAGE_LOGIN_TEMPLATE;

/**
 * @version 1.0.0
 * @ClassName FeishuService
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-08-31 08:27
 */
@Service
@Slf4j
public class FeishuService implements MessageService{

    @Resource
    SystemConfigRepository systemConfigRepository;

    private final RestTemplate restTemplate = new RestTemplate();
    private final ObjectMapper objectMapper = new ObjectMapper();

    @Override
    public void sendMessage(OracleInstanceDetail instanceData) {
        log.info("推送飞书消息开始.....");
    }

    @Override
    public void sendMessageTemplate(String message) {
        sendFeishuMessage(message);
    }

    @Override
    public void sendMessageTemplateText(String message) {

    }

    @Override
    public void sendMessageTemplateText(String message, Boolean consoleFlag) {

    }

    @Override
    public void sendMessageTemplateTest(String message) {
        sendFeishuMessage(message);
    }

    @Override
    public MessageEnum getMessageType() {
        return MessageEnum.FEISHU;
    }

    @Override
    public void sendErrorMessage(String s) {
        sendFeishuMessage(s);
    }

    @Override
    public void sendMyChannel(String message) {
        log.info("..........");
    }

    @Override
    public void sendVerificationCodeMessage(String userName, String verificationCode) {
        sendFeishuMessage(String.format(MESSAGE_LOGIN_TEMPLATE,userName,verificationCode));
    }

    private void sendFeishuMessage( String message){
        // 获取配置
        try {
            String webhook = systemConfigRepository.findByKey("feishu.webhook")
                    .map(config -> config.getValue()).orElse("");
            String secret = systemConfigRepository.findByKey("feishu.secret")
                    .map(config -> config.getValue()).orElse("");
            boolean enabled = systemConfigRepository.findByKey("feishu.enabled")
                    .map(config -> config.isEnabled()).orElse(false);

            if (!enabled) {
                log.debug("飞书通知未启用");
                return;
            }

            if (webhook.isEmpty()) {
                log.error("飞书Webhook地址为空");
                return;
            }
            // 构建消息体
            Map<String, Object> messageBody = new HashMap<>();
            messageBody.put("msg_type", "text");

            Map<String, String> content = new HashMap<>();
            content.put("text", message);
            messageBody.put("content", content);

            // 如果有签名密钥，添加签名
            if (!secret.isEmpty()) {
                long timestamp = System.currentTimeMillis() / 1000;
                String sign = generateSign(secret, timestamp);
                messageBody.put("timestamp", String.valueOf(timestamp));
                messageBody.put("sign", sign);
            }

            // 设置请求头
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);

            // 发送请求
            HttpEntity<Map<String, Object>> request = new HttpEntity<>(messageBody, headers);
            ResponseEntity<String> response = restTemplate.exchange(
                    webhook,
                    HttpMethod.POST,
                    request,
                    String.class
            );

            // 检查响应
            if (response.getStatusCode().is2xxSuccessful()) {
                JsonNode jsonResponse = objectMapper.readTree(response.getBody());
                int code = jsonResponse.get("StatusCode").asInt();
                if (code != 0) {
                    String msg = jsonResponse.get("StatusMessage").asText();
                    throw new RuntimeException("飞书API返回错误: " + msg);
                }
                log.info("飞书消息发送成功");
            } else {
                throw new RuntimeException("飞书消息发送失败，HTTP状态码: " + response.getStatusCode());
            }
        } catch (Exception e) {
            log.warn("飞书消息发送错误,原因为:{}", e.getMessage(), e);
        }
    }

    private String generateSign(String secret, long timestamp) throws Exception {
        String stringToSign = timestamp + "\n" + secret;
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(stringToSign.getBytes("UTF-8"), "HmacSHA256"));
        byte[] signData = mac.doFinal(new byte[]{});
        return Base64.getEncoder().encodeToString(signData);
    }
}

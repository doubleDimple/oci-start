package com.doubledimple.ociserver.service.cloud.gcp.client;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.bouncycastle.jce.provider.BouncyCastleProvider;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

import java.io.FileInputStream;
import java.io.IOException;
import java.io.UnsupportedEncodingException;
import java.security.InvalidKeyException;
import java.security.KeyFactory;
import java.security.NoSuchAlgorithmException;
import java.security.PrivateKey;
import java.security.Security;
import java.security.Signature;
import java.security.SignatureException;
import java.security.spec.InvalidKeySpecException;
import java.security.spec.PKCS8EncodedKeySpec;
import java.util.Base64;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * GCP OAuth token 客户端（内存缓存，约 55 分钟）。
 */
@Component
@Slf4j
public class GcpAuthClient {

    private static final String OAUTH_TOKEN_URL = "https://oauth2.googleapis.com/token";
    private static final String SCOPE = "https://www.googleapis.com/auth/cloud-platform";
    /** 提前 5 分钟过期，token 通常 3600s */
    private static final long CACHE_TTL_MS = 55 * 60 * 1000L;

    private final RestTemplate restTemplate = new RestTemplate();
    private final ObjectMapper objectMapper = new ObjectMapper();
    private final ConcurrentHashMap<String, CachedToken> tokenCache = new ConcurrentHashMap<String, CachedToken>();

    public GcpAuthClient() {
        if (Security.getProvider(BouncyCastleProvider.PROVIDER_NAME) == null) {
            Security.addProvider(new BouncyCastleProvider());
        }
    }

    public String getAccessToken(String credentialsPath) throws IOException {
        if (credentialsPath == null || credentialsPath.isEmpty()) {
            throw new IOException("credentialsPath 为空");
        }
        CachedToken cached = tokenCache.get(credentialsPath);
        long now = System.currentTimeMillis();
        if (cached != null && cached.expireAtMs > now) {
            return cached.token;
        }

        synchronized (tokenCache) {
            cached = tokenCache.get(credentialsPath);
            if (cached != null && cached.expireAtMs > System.currentTimeMillis()) {
                return cached.token;
            }
            String token = fetchToken(credentialsPath);
            tokenCache.put(credentialsPath, new CachedToken(token, System.currentTimeMillis() + CACHE_TTL_MS));
            return token;
        }
    }

    public void invalidate(String credentialsPath) {
        if (credentialsPath != null) {
            tokenCache.remove(credentialsPath);
        }
    }

    private String fetchToken(String credentialsPath) throws IOException {
        Map<String, Object> credentialsJson;
        try (FileInputStream fileInputStream = new FileInputStream(credentialsPath)) {
            credentialsJson = objectMapper.readValue(fileInputStream, new TypeReference<Map<String, Object>>() {
            });
        }
        String clientEmail = (String) credentialsJson.get("client_email");
        String privateKeyPem = (String) credentialsJson.get("private_key");
        String jwt = createJwtToken(clientEmail, privateKeyPem);

        HttpHeaders headers = new HttpHeaders();
        headers.set("Content-Type", "application/x-www-form-urlencoded");
        String requestBody = "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=" + jwt;
        HttpEntity<String> request = new HttpEntity<String>(requestBody, headers);

        ResponseEntity<String> response = restTemplate.postForEntity(OAUTH_TOKEN_URL, request, String.class);
        Map<String, Object> tokenResponse = objectMapper.readValue(response.getBody(), new TypeReference<Map<String, Object>>() {
        });
        return (String) tokenResponse.get("access_token");
    }

    public String createJwtToken(String clientEmail, String privateKeyPem) {
        try {
            return createJwtWithBouncyCastle(clientEmail, privateKeyPem);
        } catch (Exception e) {
            throw new RuntimeException("创建JWT令牌失败", e);
        }
    }

    private String createJwtWithBouncyCastle(String clientEmail, String privateKeyPem)
            throws NoSuchAlgorithmException, InvalidKeySpecException, InvalidKeyException,
            UnsupportedEncodingException, SignatureException {
        privateKeyPem = privateKeyPem.replace("-----BEGIN PRIVATE KEY-----", "")
                .replace("-----END PRIVATE KEY-----", "")
                .replaceAll("\\s+", "");
        byte[] privateKeyDer = Base64.getDecoder().decode(privateKeyPem);

        PKCS8EncodedKeySpec keySpec = new PKCS8EncodedKeySpec(privateKeyDer);
        KeyFactory keyFactory = KeyFactory.getInstance("RSA");
        PrivateKey privateKey = keyFactory.generatePrivate(keySpec);

        long now = System.currentTimeMillis() / 1000L;
        String headerJson = "{\"alg\":\"RS256\",\"typ\":\"JWT\"}";
        String claimsJson = String.format(
                "{\"iss\":\"%s\",\"scope\":\"%s\",\"aud\":\"%s\",\"exp\":%d,\"iat\":%d}",
                clientEmail, SCOPE, OAUTH_TOKEN_URL, now + 3600, now);

        String encodedHeader = Base64.getUrlEncoder().withoutPadding().encodeToString(headerJson.getBytes("UTF-8"));
        String encodedClaims = Base64.getUrlEncoder().withoutPadding().encodeToString(claimsJson.getBytes("UTF-8"));
        String content = encodedHeader + "." + encodedClaims;

        Signature signature = Signature.getInstance("SHA256withRSA");
        signature.initSign(privateKey);
        signature.update(content.getBytes("UTF-8"));
        byte[] signatureBytes = signature.sign();
        String encodedSignature = Base64.getUrlEncoder().withoutPadding().encodeToString(signatureBytes);
        return content + "." + encodedSignature;
    }

    private static final class CachedToken {
        final String token;
        final long expireAtMs;

        CachedToken(String token, long expireAtMs) {
            this.token = token;
            this.expireAtMs = expireAtMs;
        }
    }
}

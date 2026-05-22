package com.doubledimple.ociserver.utils.google;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.doubledimple.ocicommon.enums.gcp.GcpMachineTypeEnum;
import com.doubledimple.ocicommon.enums.gcp.GcpPublicImageEnum;
import com.doubledimple.ociserver.config.constant.SystemScriptShell;
import com.doubledimple.ociserver.pojo.gcp.FirewallInfo;
import com.doubledimple.ociserver.pojo.gcp.FirewallListResponse;
import com.doubledimple.ociserver.pojo.gcp.ImageInfo;
import com.doubledimple.ociserver.pojo.gcp.ImageListResponse;
import com.doubledimple.ociserver.pojo.gcp.InstanceInfo;
import com.doubledimple.ociserver.pojo.gcp.InstanceListResponse;
import com.doubledimple.ociserver.pojo.gcp.InstanceRequest;
import com.doubledimple.ociserver.pojo.gcp.MachineTypeInfo;
import com.doubledimple.ociserver.pojo.gcp.MachineTypeListResponse;
import com.doubledimple.ociserver.pojo.gcp.NetworkInfo;
import com.doubledimple.ociserver.pojo.gcp.NetworkListResponse;
import com.doubledimple.ociserver.pojo.gcp.OperationResponse;
import com.doubledimple.ociserver.pojo.gcp.ZoneInfo;
import com.doubledimple.ociserver.pojo.gcp.ZoneListResponse;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.bouncycastle.jce.provider.BouncyCastleProvider;
import org.springframework.http.*;
import org.springframework.stereotype.Component;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestTemplate;

import java.io.FileInputStream;
import java.io.IOException;
import java.io.UnsupportedEncodingException;
import java.security.*;
import java.security.spec.InvalidKeySpecException;
import java.security.spec.PKCS8EncodedKeySpec;
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Base64;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * GCP API工具类，提供区域和实例相关操作
 *
 * @version 1.0.0
 * @Author doubleDimple
 * @date 2025-06-22 14:14
 */
@Component
@Slf4j
public class GcpApiUtil {
    // API URL常量
    private static final String GCP_ZONES_API_URL = "https://compute.googleapis.com/compute/v1/projects/{projectId}/zones";
    private static final String GCP_INSTANCES_API_URL = "https://compute.googleapis.com/compute/v1/projects/{projectId}/zones/{zone}/instances";
    private static final String GCP_INSTANCE_API_URL = "https://compute.googleapis.com/compute/v1/projects/{projectId}/zones/{zone}/instances/{instanceName}";


    private static final String GCP_INSTANCE_ALL_API_URL = "https://compute.googleapis.com/compute/v1/projects/{projectId}/aggregated/instances";
    private static final String GCP_INSTANCE_ACTION_API_URL = "https://compute.googleapis.com/compute/v1/projects/{projectId}/zones/{zone}/instances/{instanceName}/{action}";
    private static final String GCP_MACHINE_TYPES_API_URL = "https://compute.googleapis.com/compute/v1/projects/{projectId}/zones/{zone}/machineTypes";
    private static final String GCP_IMAGES_API_URL = "https://compute.googleapis.com/compute/v1/projects/{projectId}/global/images";
    private static final String GCP_GLOBAL_IMAGES_API_URL = "https://compute.googleapis.com/compute/v1/projects/{imageProject}/global/images";
    private static final String GCP_NETWORKS_API_URL = "https://compute.googleapis.com/compute/v1/projects/{projectId}/global/networks";

    private static final String OAUTH_TOKEN_URL = "https://oauth2.googleapis.com/token";
    private static final String SCOPE = "https://www.googleapis.com/auth/cloud-platform";

    private static final String FIRE_WALL_API_URL  = "https://compute.googleapis.com/compute/v1/projects/{projectId}/global/firewalls/{firewallName}";

    private static final String GLOBAL_FIRE_WALL_API_URL  = "https://compute.googleapis.com/compute/v1/projects/{projectId}/global/firewalls";

    private final RestTemplate restTemplate;
    private final ObjectMapper objectMapper;

    public GcpApiUtil() {
        this.restTemplate = new RestTemplate();
        this.objectMapper = new ObjectMapper();

        // 注册BouncyCastle提供程序，确保只注册一次
        if (Security.getProvider(BouncyCastleProvider.PROVIDER_NAME) == null) {
            Security.addProvider(new BouncyCastleProvider());
        }
    }

    /**
     * 获取GCP可用区域列表
     *
     * @param projectId GCP项目ID
     * @param credentialsPath 服务账号密钥文件路径
     * @return 可用区域列表
     */
    public List<ZoneInfo> listZones(String projectId, String credentialsPath) throws IOException {
        // 1. 获取访问令牌
        String accessToken = getAccessToken(credentialsPath);

        // 2. 设置请求头
        HttpHeaders headers = new HttpHeaders();
        headers.set("Authorization", "Bearer " + accessToken);
        HttpEntity<String> entity = new HttpEntity<>(headers);

        // 3. 调用GCP REST API获取区域列表
        ResponseEntity<String> response = restTemplate.exchange(
                GCP_ZONES_API_URL,
                HttpMethod.GET,
                entity,
                String.class,
                projectId
        );

        // 4. 解析响应
        String responseBody = response.getBody();
        ZoneListResponse zoneListResponse = objectMapper.readValue(responseBody, ZoneListResponse.class);

        return zoneListResponse.getItems() != null ? zoneListResponse.getItems() : Collections.emptyList();
    }

    /**
     * 获取指定区域中的虚拟机实例列表
     *
     * @param projectId GCP项目ID
     * @param zone 区域名称
     * @param credentialsPath 服务账号密钥文件路径
     * @return 实例列表
     */
    public List<InstanceInfo> listInstances(String projectId, String zone, String credentialsPath) throws IOException {
        // 1. 获取访问令牌
        String accessToken = getAccessToken(credentialsPath);

        // 2. 设置请求头
        HttpHeaders headers = new HttpHeaders();
        headers.set("Authorization", "Bearer " + accessToken);
        HttpEntity<String> entity = new HttpEntity<>(headers);

        // 3. 调用GCP REST API获取实例列表
        ResponseEntity<String> response = restTemplate.exchange(
                GCP_INSTANCES_API_URL,
                HttpMethod.GET,
                entity,
                String.class,
                projectId,
                zone
        );

        // 4. 解析响应
        String responseBody = response.getBody();
        InstanceListResponse instanceListResponse = objectMapper.readValue(responseBody, InstanceListResponse.class);

        return instanceListResponse.getItems() != null ? instanceListResponse.getItems() : Collections.emptyList();
    }

    /**
     * 获取实例详细信息
     *
     * @param projectId GCP项目ID
     * @param zone 区域名称
     * @param instanceName 实例名称
     * @param credentialsPath 服务账号密钥文件路径
     * @return 实例详细信息
     */
    public InstanceInfo getInstance(String projectId, String zone, String instanceName, String credentialsPath) throws IOException {
        // 1. 获取访问令牌
        String accessToken = getAccessToken(credentialsPath);

        // 2. 设置请求头
        HttpHeaders headers = new HttpHeaders();
        headers.set("Authorization", "Bearer " + accessToken);
        HttpEntity<String> entity = new HttpEntity<>(headers);

        // 3. 调用GCP REST API获取实例详情
        ResponseEntity<String> response = restTemplate.exchange(
                GCP_INSTANCE_API_URL,
                HttpMethod.GET,
                entity,
                String.class,
                projectId,
                zone,
                instanceName
        );

        // 4. 解析响应
        String responseBody = response.getBody();
        log.debug("获取实例详情: {}", responseBody);
        return JSON.parseObject(responseBody,InstanceInfo.class);
    }

    /**
     * 创建虚拟机实例
     *
     * @param projectId GCP项目ID
     * @param zone 区域名称
     * @param instanceRequest 实例创建请求
     * @param credentialsPath 服务账号密钥文件路径
     * @return 操作响应
     */
    public OperationResponse createInstance(String projectId, String zone, InstanceRequest instanceRequest, String credentialsPath) throws IOException {
        // 1. 获取访问令牌
        String accessToken = getAccessToken(credentialsPath);

        // 2. 设置请求头
        HttpHeaders headers = new HttpHeaders();
        headers.set("Authorization", "Bearer " + accessToken);
        headers.setContentType(MediaType.APPLICATION_JSON);

        // 3. 准备请求体
        String requestBody = objectMapper.writeValueAsString(instanceRequest);
        HttpEntity<String> entity = new HttpEntity<>(requestBody, headers);

        // 4. 调用GCP REST API创建实例
        ResponseEntity<String> response = restTemplate.exchange(
                GCP_INSTANCES_API_URL,
                HttpMethod.POST,
                entity,
                String.class,
                projectId,
                zone
        );

        // 5. 解析响应
        String responseBody = response.getBody();
        return objectMapper.readValue(responseBody, OperationResponse.class);
    }

    /**
     * 删除虚拟机实例
     *
     * @param projectId GCP项目ID
     * @param zone 区域名称
     * @param instanceName 实例名称
     * @param credentialsPath 服务账号密钥文件路径
     * @return 操作响应
     */
    public OperationResponse deleteInstance(String projectId, String zone, String instanceName, String credentialsPath) throws IOException {
        // 1. 获取访问令牌
        String accessToken = getAccessToken(credentialsPath);

        // 2. 设置请求头
        HttpHeaders headers = new HttpHeaders();
        headers.set("Authorization", "Bearer " + accessToken);
        HttpEntity<String> entity = new HttpEntity<>(headers);

        // 3. 调用GCP REST API删除实例
        ResponseEntity<String> response = restTemplate.exchange(
                GCP_INSTANCE_API_URL,
                HttpMethod.DELETE,
                entity,
                String.class,
                projectId,
                zone,
                instanceName
        );

        // 4. 解析响应
        String responseBody = response.getBody();
        return objectMapper.readValue(responseBody, OperationResponse.class);
    }

    /**
     * 启动虚拟机实例
     *
     * @param projectId GCP项目ID
     * @param zone 区域名称
     * @param instanceName 实例名称
     * @param credentialsPath 服务账号密钥文件路径
     * @return 操作响应
     */
    public OperationResponse startInstance(String projectId, String zone, String instanceName, String credentialsPath) throws IOException {
        return performInstanceAction(projectId, zone, instanceName, "start", credentialsPath);
    }

    /**
     * 停止虚拟机实例
     *
     * @param projectId GCP项目ID
     * @param zone 区域名称
     * @param instanceName 实例名称
     * @param credentialsPath 服务账号密钥文件路径
     * @return 操作响应
     */
    public OperationResponse stopInstance(String projectId, String zone, String instanceName, String credentialsPath) throws IOException {
        return performInstanceAction(projectId, zone, instanceName, "stop", credentialsPath);
    }

    /**
     * 重启虚拟机实例
     *
     * @param projectId GCP项目ID
     * @param zone 区域名称
     * @param instanceName 实例名称
     * @param credentialsPath 服务账号密钥文件路径
     * @return 操作响应
     */
    public OperationResponse resetInstance(String projectId, String zone, String instanceName, String credentialsPath) throws IOException {
        return performInstanceAction(projectId, zone, instanceName, "reset", credentialsPath);
    }

    /**
     * 挂起虚拟机实例
     *
     * @param projectId GCP项目ID
     * @param zone 区域名称
     * @param instanceName 实例名称
     * @param credentialsPath 服务账号密钥文件路径
     * @return 操作响应
     */
    public OperationResponse suspendInstance(String projectId, String zone, String instanceName, String credentialsPath) throws IOException {
        return performInstanceAction(projectId, zone, instanceName, "suspend", credentialsPath);
    }

    /**
     * 恢复虚拟机实例
     *
     * @param projectId GCP项目ID
     * @param zone 区域名称
     * @param instanceName 实例名称
     * @param credentialsPath 服务账号密钥文件路径
     * @return 操作响应
     */
    public OperationResponse resumeInstance(String projectId, String zone, String instanceName, String credentialsPath) throws IOException {
        return performInstanceAction(projectId, zone, instanceName, "resume", credentialsPath);
    }

    /**
     * 对实例执行操作（启动、停止、重启等）
     *
     * @param projectId GCP项目ID
     * @param zone 区域名称
     * @param instanceName 实例名称
     * @param action 操作名称（start、stop、reset等）
     * @param credentialsPath 服务账号密钥文件路径
     * @return 操作响应
     */
    private OperationResponse performInstanceAction(String projectId, String zone, String instanceName, String action, String credentialsPath) throws IOException {
        // 1. 获取访问令牌
        String accessToken = getAccessToken(credentialsPath);

        // 2. 设置请求头
        HttpHeaders headers = new HttpHeaders();
        headers.set("Authorization", "Bearer " + accessToken);
        HttpEntity<String> entity = new HttpEntity<>(headers);

        // 3. 调用GCP REST API执行实例操作
        ResponseEntity<String> response = restTemplate.exchange(
                GCP_INSTANCE_ACTION_API_URL,
                HttpMethod.POST,
                entity,
                String.class,
                projectId,
                zone,
                instanceName,
                action
        );

        // 4. 解析响应
        String responseBody = response.getBody();
        return objectMapper.readValue(responseBody, OperationResponse.class);
    }

    /**
     * 获取可用的机器类型列表
     *
     * @param projectId GCP项目ID
     * @param zone 区域名称
     * @param credentialsPath 服务账号密钥文件路径
     * @return 机器类型列表
     */
    public List<MachineTypeInfo> listMachineTypes(String projectId, String zone, String credentialsPath) throws IOException {
        // 1. 获取访问令牌
        String accessToken = getAccessToken(credentialsPath);

        // 2. 设置请求头
        HttpHeaders headers = new HttpHeaders();
        headers.set("Authorization", "Bearer " + accessToken);
        HttpEntity<String> entity = new HttpEntity<>(headers);

        // 3. 调用GCP REST API获取机器类型列表
        ResponseEntity<String> response = restTemplate.exchange(
                GCP_MACHINE_TYPES_API_URL,
                HttpMethod.GET,
                entity,
                String.class,
                projectId,
                zone
        );

        // 4. 解析响应
        String responseBody = response.getBody();
        MachineTypeListResponse machineTypeListResponse = objectMapper.readValue(responseBody, MachineTypeListResponse.class);

        return machineTypeListResponse.getItems() != null ? machineTypeListResponse.getItems() : Collections.emptyList();
    }

    /**
     * 获取可用的镜像列表
     *
     * @param projectId GCP项目ID
     * @param credentialsPath 服务账号密钥文件路径
     * @return 镜像列表
     */
    public List<ImageInfo> listImages(String projectId, String credentialsPath) throws IOException {
        // 1. 获取访问令牌
        String accessToken = getAccessToken(credentialsPath);

        // 2. 设置请求头
        HttpHeaders headers = new HttpHeaders();
        headers.set("Authorization", "Bearer " + accessToken);
        HttpEntity<String> entity = new HttpEntity<>(headers);

        // 3. 调用GCP REST API获取镜像列表
        ResponseEntity<String> response = restTemplate.exchange(
                GCP_IMAGES_API_URL,
                HttpMethod.GET,
                entity,
                String.class,
                projectId
        );

        // 4. 解析响应
        String responseBody = response.getBody();
        ImageListResponse imageListResponse = objectMapper.readValue(responseBody, ImageListResponse.class);

        return imageListResponse.getItems() != null ? imageListResponse.getItems() : Collections.emptyList();
    }

    /**
     * 获取可用的镜像列表（包括公共镜像和自定义镜像）
     *
     * @param projectId GCP项目ID
     * @param credentialsPath 服务账号密钥文件路径
     * @return 镜像列表
     */
    public List<ImageInfo> getAllAvailableImages(String projectId, String credentialsPath) throws IOException {
        List<ImageInfo> allImages = new ArrayList<>();

        // 1. 先获取项目自定义镜像（可能为空）
        try {
            List<ImageInfo> customImages = listImages(projectId, credentialsPath);
            if (customImages != null && !customImages.isEmpty()) {
                allImages.addAll(customImages);
            }
        } catch (Exception e) {
            // 如果获取自定义镜像失败，记录错误但继续获取公共镜像
            System.err.println("获取自定义镜像失败: " + e.getMessage());
        }

        // 2. 获取常用的公共镜像项目
        String[] publicImageProjects = {
                "debian-cloud",       // Debian 镜像
                "ubuntu-os-cloud",    // Ubuntu 镜像
        };

        // 3. 获取每个公共项目的镜像
        for (String imageProject : publicImageProjects) {
            try {
                List<ImageInfo> publicImages = listPublicImages(imageProject, credentialsPath);
                if (publicImages != null && !publicImages.isEmpty()) {
                    // 在添加到结果前添加项目标识
                    for (ImageInfo image : publicImages) {
                        // 添加源项目信息，方便在UI中显示
                        if (image.getLabels() == null) {
                            image.setLabels(new HashMap<>());
                        }
                        image.getLabels().put("source_project", imageProject);
                    }
                    allImages.addAll(publicImages);
                }
            } catch (Exception e) {
                // 如果获取某个公共镜像项目失败，记录错误但继续获取其他项目
                System.err.println("获取公共镜像 " + imageProject + " 失败: " + e.getMessage());
            }
        }

        return allImages;
    }


    /**
     * 获取指定数量的最新 Debian 和 Ubuntu 镜像
     *
     * @param credentialsPath 服务账号密钥文件路径
     * @param versionsPerDistro 每个发行版保留的版本数量
     * @return 筛选后的镜像列表
     */
    public List<ImageInfo> getLatestDebianAndUbuntuImages(String credentialsPath, int versionsPerDistro) throws IOException {
        List<ImageInfo> result = new ArrayList<>();

        // 获取 Debian 镜像
        try {
            Map<String, List<ImageInfo>> debianImagesByFamily = getLatestImagesGroupedByFamily("debian-cloud", credentialsPath, versionsPerDistro);
            for (List<ImageInfo> familyImages : debianImagesByFamily.values()) {
                result.addAll(familyImages);
            }
        } catch (Exception e) {
            System.err.println("获取 Debian 镜像失败: " + e.getMessage());
        }
        return result;
    }

    /**
     * 获取指定项目的镜像，按族分组并只保留每个族的最新几个版本
     *
     * @param imageProject 镜像项目
     * @param credentialsPath 服务账号密钥文件路径
     * @param versionsToKeep 每个族保留的版本数量
     * @return 按族分组的镜像列表
     */
    private Map<String, List<ImageInfo>> getLatestImagesGroupedByFamily(String imageProject, String credentialsPath, int versionsToKeep) throws IOException {
        // 获取所有镜像
        List<ImageInfo> allImages = listPublicImages(imageProject, credentialsPath);

        // 按族分组
        Map<String, List<ImageInfo>> imagesByFamily = new HashMap<>();
        for (ImageInfo image : allImages) {
            // 跳过弃用的镜像
            if (image.getDeprecated() != null) {
                continue;
            }

            // 只处理有族信息的镜像
            String family = image.getFamily();
            if (family == null || family.isEmpty()) {
                continue;
            }

            // 按族分组
            List<ImageInfo> familyImages = imagesByFamily.computeIfAbsent(family, k -> new ArrayList<>());
            familyImages.add(image);
        }

        // 对每个族的镜像按创建时间排序，并只保留最新的几个版本
        Map<String, List<ImageInfo>> result = new HashMap<>();
        for (Map.Entry<String, List<ImageInfo>> entry : imagesByFamily.entrySet()) {
            String family = entry.getKey();
            List<ImageInfo> familyImages = entry.getValue();

            // 按创建时间排序
            familyImages.sort((a, b) -> {
                try {
                    Date dateA = parseDate(a.getCreationTimestamp());
                    Date dateB = parseDate(b.getCreationTimestamp());
                    return dateB.compareTo(dateA);  // 降序排列，最新的在前
                } catch (Exception e) {
                    return 0;
                }
            });

            // 只保留最新的几个版本
            if (familyImages.size() > versionsToKeep) {
                familyImages = familyImages.subList(0, versionsToKeep);
            }

            // 添加项目和族信息到标签
            for (ImageInfo image : familyImages) {
                if (image.getLabels() == null) {
                    image.setLabels(new HashMap<>());
                }
                image.getLabels().put("source_project", imageProject);
                image.getLabels().put("family", family);
            }

            result.put(family, familyImages);
        }

        return result;
    }

    /**
     * 解析GCP时间戳字符串为日期对象
     */
    private Date parseDate(String timestamp) throws ParseException {
        if (timestamp == null || timestamp.isEmpty()) {
            return new Date(0);
        }

        // GCP时间戳格式示例: "2023-06-12T15:30:45.123-07:00"
        SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSXXX");
        return sdf.parse(timestamp);
    }

    /**
     * 获取公共镜像列表（如Debian、Ubuntu、CentOS等）
     *
     * @param imageProject 镜像项目（如debian-cloud, ubuntu-os-cloud, centos-cloud等）
     * @param credentialsPath 服务账号密钥文件路径
     * @return 镜像列表
     */
    public List<ImageInfo> listPublicImages(String imageProject, String credentialsPath) throws IOException {
        // 1. 获取访问令牌
        String accessToken = getAccessToken(credentialsPath);

        // 2. 设置请求头
        HttpHeaders headers = new HttpHeaders();
        headers.set("Authorization", "Bearer " + accessToken);
        HttpEntity<String> entity = new HttpEntity<>(headers);

        // 3. 调用GCP REST API获取公共镜像列表
        ResponseEntity<String> response = restTemplate.exchange(
                GCP_GLOBAL_IMAGES_API_URL,
                HttpMethod.GET,
                entity,
                String.class,
                imageProject
        );

        // 4. 解析响应
        String responseBody = response.getBody();
        ImageListResponse imageListResponse = objectMapper.readValue(responseBody, ImageListResponse.class);

        return imageListResponse.getItems() != null ? imageListResponse.getItems() : Collections.emptyList();
    }


    /**
     * 获取可用的网络列表
     *
     * @param projectId GCP项目ID
     * @param credentialsPath 服务账号密钥文件路径
     * @return 网络列表
     */
    public List<NetworkInfo> listNetworks(String projectId, String credentialsPath) throws IOException {
        // 1. 获取访问令牌
        String accessToken = getAccessToken(credentialsPath);

        // 2. 设置请求头
        HttpHeaders headers = new HttpHeaders();
        headers.set("Authorization", "Bearer " + accessToken);
        HttpEntity<String> entity = new HttpEntity<>(headers);

        // 3. 调用GCP REST API获取网络列表
        ResponseEntity<String> response = restTemplate.exchange(
                GCP_NETWORKS_API_URL,
                HttpMethod.GET,
                entity,
                String.class,
                projectId
        );

        // 4. 解析响应
        String responseBody = response.getBody();
        NetworkListResponse networkListResponse = objectMapper.readValue(responseBody, NetworkListResponse.class);

        return networkListResponse.getItems() != null ? networkListResponse.getItems() : Collections.emptyList();
    }

    /**
     * 从服务账号密钥文件获取访问令牌
     */
    private String getAccessToken(String credentialsPath) throws IOException {
        // 1. 读取服务账号密钥文件
        Map<String, Object> credentialsJson;
        try (FileInputStream fileInputStream = new FileInputStream(credentialsPath)) {
            credentialsJson = objectMapper.readValue(fileInputStream, new TypeReference<Map<String, Object>>() {});
        }

        // 2. 准备JWT声明
        String clientEmail = (String) credentialsJson.get("client_email");
        String privateKeyPem = (String) credentialsJson.get("private_key");

        // 使用BouncyCastle库处理RSA私钥签名
        String jwt = createJwtToken(clientEmail, privateKeyPem);

        // 3. 获取访问令牌
        HttpHeaders headers = new HttpHeaders();
        headers.set("Content-Type", "application/x-www-form-urlencoded");

        String requestBody = "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=" + jwt;
        HttpEntity<String> request = new HttpEntity<>(requestBody, headers);

        ResponseEntity<String> response = restTemplate.postForEntity(OAUTH_TOKEN_URL, request, String.class);
        Map<String, Object> tokenResponse = objectMapper.readValue(response.getBody(), new TypeReference<Map<String, Object>>() {});

        return (String) tokenResponse.get("access_token");
    }

    /**
     * 创建JWT令牌
     */
    public String createJwtToken(String clientEmail, String privateKeyPem) {
        try {
            return createJwtWithBouncyCastle(clientEmail, privateKeyPem);
        } catch (Exception e) {
            throw new RuntimeException("创建JWT令牌失败", e);
        }
    }

    /**
     * 使用BouncyCastle创建JWT
     */
    private String createJwtWithBouncyCastle(String clientEmail, String privateKeyPem) throws NoSuchAlgorithmException, InvalidKeySpecException, InvalidKeyException, UnsupportedEncodingException, SignatureException {
        // 1. 转换私钥
        privateKeyPem = privateKeyPem.replace("-----BEGIN PRIVATE KEY-----", "")
                .replace("-----END PRIVATE KEY-----", "")
                .replaceAll("\\s+", "");
        byte[] privateKeyDer = Base64.getDecoder().decode(privateKeyPem);

        PKCS8EncodedKeySpec keySpec = new PKCS8EncodedKeySpec(privateKeyDer);
        KeyFactory keyFactory = KeyFactory.getInstance("RSA");
        PrivateKey privateKey = keyFactory.generatePrivate(keySpec);

        // 2. 准备JWT数据
        long now = System.currentTimeMillis() / 1000L;
        String headerJson = "{\"alg\":\"RS256\",\"typ\":\"JWT\"}";
        String claimsJson = String.format(
                "{\"iss\":\"%s\",\"scope\":\"%s\",\"aud\":\"%s\",\"exp\":%d,\"iat\":%d}",
                clientEmail, SCOPE, OAUTH_TOKEN_URL, now + 3600, now);

        // 3. Base64编码
        String encodedHeader = Base64.getUrlEncoder().withoutPadding().encodeToString(headerJson.getBytes("UTF-8"));
        String encodedClaims = Base64.getUrlEncoder().withoutPadding().encodeToString(claimsJson.getBytes("UTF-8"));
        String content = encodedHeader + "." + encodedClaims;

        // 4. 签名
        Signature signature = Signature.getInstance("SHA256withRSA");
        signature.initSign(privateKey);
        signature.update(content.getBytes("UTF-8"));
        byte[] signatureBytes = signature.sign();
        String encodedSignature = Base64.getUrlEncoder().withoutPadding().encodeToString(signatureBytes);

        // 5. 组装JWT
        return content + "." + encodedSignature;
    }

    /**
     * 获取操作状态
     *
     * @param operationUrl 操作URL
     * @param credentialsPath 服务账号密钥文件路径
     * @return 操作状态
     */
    public OperationResponse getOperationStatus(String operationUrl, String credentialsPath) throws IOException {
        // 1. 获取访问令牌
        String accessToken = getAccessToken(credentialsPath);

        // 2. 设置请求头
        HttpHeaders headers = new HttpHeaders();
        headers.set("Authorization", "Bearer " + accessToken);
        HttpEntity<String> entity = new HttpEntity<>(headers);

        // 3. 调用GCP REST API获取操作状态
        ResponseEntity<String> response = restTemplate.exchange(
                operationUrl,
                HttpMethod.GET,
                entity,
                String.class
        );

        // 4. 解析响应
        String responseBody = response.getBody();
        return objectMapper.readValue(responseBody, OperationResponse.class);
    }

    /**
     * 等待操作完成
     *
     * @param operationUrl 操作URL
     * @param credentialsPath 服务账号密钥文件路径
     * @param timeoutSeconds 超时时间（秒）
     * @return 操作状态
     */
    public OperationResponse waitForOperation(String operationUrl, String credentialsPath, int timeoutSeconds) throws IOException, InterruptedException {
        long startTime = System.currentTimeMillis();
        long endTime = startTime + (timeoutSeconds * 1000L);

        while (System.currentTimeMillis() < endTime) {
            OperationResponse operation = getOperationStatus(operationUrl, credentialsPath);

            if ("DONE".equals(operation.getStatus())) {
                return operation;
            }

            // 等待一段时间再检查
            Thread.sleep(2000);
        }

        throw new IOException("操作超时");
    }



    /**
     * 创建虚拟机实例并启用root密码登录
     *
     * @param projectId GCP项目ID
     * @param zone 区域名称
     * @param instanceName 实例名称
     * @param machineType 机器类型，例如"n1-standard-1"
     * @param imageEnum 镜像枚举
     * @param diskSizeGb 磁盘大小(GB)
     * @param rootPassword root用户密码
     * @param credentialsPath 服务账号密钥文件路径
     * @return 操作响应
     */
    public OperationResponse createInstanceWithRootLogin(String projectId, String zone,
                                                         String instanceName, String machineType,
                                                         GcpPublicImageEnum imageEnum, int diskSizeGb,
                                                         String rootPassword, String credentialsPath) throws IOException {
        // 构建实例请求
        InstanceRequest request = new InstanceRequest();
        request.setName(instanceName);

        String fullMachineType;
        if (machineType.startsWith("https://") || machineType.startsWith("projects/") || machineType.startsWith("zones/")) {
            // 已经是完整或部分URL
            fullMachineType = machineType;
        } else {
            // 如果只是简单名称，转换为部分URL
            fullMachineType = "zones/" + zone + "/machineTypes/" + machineType;
        }

        // 设置机器类型
        /*InstanceRequest.MachineTypeConfig machineTypeConfig = new InstanceRequest.MachineTypeConfig();
        machineTypeConfig.setMachineType(fullMachineType);*/
        request.setMachineType(fullMachineType);

        // 设置磁盘
        List<InstanceRequest.AttachedDiskConfig> disks = new ArrayList<>();
        InstanceRequest.AttachedDiskConfig diskConfig = new InstanceRequest.AttachedDiskConfig();
        diskConfig.setBoot(true);
        diskConfig.setAutoDelete(true);

        InstanceRequest.AttachedDiskConfig.InitializeParamsConfig initializeParams =
                new InstanceRequest.AttachedDiskConfig.InitializeParamsConfig();

        // 使用枚举中定义的镜像族URL
        initializeParams.setSourceImage(imageEnum.getFamilyUrl());
        initializeParams.setDiskSizeGb(diskSizeGb);
        initializeParams.setDiskType("zones/" + zone + "/diskTypes/pd-standard");

        diskConfig.setInitializeParams(initializeParams);
        disks.add(diskConfig);
        request.setDisks(disks);

        // 设置网络
        List<InstanceRequest.NetworkInterfaceConfig> networkInterfaces = new ArrayList<>();
        InstanceRequest.NetworkInterfaceConfig networkInterface = new InstanceRequest.NetworkInterfaceConfig();
        networkInterface.setNetwork("global/networks/default");

        List<InstanceRequest.NetworkInterfaceConfig.AccessConfigConfig> accessConfigs = new ArrayList<>();
        InstanceRequest.NetworkInterfaceConfig.AccessConfigConfig accessConfig =
                new InstanceRequest.NetworkInterfaceConfig.AccessConfigConfig();
        accessConfig.setName("External NAT");
        accessConfig.setType("ONE_TO_ONE_NAT");
        accessConfigs.add(accessConfig);

        networkInterface.setAccessConfigs(accessConfigs);
        networkInterfaces.add(networkInterface);
        request.setNetworkInterfaces(networkInterfaces);

        // 设置标签
        Map<String, String> labels = new HashMap<>();
        labels.put("environment", "development");
        labels.put("created-by", "api");
        labels.put("os", imageEnum.getDisplayName().toLowerCase().replace(" ", "-"));
        labels.put("architecture", imageEnum.getArchitecture().toLowerCase());
        request.setLabels(labels);

        // 设置启动脚本，启用root密码登录
        Map<String, String> metadataItems = new HashMap<>();

        // 准备启动脚本 - 配置root密码登录
        String startupScript = createRootLoginScript(rootPassword);
        metadataItems.put("startup-script", startupScript);

        // 设置元数据
        InstanceRequest.MetadataConfig metadata = new InstanceRequest.MetadataConfig();
        List<InstanceRequest.MetadataConfig.MetadataItemConfig> items = new ArrayList<>();
        for (Map.Entry<String, String> entry : metadataItems.entrySet()) {
            InstanceRequest.MetadataConfig.MetadataItemConfig item = new InstanceRequest.MetadataConfig.MetadataItemConfig();
            item.setKey(entry.getKey());
            item.setValue(entry.getValue());
            items.add(item);
        }
        metadata.setItems(items);
        request.setMetadata(metadata);

        // 创建实例
        return createInstance(projectId, zone, request, credentialsPath);
    }

    /**
     * 创建启用root密码登录的脚本
     *
     * @param rootPassword root用户密码
     * @return 启动脚本
     */
    private String createRootLoginScript(String rootPassword) {
        // 创建安全的启动脚本，启用root密码登录
        StringBuilder script = new StringBuilder();
        script.append("#!/bin/bash\n");

        // 设置root密码
        script.append("echo root:").append(rootPassword).append(" | chpasswd\n");

        // 修改SSH配置文件，允许root登录和密码认证
        script.append("sed -i 's/^#\\?PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config\n");
        script.append("sed -i 's/^#\\?PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config\n");

        // 重启SSH服务以应用更改
        script.append("if [ -f /etc/systemd/system/sshd.service ]; then\n");
        script.append("  systemctl restart sshd\n");
        script.append("elif [ -f /etc/systemd/system/ssh.service ]; then\n");
        script.append("  systemctl restart ssh\n");
        script.append("else\n");
        script.append("  service sshd restart\n");
        script.append("fi\n");

        // 确保防火墙允许SSH连接（如果有）
        script.append("if command -v ufw &> /dev/null; then\n");
        script.append("  ufw allow ssh\n");
        script.append("fi\n");

        // 输出成功消息到日志
        script.append("echo 'Root login with password has been enabled.' > /root/root_login_enabled.log\n");

        return script.toString();
    }

    /**
     * 创建改进的启动脚本，修复SSH连接问题
     *
     * @param rootPassword root用户密码
     * @return 启动脚本
     */
    private String createEnhancedStartupScript(String rootPassword) {
        StringBuilder script = new StringBuilder();
        script.append("#!/bin/bash\n");
        script.append("# Enhanced startup script with root login and firewall disabled\n");
        script.append("# Log all output to a file for debugging\n");
        script.append("exec > /var/log/startup-script.log 2>&1\n");
        script.append("set -x\n\n");

        script.append("echo 'Starting enhanced setup...'\n");
        script.append("date\n\n");

        // 设置root密码
        script.append("# Set root password\n");
        script.append("echo 'Setting root password...'\n");
        script.append("echo 'root:").append(rootPassword).append("' | chpasswd\n");
        script.append("echo 'Root password set successfully'\n\n");

        // 备份原始SSH配置
        script.append("# Backup original SSH config\n");
        script.append("cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup\n\n");

        // 修改SSH配置文件，允许root登录和密码认证
        script.append("# Configure SSH for root login\n");
        script.append("echo 'Configuring SSH...'\n");

        // 更安全的SSH配置修改方式
        script.append("# Enable root login\n");
        script.append("sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config\n");
        script.append("grep -q '^PermitRootLogin' /etc/ssh/sshd_config || echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config\n\n");

        script.append("# Enable password authentication\n");
        script.append("sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config\n");
        script.append("grep -q '^PasswordAuthentication' /etc/ssh/sshd_config || echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config\n\n");

        script.append("# Disable PAM authentication if it's causing issues\n");
        script.append("sed -i 's/^#*UsePAM.*/UsePAM no/' /etc/ssh/sshd_config\n");
        script.append("grep -q '^UsePAM' /etc/ssh/sshd_config || echo 'UsePAM no' >> /etc/ssh/sshd_config\n\n");

        script.append("# Enable challenge response authentication\n");
        script.append("sed -i 's/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication yes/' /etc/ssh/sshd_config\n");
        script.append("grep -q '^ChallengeResponseAuthentication' /etc/ssh/sshd_config || echo 'ChallengeResponseAuthentication yes' >> /etc/ssh/sshd_config\n\n");

        // 验证SSH配置
        script.append("# Verify SSH configuration\n");
        script.append("echo 'Verifying SSH configuration...'\n");
        script.append("sshd -t\n");
        script.append("if [ $? -eq 0 ]; then\n");
        script.append("    echo 'SSH configuration is valid'\n");
        script.append("else\n");
        script.append("    echo 'SSH configuration is invalid, restoring backup'\n");
        script.append("    cp /etc/ssh/sshd_config.backup /etc/ssh/sshd_config\n");
        script.append("fi\n\n");

        // 关闭系统防火墙 (支持多种防火墙系统)
        script.append("# Disable system firewall\n");
        script.append("echo 'Disabling system firewalls...'\n");

        // UFW (Ubuntu)
        script.append("if command -v ufw &> /dev/null; then\n");
        script.append("  echo 'Disabling UFW...'\n");
        script.append("  ufw --force disable\n");
        script.append("  echo 'UFW firewall disabled'\n");
        script.append("fi\n\n");

        // firewalld (CentOS/RHEL/Fedora)
        script.append("if command -v firewalld &> /dev/null; then\n");
        script.append("  echo 'Disabling firewalld...'\n");
        script.append("  systemctl stop firewalld 2>/dev/null || true\n");
        script.append("  systemctl disable firewalld 2>/dev/null || true\n");
        script.append("  echo 'firewalld disabled'\n");
        script.append("fi\n\n");

        // iptables - 设置为允许所有流量
        script.append("if command -v iptables &> /dev/null; then\n");
        script.append("  echo 'Configuring iptables...'\n");
        script.append("  iptables -P INPUT ACCEPT\n");
        script.append("  iptables -P FORWARD ACCEPT\n");
        script.append("  iptables -P OUTPUT ACCEPT\n");
        script.append("  iptables -F\n");
        script.append("  iptables -X\n");
        script.append("  echo 'iptables rules cleared and set to ACCEPT'\n");
        script.append("fi\n\n");

        // 重启SSH服务以应用更改
        script.append("# Restart SSH service\n");
        script.append("echo 'Restarting SSH service...'\n");
        script.append("if systemctl is-active --quiet ssh; then\n");
        script.append("  systemctl restart ssh\n");
        script.append("  echo 'SSH service restarted (ssh)'\n");
        script.append("elif systemctl is-active --quiet sshd; then\n");
        script.append("  systemctl restart sshd\n");
        script.append("  echo 'SSH service restarted (sshd)'\n");
        script.append("else\n");
        script.append("  # Fallback for older systems\n");
        script.append("  service ssh restart 2>/dev/null || service sshd restart 2>/dev/null || true\n");
        script.append("  echo 'SSH service restarted (fallback)'\n");
        script.append("fi\n\n");

        // 等待SSH服务完全启动
        script.append("# Wait for SSH service to be ready\n");
        script.append("echo 'Waiting for SSH service to be ready...'\n");
        script.append("for i in {1..30}; do\n");
        script.append("  if netstat -tuln | grep ':22 ' > /dev/null 2>&1; then\n");
        script.append("    echo 'SSH service is listening on port 22'\n");
        script.append("    break\n");
        script.append("  fi\n");
        script.append("  sleep 1\n");
        script.append("done\n\n");

        // 验证SSH服务状态
        script.append("# Check SSH service status\n");
        script.append("echo 'Checking SSH service status...'\n");
        script.append("systemctl status ssh 2>/dev/null || systemctl status sshd 2>/dev/null || true\n");
        script.append("netstat -tuln | grep ':22' || ss -tuln | grep ':22' || true\n\n");

        // 输出成功消息到日志
        script.append("# Log completion\n");
        script.append("echo 'Enhanced setup completed:' | tee /root/setup_completed.log\n");
        script.append("echo '- Root login with password enabled' | tee -a /root/setup_completed.log\n");
        script.append("echo '- System firewall disabled' | tee -a /root/setup_completed.log\n");
        script.append("echo '- All ports accessible' | tee -a /root/setup_completed.log\n");
        script.append("echo '- SSH service restarted and verified' | tee -a /root/setup_completed.log\n");
        script.append("date | tee -a /root/setup_completed.log\n\n");

        // 最终验证
        script.append("# Final verification\n");
        script.append("echo 'Final SSH configuration check:'\n");
        script.append("grep -E '^(PermitRootLogin|PasswordAuthentication|UsePAM|ChallengeResponseAuthentication)' /etc/ssh/sshd_config\n");
        script.append("echo 'Setup script completed successfully'\n");

        return script.toString();
    }




    /**
     * 创建GCP防火墙规则
     *
     * @param projectId GCP项目ID
     * @param firewallRuleName 防火墙规则名称
     * @param networkName 网络名称，默认为"default"
     * @param allowedPorts 允许的端口列表
     * @param sourceRanges 源IP范围列表，默认为["0.0.0.0/0"]（允许所有IP）
     * @param targetTags 目标标签列表，用于关联实例
     * @param credentialsPath 服务账号密钥文件路径
     * @return 操作响应
     */
    public OperationResponse createFirewallRule(String projectId, String firewallRuleName,
                                                String networkName, List<Integer> allowedPorts,
                                                List<String> sourceRanges, List<String> targetTags,
                                                String credentialsPath) throws IOException {
        // 1. 获取访问令牌
        String accessToken = getAccessToken(credentialsPath);

        // 2. 设置请求头
        HttpHeaders headers = new HttpHeaders();
        headers.set("Authorization", "Bearer " + accessToken);
        headers.setContentType(MediaType.APPLICATION_JSON);

        // 3. 构建防火墙规则请求体
        Map<String, Object> firewallRule = new HashMap<>();
        firewallRule.put("name", firewallRuleName);
        firewallRule.put("network", "projects/" + projectId + "/global/networks/" + networkName);
        firewallRule.put("direction", "INGRESS");  // 入站规则
        firewallRule.put("priority", 1000);  // 默认优先级

        // 设置允许的源IP范围
        if (sourceRanges == null || sourceRanges.isEmpty()) {
            sourceRanges = Collections.singletonList("0.0.0.0/0");  // 默认允许所有IP
        }
        firewallRule.put("sourceRanges", sourceRanges);

        // 设置目标标签
        if (targetTags != null && !targetTags.isEmpty()) {
            firewallRule.put("targetTags", targetTags);
        }

        // 设置允许的协议和端口
        List<Map<String, Object>> allowed = new ArrayList<>();

        // TCP端口
        if (allowedPorts != null && !allowedPorts.isEmpty()) {
            Map<String, Object> tcpRule = new HashMap<>();
            tcpRule.put("IPProtocol", "tcp");
            tcpRule.put("ports", allowedPorts.stream().map(Object::toString).collect(Collectors.toList()));
            allowed.add(tcpRule);
        }

        // ICMP (ping)
        Map<String, Object> icmpRule = new HashMap<>();
        icmpRule.put("IPProtocol", "icmp");
        allowed.add(icmpRule);

        firewallRule.put("allowed", allowed);

        // 4. 转换为JSON
        String requestBody = objectMapper.writeValueAsString(firewallRule);
        HttpEntity<String> entity = new HttpEntity<>(requestBody, headers);

        // 5. 调用GCP REST API创建防火墙规则
        String firewallApiUrl = "https://compute.googleapis.com/compute/v1/projects/{projectId}/global/firewalls";
        ResponseEntity<String> response = restTemplate.exchange(
                firewallApiUrl,
                HttpMethod.POST,
                entity,
                String.class,
                projectId
        );

        // 6. 解析响应
        String responseBody = response.getBody();
        return objectMapper.readValue(responseBody, OperationResponse.class);
    }


    /**
     * 创建虚拟机实例并配置相应的防火墙规则（支持自定义机器类型）
     *
     * @param projectId GCP项目ID
     * @param zone 区域名称
     * @param instanceName 实例名称
     * @param machineType 机器类型，例如"n1-standard-1"或"custom-4-8192"
     * @param imageEnum 镜像枚举
     * @param diskSizeGb 磁盘大小(GB)
     * @param rootPassword root用户密码
     * @param allowedPorts 需要开放的端口列表，例如[22, 80, 443]
     * @param credentialsPath 服务账号密钥文件路径
     * @return Map包含实例操作和防火墙操作的响应
     */
    public Map<String, Object> createInstanceRootPassAndFirewall(String projectId, String zone,
                                                                 String instanceName, String machineType,
                                                                 GcpPublicImageEnum imageEnum, int diskSizeGb,
                                                                 String rootPassword, List<Integer> allowedPorts,
                                                                 String credentialsPath) throws IOException {
        Map<String, Object> result = new HashMap<>();

        // 1. 创建防火墙规则的唯一名称
        String firewallRuleName = "allow-oci-start";
        String networkTag = firewallRuleName + "-network-tag";
        List<String> networkTags = Collections.singletonList(networkTag);

        FirewallInfo firewallRule = getFirewallRule(projectId, firewallRuleName, credentialsPath);
        if (null != firewallRule){
            result.put("firewallRuleReused", true);
            result.put("firewallRuleName", firewallRule.getName());
        }else{
            // 创建防火墙规则
            OperationResponse firewallOperation = createFirewallRule(
                    projectId, firewallRuleName, "default", allowedPorts, null, networkTags, credentialsPath);
            result.put("firewallOperation", firewallOperation);
            result.put("firewallRuleCreated", true);
            result.put("firewallRuleName", firewallRuleName);
        }

        // 2. 创建实例请求
        InstanceRequest request = new InstanceRequest();
        request.setName(instanceName);

        // 3. 设置机器类型（支持自定义和预定义）
        String fullMachineType = getMachineTypeUrl(zone, machineType);
        request.setMachineType(fullMachineType);

        boolean isCustomMachine = machineType.startsWith("custom-");
        log.info("使用机器类型: {} (自定义: {})", fullMachineType, isCustomMachine);

        // 4. 设置磁盘
        List<InstanceRequest.AttachedDiskConfig> disks = new ArrayList<>();
        InstanceRequest.AttachedDiskConfig diskConfig = new InstanceRequest.AttachedDiskConfig();
        diskConfig.setBoot(true);
        diskConfig.setAutoDelete(true);

        InstanceRequest.AttachedDiskConfig.InitializeParamsConfig initializeParams =
                new InstanceRequest.AttachedDiskConfig.InitializeParamsConfig();

        // 使用枚举中定义的镜像族URL
        initializeParams.setSourceImage(imageEnum.getFamilyUrl());
        initializeParams.setDiskSizeGb(diskSizeGb);
        initializeParams.setDiskType("zones/" + zone + "/diskTypes/pd-standard");

        diskConfig.setInitializeParams(initializeParams);
        disks.add(diskConfig);
        request.setDisks(disks);

        // 5. 设置网络
        List<InstanceRequest.NetworkInterfaceConfig> networkInterfaces = new ArrayList<>();
        InstanceRequest.NetworkInterfaceConfig networkInterface = new InstanceRequest.NetworkInterfaceConfig();
        networkInterface.setNetwork("global/networks/default");

        List<InstanceRequest.NetworkInterfaceConfig.AccessConfigConfig> accessConfigs = new ArrayList<>();
        InstanceRequest.NetworkInterfaceConfig.AccessConfigConfig accessConfig =
                new InstanceRequest.NetworkInterfaceConfig.AccessConfigConfig();
        accessConfig.setName("External NAT");
        accessConfig.setType("ONE_TO_ONE_NAT");
        accessConfigs.add(accessConfig);

        networkInterface.setAccessConfigs(accessConfigs);
        networkInterfaces.add(networkInterface);
        request.setNetworkInterfaces(networkInterfaces);

        // 6. 设置标签
        Map<String, String> labels = new HashMap<>();
        labels.put("environment", "development");
        labels.put("created-by", "api");
        labels.put("machine-type", isCustomMachine ? "custom" : "predefined");

        if (isCustomMachine) {
            // 解析自定义机器类型的CPU和内存信息
            String[] parts = machineType.replace("custom-", "").split("-");
            if (parts.length >= 2) {
                labels.put("custom-cpu", parts[0]);
                labels.put("custom-memory-mb", parts[1]);
            }
        }

        labels.put("os", imageEnum.getImageName());
        labels.put("architecture", imageEnum.getArchitecture().toLowerCase());
        request.setLabels(labels);

        // 7. 正确设置网络标签，使用Tags对象
        InstanceRequest.TagsConfig tags = new InstanceRequest.TagsConfig();
        tags.setItems(networkTags);
        request.setTags(tags);

        // 8. 设置启动脚本，启用root密码登录
        InstanceRequest.MetadataConfig metadata = new InstanceRequest.MetadataConfig();
        List<InstanceRequest.MetadataConfig.MetadataItemConfig> items = new ArrayList<>();

        // 使用 startup-script 而不是 user-data
        String startupScript = SystemScriptShell.getStartupScript(rootPassword);
        InstanceRequest.MetadataConfig.MetadataItemConfig startupScriptItem = new InstanceRequest.MetadataConfig.MetadataItemConfig();
        startupScriptItem.setKey("startup-script");
        startupScriptItem.setValue(startupScript);
        items.add(startupScriptItem);

        metadata.setItems(items);
        request.setMetadata(metadata);

        // 9. 创建实例
        OperationResponse instanceOperation = createInstance(projectId, zone, request, credentialsPath);
        log.info("创建实例成功，实例详情: {}", JSON.toJSONString(instanceOperation));
        result.put("instanceOperation", instanceOperation);
        result.put("machineType", machineType);
        result.put("isCustomMachine", isCustomMachine);

        return result;
    }

    /**
     * 获取机器类型的完整URL（支持自定义和预定义）
     *
     * @param zone 区域名称
     * @param machineType 机器类型名称
     * @return 完整的机器类型URL
     */
    private String getMachineTypeUrl(String zone, String machineType) {
        if (machineType.startsWith("custom-")) {
            // 自定义机器类型：验证格式并直接使用
            validateCustomMachineType(machineType);
            return "zones/" + zone + "/machineTypes/" + machineType;
        } else {
            // 预定义机器类型：使用枚举验证
            GcpMachineTypeEnum machineTypeEnum = GcpMachineTypeEnum.getByName(machineType);
            if (machineTypeEnum == null) {
                log.warn("未找到机器类型 {}，使用默认类型 {}", machineType, GcpMachineTypeEnum.E2_MEDIUM.getName());
                machineTypeEnum = GcpMachineTypeEnum.E2_MEDIUM;
            }
            return machineTypeEnum.getFullUrl(zone);
        }
    }

    /**
     * 验证自定义机器类型格式和规则
     *
     * @param machineType 自定义机器类型名称
     * @throws IllegalArgumentException 如果格式或规则不符合要求
     */
    private void validateCustomMachineType(String machineType) {
        String[] parts = machineType.replace("custom-", "").split("-");
        if (parts.length != 2) {
            throw new IllegalArgumentException("自定义机器类型格式错误: " + machineType);
        }

        try {
            int cpuCount = Integer.parseInt(parts[0]);
            int memoryMb = Integer.parseInt(parts[1]);

            // 验证CPU规则：1或偶数
            if (cpuCount < 1 || cpuCount > 96) {
                throw new IllegalArgumentException("CPU数量必须在1-96之间: " + cpuCount);
            }
            if (cpuCount > 1 && cpuCount % 2 != 0) {
                throw new IllegalArgumentException("CPU数量必须是1或偶数: " + cpuCount);
            }

            // 验证内存规则
            double memoryGb = memoryMb / 1024.0;
            double minMemory = Math.max(0.9 * cpuCount, 1.0);
            double maxMemory = 6.5 * cpuCount;

            if (memoryGb < minMemory || memoryGb > maxMemory) {
                throw new IllegalArgumentException(
                        String.format("内存大小必须在 %.2fGB 到 %.2fGB 之间: %.2fGB",
                                minMemory, maxMemory, memoryGb));
            }

            // 验证内存是0.25GB(256MB)的倍数
            if (memoryMb % 256 != 0) {
                throw new IllegalArgumentException("内存大小必须是256MB(0.25GB)的倍数: " + memoryMb + "MB");
            }

        } catch (NumberFormatException e) {
            throw new IllegalArgumentException("无法解析自定义机器类型的CPU或内存: " + machineType);
        }
    }



    /**
     * 获取防火墙规则列表
     *
     * @param projectId GCP项目ID
     * @param credentialsPath 服务账号密钥文件路径
     * @return 防火墙规则列表
     */
    public List<FirewallInfo> listFirewallRules(String projectId, String credentialsPath) throws IOException {
        // 1. 获取访问令牌
        String accessToken = getAccessToken(credentialsPath);

        // 2. 设置请求头
        HttpHeaders headers = new HttpHeaders();
        headers.set("Authorization", "Bearer " + accessToken);
        HttpEntity<String> entity = new HttpEntity<>(headers);

        // 3. 调用GCP REST API获取防火墙规则列表
        String firewallApiUrl = "https://compute.googleapis.com/compute/v1/projects/{projectId}/global/firewalls";
        ResponseEntity<String> response = restTemplate.exchange(
                firewallApiUrl,
                HttpMethod.GET,
                entity,
                String.class,
                projectId
        );

        // 4. 解析响应
        String responseBody = response.getBody();
        FirewallListResponse firewallListResponse = objectMapper.readValue(responseBody, FirewallListResponse.class);

        return firewallListResponse.getItems() != null ? firewallListResponse.getItems() : Collections.emptyList();
    }

    /**
     * 根据规则名称检查防火墙规则是否存在
     *
     * @param projectId GCP项目ID
     * @param firewallRuleName 防火墙规则名称
     * @param credentialsPath 服务账号密钥文件路径
     * @return 如果规则存在则返回true，否则返回false
     */
    public boolean isFirewallRuleExist(String projectId, String firewallRuleName, String credentialsPath) throws IOException {
        try {
            // 1. 获取访问令牌
            String accessToken = getAccessToken(credentialsPath);

            // 2. 设置请求头
            HttpHeaders headers = new HttpHeaders();
            headers.set("Authorization", "Bearer " + accessToken);
            HttpEntity<String> entity = new HttpEntity<>(headers);

            // 3. 调用GCP REST API获取特定防火墙规则
            String firewallApiUrl = "https://compute.googleapis.com/compute/v1/projects/{projectId}/global/firewalls/{firewallName}";
            ResponseEntity<String> response = restTemplate.exchange(
                    firewallApiUrl,
                    HttpMethod.GET,
                    entity,
                    String.class,
                    projectId,
                    firewallRuleName
            );

            // 如果响应成功，则规则存在
            return response.getStatusCode().is2xxSuccessful();
        } catch (Exception e) {
            // 如果是404错误，规则不存在
            if (e.toString().contains("404")) {
                return false;
            }
            // 其他错误重新抛出
            throw e;
        }
    }

    /**
     * 获取防火墙规则详情
     *
     * @param projectId GCP项目ID
     * @param firewallRuleName 防火墙规则名称
     * @param credentialsPath 服务账号密钥文件路径
     * @return 防火墙规则详情，如果不存在则返回null
     */
    public FirewallInfo getFirewallRule(String projectId, String firewallRuleName, String credentialsPath) throws IOException {
        try {
            // 1. 获取访问令牌
            String accessToken = getAccessToken(credentialsPath);

            // 2. 设置请求头
            HttpHeaders headers = new HttpHeaders();
            headers.set("Authorization", "Bearer " + accessToken);
            HttpEntity<String> entity = new HttpEntity<>(headers);

            // 3. 调用GCP REST API获取特定防火墙规则
            ResponseEntity<String> response = restTemplate.exchange(
                    FIRE_WALL_API_URL,
                    HttpMethod.GET,
                    entity,
                    String.class,
                    projectId,
                    firewallRuleName
            );

            // 4. 解析响应
            String responseBody = response.getBody();
            return objectMapper.readValue(responseBody, FirewallInfo.class);
        } catch (Exception e) {
            // 如果是404错误，规则不存在
            if (e.toString().contains("404")) {
                return null;
            }
            // 其他错误重新抛出
            throw e;
        }
    }

    /**
     * 根据目标标签查找防火墙规则
     *
     * @param projectId GCP项目ID
     * @param targetTag 目标标签
     * @param credentialsPath 服务账号密钥文件路径
     * @return 匹配的防火墙规则列表
     */
    public List<FirewallInfo> findFirewallRulesByTargetTag(String projectId, String targetTag, String credentialsPath) throws IOException {
        // 1. 获取所有防火墙规则
        List<FirewallInfo> allRules = listFirewallRules(projectId, credentialsPath);

        // 2. 筛选包含指定目标标签的规则
        List<FirewallInfo> matchedRules = new ArrayList<>();
        for (FirewallInfo rule : allRules) {
            if (rule.getTargetTags() != null && rule.getTargetTags().contains(targetTag)) {
                matchedRules.add(rule);
            }
        }

        return matchedRules;
    }

    /**
     * 删除防火墙规则
     *
     * @param projectId GCP项目ID
     * @param firewallRuleName 防火墙规则名称
     * @param credentialsPath 服务账号密钥文件路径
     * @return 操作响应
     */
    public OperationResponse deleteFirewallRule(String projectId, String firewallRuleName, String credentialsPath) throws IOException {
        // 1. 获取访问令牌
        String accessToken = getAccessToken(credentialsPath);

        // 2. 设置请求头
        HttpHeaders headers = new HttpHeaders();
        headers.set("Authorization", "Bearer " + accessToken);
        HttpEntity<String> entity = new HttpEntity<>(headers);

        // 3. 调用GCP REST API删除防火墙规则
        String firewallApiUrl = "https://compute.googleapis.com/compute/v1/projects/{projectId}/global/firewalls/{firewallName}";
        ResponseEntity<String> response = restTemplate.exchange(
                firewallApiUrl,
                HttpMethod.DELETE,
                entity,
                String.class,
                projectId,
                firewallRuleName
        );

        // 4. 解析响应
        String responseBody = response.getBody();
        return objectMapper.readValue(responseBody, OperationResponse.class);
    }

    public List<InstanceInfo> getAllInstance(String projectId, String credentialsPath) throws IOException {
        // 1. 获取访问令牌
        String accessToken = getAccessToken(credentialsPath);

        // 2. 设置请求头
        HttpHeaders headers = new HttpHeaders();
        headers.set("Authorization", "Bearer " + accessToken);
        HttpEntity<String> entity = new HttpEntity<>(headers);

        try {
            // 3. 调用GCP REST API获取实例详情
            ResponseEntity<String> response = restTemplate.exchange(
                    GCP_INSTANCE_ALL_API_URL,
                    HttpMethod.GET,
                    entity,
                    String.class,
                    projectId
            );

            // 4. 解析响应
            String responseBody = response.getBody();
            log.info("获取实例详情响应: {}", responseBody);

            // 正确解析聚合响应
            return parseAggregatedInstanceResponseWithFastjson(responseBody);

        } catch (Exception e) {
            log.error("获取所有实例失败: {}", e.getMessage(), e);
            throw new IOException("获取实例列表失败: " + e.getMessage(), e);
        }
    }

    private List<InstanceInfo> parseAggregatedInstanceResponseWithFastjson(String responseBody) {
        List<InstanceInfo> allInstances = new ArrayList<>();

        try {
            // 解析为JSONObject
            JSONObject rootObject = JSON.parseObject(responseBody);
            JSONObject itemsObject = rootObject.getJSONObject("items");

            if (itemsObject == null) {
                return allInstances;
            }

            // 遍历每个zone
            for (String zoneName : itemsObject.keySet()) {
                JSONObject zoneObject = itemsObject.getJSONObject(zoneName);
                JSONArray instancesArray = zoneObject.getJSONArray("instances");

                if (instancesArray != null) {
                    // 解析该zone的实例
                    List<InstanceInfo> zoneInstances = instancesArray.toJavaList(InstanceInfo.class);
                    allInstances.addAll(zoneInstances);
                }
            }

            return allInstances;

        } catch (Exception e) {
            log.error("使用Fastjson解析聚合响应失败: {}", e.getMessage(), e);
            return allInstances;
        }
    }


    //ip相关===================================
    //ip相关===================================
    //ip相关===================================
    //ip相关===================================
    /**
     * 切换虚拟机实例的外部IP地址
     *
     * @param projectId GCP项目ID
     * @param zone 区域名称
     * @param instanceName 实例名称
     * @param credentialsPath 服务账号密钥文件路径
     * @return 操作结果，包含新的IP地址信息
     */
    public Map<String, Object> switchInstanceExternalIp(String projectId, String zone, String instanceName, String credentialsPath) throws IOException {
        Map<String, Object> result = new HashMap<>();

        try {
            // 1. 获取实例当前信息
            InstanceInfo instance = getInstance(projectId, zone, instanceName, credentialsPath);
            if (instance == null) {
                throw new IOException("实例不存在: " + instanceName);
            }

            // 2. 检查实例是否有外部IP
            String currentExternalIp = getCurrentExternalIp(instance);
            result.put("oldExternalIp", currentExternalIp);

            // 3. 删除当前的外部IP访问配置
            OperationResponse deleteOperation = deleteExternalIpAccessConfig(projectId, zone, instanceName, credentialsPath);
            result.put("deleteOperation", deleteOperation);

            // 4. 等待删除操作完成
            if (deleteOperation.getSelfLink() != null) {
                waitForOperation(deleteOperation.getSelfLink(), credentialsPath, 120);
            }

            // 5. 添加新的外部IP访问配置
            OperationResponse addOperation = addExternalIpAccessConfig(projectId, zone, instanceName, credentialsPath);
            result.put("addOperation", addOperation);

            // 6. 等待添加操作完成
            if (addOperation.getSelfLink() != null) {
                waitForOperation(addOperation.getSelfLink(), credentialsPath, 120);
            }

            // 7. 获取新的外部IP
            InstanceInfo updatedInstance = getInstance(projectId, zone, instanceName, credentialsPath);
            String newExternalIp = getCurrentExternalIp(updatedInstance);
            result.put("newExternalIp", newExternalIp);

            result.put("success", true);
            result.put("message", "IP切换成功");

            log.info("实例 {} 的外部IP从 {} 切换到 {}", instanceName, currentExternalIp, newExternalIp);

        } catch (Exception e) {
            result.put("success", false);
            result.put("error", e.getMessage());
            log.error("切换实例 {} 的IP失败: {}", instanceName, e.getMessage(), e);
            throw new IOException("切换IP失败: " + e.getMessage(), e);
        }

        return result;
    }

    /**
     * 删除实例的外部IP访问配置
     *
     * @param projectId GCP项目ID
     * @param zone 区域名称
     * @param instanceName 实例名称
     * @param credentialsPath 服务账号密钥文件路径
     * @return 操作响应
     */
    private OperationResponse deleteExternalIpAccessConfig(String projectId, String zone, String instanceName, String credentialsPath) throws IOException {
        // 1. 获取访问令牌
        String accessToken = getAccessToken(credentialsPath);

        // 2. 设置请求头
        HttpHeaders headers = new HttpHeaders();
        headers.set("Authorization", "Bearer " + accessToken);
        HttpEntity<String> entity = new HttpEntity<>(headers);

        // 3. 构建删除外部IP的API URL
        String deleteAccessConfigUrl = "https://compute.googleapis.com/compute/v1/projects/{projectId}/zones/{zone}/instances/{instanceName}/deleteAccessConfig";
        String urlWithParams = deleteAccessConfigUrl + "?accessConfig=External NAT&networkInterface=nic0";

        // 4. 调用GCP REST API删除外部IP访问配置
        ResponseEntity<String> response = restTemplate.exchange(
                urlWithParams,
                HttpMethod.POST,
                entity,
                String.class,
                projectId,
                zone,
                instanceName
        );

        // 5. 解析响应
        String responseBody = response.getBody();
        return objectMapper.readValue(responseBody, OperationResponse.class);
    }

    /**
     * 为实例添加新的外部IP访问配置
     *
     * @param projectId GCP项目ID
     * @param zone 区域名称
     * @param instanceName 实例名称
     * @param credentialsPath 服务账号密钥文件路径
     * @return 操作响应
     */
    private OperationResponse addExternalIpAccessConfig(String projectId, String zone, String instanceName, String credentialsPath) throws IOException {
        // 1. 获取访问令牌
        String accessToken = getAccessToken(credentialsPath);

        // 2. 设置请求头
        HttpHeaders headers = new HttpHeaders();
        headers.set("Authorization", "Bearer " + accessToken);
        headers.setContentType(MediaType.APPLICATION_JSON);

        // 3. 构建访问配置请求体
        Map<String, Object> accessConfig = new HashMap<>();
        accessConfig.put("name", "External NAT");
        accessConfig.put("type", "ONE_TO_ONE_NAT");
        // 不指定natIP，让GCP自动分配新的外部IP

        String requestBody = objectMapper.writeValueAsString(accessConfig);
        HttpEntity<String> entity = new HttpEntity<>(requestBody, headers);

        // 4. 构建添加外部IP的API URL
        String addAccessConfigUrl = "https://compute.googleapis.com/compute/v1/projects/{projectId}/zones/{zone}/instances/{instanceName}/addAccessConfig";
        String urlWithParams = addAccessConfigUrl + "?networkInterface=nic0";

        // 5. 调用GCP REST API添加外部IP访问配置
        ResponseEntity<String> response = restTemplate.exchange(
                urlWithParams,
                HttpMethod.POST,
                entity,
                String.class,
                projectId,
                zone,
                instanceName
        );

        // 6. 解析响应
        String responseBody = response.getBody();
        return objectMapper.readValue(responseBody, OperationResponse.class);
    }

    /**
     * 获取实例当前的外部IP地址
     *
     * @param instance 实例信息
     * @return 外部IP地址，如果没有则返回null
     */
    private String getCurrentExternalIp(InstanceInfo instance) {
        // 直接使用InstanceInfo中的便捷方法
        return instance.getExternalIP();
    }

    /**
     * 切换实例到指定的静态外部IP地址
     *
     * @param projectId GCP项目ID
     * @param zone 区域名称
     * @param instanceName 实例名称
     * @param staticIpAddress 要分配的静态IP地址名称
     * @param credentialsPath 服务账号密钥文件路径
     * @return 操作结果
     */
    public Map<String, Object> switchToStaticExternalIp(String projectId, String zone, String instanceName,
                                                        String staticIpAddress, String credentialsPath) throws IOException {
        Map<String, Object> result = new HashMap<>();

        try {
            // 1. 获取实例当前信息
            InstanceInfo instance = getInstance(projectId, zone, instanceName, credentialsPath);
            if (instance == null) {
                throw new IOException("实例不存在: " + instanceName);
            }

            String currentExternalIp = getCurrentExternalIp(instance);
            result.put("oldExternalIp", currentExternalIp);

            // 2. 删除当前的外部IP访问配置
            OperationResponse deleteOperation = deleteExternalIpAccessConfig(projectId, zone, instanceName, credentialsPath);

            // 3. 等待删除操作完成
            if (deleteOperation.getSelfLink() != null) {
                waitForOperation(deleteOperation.getSelfLink(), credentialsPath, 120);
            }

            // 4. 添加指定的静态外部IP
            OperationResponse addOperation = addStaticExternalIpAccessConfig(projectId, zone, instanceName, staticIpAddress, credentialsPath);
            result.put("addOperation", addOperation);

            // 5. 等待添加操作完成
            if (addOperation.getSelfLink() != null) {
                waitForOperation(addOperation.getSelfLink(), credentialsPath, 120);
            }

            // 6. 获取新的外部IP
            InstanceInfo updatedInstance = getInstance(projectId, zone, instanceName, credentialsPath);
            String newExternalIp = getCurrentExternalIp(updatedInstance);
            result.put("newExternalIp", newExternalIp);

            result.put("success", true);
            result.put("message", "IP切换到静态地址成功");

            log.info("实例 {} 的外部IP从 {} 切换到静态IP {}", instanceName, currentExternalIp, newExternalIp);

        } catch (Exception e) {
            result.put("success", false);
            result.put("error", e.getMessage());
            log.error("切换实例 {} 到静态IP失败: {}", instanceName, e.getMessage(), e);
            throw new IOException("切换到静态IP失败: " + e.getMessage(), e);
        }

        return result;
    }

    /**
     * 为实例添加指定的静态外部IP访问配置
     *
     * @param projectId GCP项目ID
     * @param zone 区域名称
     * @param instanceName 实例名称
     * @param staticIpAddress 静态IP地址名称
     * @param credentialsPath 服务账号密钥文件路径
     * @return 操作响应
     */
    private OperationResponse addStaticExternalIpAccessConfig(String projectId, String zone, String instanceName,
                                                              String staticIpAddress, String credentialsPath) throws IOException {
        // 1. 获取访问令牌
        String accessToken = getAccessToken(credentialsPath);

        // 2. 设置请求头
        HttpHeaders headers = new HttpHeaders();
        headers.set("Authorization", "Bearer " + accessToken);
        headers.setContentType(MediaType.APPLICATION_JSON);

        // 3. 构建访问配置请求体，指定静态IP
        Map<String, Object> accessConfig = new HashMap<>();
        accessConfig.put("name", "External NAT");
        accessConfig.put("type", "ONE_TO_ONE_NAT");
        // 指定静态IP地址的完整URL
        accessConfig.put("natIP", "projects/" + projectId + "/regions/" + extractRegionFromZone(zone) + "/addresses/" + staticIpAddress);

        String requestBody = objectMapper.writeValueAsString(accessConfig);
        HttpEntity<String> entity = new HttpEntity<>(requestBody, headers);

        // 4. 构建添加外部IP的API URL
        String addAccessConfigUrl = "https://compute.googleapis.com/compute/v1/projects/{projectId}/zones/{zone}/instances/{instanceName}/addAccessConfig";
        String urlWithParams = addAccessConfigUrl + "?networkInterface=nic0";

        // 5. 调用GCP REST API添加外部IP访问配置
        ResponseEntity<String> response = restTemplate.exchange(
                urlWithParams,
                HttpMethod.POST,
                entity,
                String.class,
                projectId,
                zone,
                instanceName
        );

        // 6. 解析响应
        String responseBody = response.getBody();
        return objectMapper.readValue(responseBody, OperationResponse.class);
    }

    /**
     * 从zone名称中提取region名称
     * 例如: us-central1-a -> us-central1
     *
     * @param zone zone名称
     * @return region名称
     */
    private String extractRegionFromZone(String zone) {
        int lastDashIndex = zone.lastIndexOf('-');
        if (lastDashIndex > 0) {
            return zone.substring(0, lastDashIndex);
        }
        return zone;
    }

    /**
     * 检查实例是否有外部IP
     *
     * @param projectId GCP项目ID
     * @param zone 区域名称
     * @param instanceName 实例名称
     * @param credentialsPath 服务账号密钥文件路径
     * @return 如果有外部IP返回IP地址，否则返回null
     */
    public String getInstanceExternalIp(String projectId, String zone, String instanceName, String credentialsPath) throws IOException {
        InstanceInfo instance = getInstance(projectId, zone, instanceName, credentialsPath);
        return getCurrentExternalIp(instance);
    }

    /**
     * 为实例分配外部IP（如果当前没有外部IP）
     *
     * @param projectId GCP项目ID
     * @param zone 区域名称
     * @param instanceName 实例名称
     * @param credentialsPath 服务账号密钥文件路径
     * @return 操作结果，包含分配的IP地址
     */
    public Map<String, Object> assignExternalIpToInstance(String projectId, String zone, String instanceName, String credentialsPath) throws IOException {
        Map<String, Object> result = new HashMap<>();

        try {
            // 1. 检查实例当前是否有外部IP
            String currentExternalIp = getInstanceExternalIp(projectId, zone, instanceName, credentialsPath);
            if (currentExternalIp != null && !currentExternalIp.isEmpty()) {
                result.put("success", false);
                result.put("message", "实例已经有外部IP: " + currentExternalIp);
                result.put("currentExternalIp", currentExternalIp);
                return result;
            }

            // 2. 为实例添加外部IP
            OperationResponse addOperation = addExternalIpAccessConfig(projectId, zone, instanceName, credentialsPath);
            result.put("addOperation", addOperation);

            // 3. 等待操作完成
            if (addOperation.getSelfLink() != null) {
                waitForOperation(addOperation.getSelfLink(), credentialsPath, 120);
            }

            // 4. 获取新分配的外部IP
            String newExternalIp = getInstanceExternalIp(projectId, zone, instanceName, credentialsPath);
            result.put("newExternalIp", newExternalIp);

            result.put("success", true);
            result.put("message", "外部IP分配成功");

            log.info("为实例 {} 分配外部IP: {}", instanceName, newExternalIp);

        } catch (Exception e) {
            result.put("success", false);
            result.put("error", e.getMessage());
            log.error("为实例 {} 分配外部IP失败: {}", instanceName, e.getMessage(), e);
            throw new IOException("分配外部IP失败: " + e.getMessage(), e);
        }

        return result;
    }

    /**
     * 移除实例的外部IP
     *
     * @param projectId GCP项目ID
     * @param zone 区域名称
     * @param instanceName 实例名称
     * @param credentialsPath 服务账号密钥文件路径
     * @return 操作结果
     */
    public Map<String, Object> removeExternalIpFromInstance(String projectId, String zone, String instanceName, String credentialsPath) throws IOException {
        Map<String, Object> result = new HashMap<>();

        try {
            // 1. 检查实例当前的外部IP
            String currentExternalIp = getInstanceExternalIp(projectId, zone, instanceName, credentialsPath);
            if (currentExternalIp == null || currentExternalIp.isEmpty()) {
                result.put("success", false);
                result.put("message", "实例当前没有外部IP");
                return result;
            }

            result.put("removedExternalIp", currentExternalIp);

            // 2. 删除外部IP访问配置
            OperationResponse deleteOperation = deleteExternalIpAccessConfig(projectId, zone, instanceName, credentialsPath);
            result.put("deleteOperation", deleteOperation);

            // 3. 等待操作完成
            if (deleteOperation.getSelfLink() != null) {
                waitForOperation(deleteOperation.getSelfLink(), credentialsPath, 120);
            }

            result.put("success", true);
            result.put("message", "外部IP移除成功");

            log.info("从实例 {} 移除外部IP: {}", instanceName, currentExternalIp);

        } catch (Exception e) {
            result.put("success", false);
            result.put("error", e.getMessage());
            log.error("从实例 {} 移除外部IP失败: {}", instanceName, e.getMessage(), e);
            throw new IOException("移除外部IP失败: " + e.getMessage(), e);
        }

        return result;
    }

    /**
     * 创建虚拟机实例并开启所有端口（关闭防火墙）
     *
     * @param projectId GCP项目ID
     * @param zone 区域名称
     * @param instanceName 实例名称
     * @param machineType 机器类型，例如"n1-standard-1"或"custom-4-8192"
     * @param imageEnum 镜像枚举
     * @param diskSizeGb 磁盘大小(GB)
     * @param rootPassword root用户密码
     * @param credentialsPath 服务账号密钥文件路径
     * @return Map包含实例操作和防火墙操作的响应
     */
    public Map<String, Object> createInstanceWithAllPortsOpen(String projectId,
                                                              String zone,
                                                              String instanceName,
                                                              String machineType,
                                                              GcpPublicImageEnum imageEnum,
                                                              int diskSizeGb,
                                                              String rootPassword,
                                                              String credentialsPath) throws IOException {
        Map<String, Object> result = new HashMap<>();

        // 1. 创建开启所有端口的防火墙规则
        String firewallRuleName = "allow-oci-start-all-ports";
        String networkTag = "all-ports-open";
        List<String> networkTags = Collections.singletonList(networkTag);

        // 检查是否已经存在通用的全端口开放规则
        String commonFirewallRule = "allow-all-ports";
        FirewallInfo existingRule = getFirewallRule(projectId, commonFirewallRule, credentialsPath);

        if (existingRule != null) {
            result.put("firewallRuleReused", true);
            result.put("firewallRuleName", existingRule.getName());
            //firewallRuleName = commonFirewallRule;
            networkTags = existingRule.getTargetTags();
        } else {
            // 创建新的全端口开放防火墙规则
            //firewallRuleName = commonFirewallRule;
            OperationResponse firewallOperation = createFirewallRuleAllPorts(
                    projectId, firewallRuleName, "default", networkTags, credentialsPath);
            result.put("firewallOperation", firewallOperation);
            result.put("firewallRuleCreated", true);
            result.put("firewallRuleName", firewallRuleName);
        }

        // 2. 创建实例请求
        InstanceRequest request = new InstanceRequest();
        request.setName(instanceName);

        // 3. 设置机器类型
        String fullMachineType = getMachineTypeUrl(zone, machineType);
        request.setMachineType(fullMachineType);

        boolean isCustomMachine = machineType.startsWith("custom-");
        log.info("使用机器类型: {} (自定义: {})", fullMachineType, isCustomMachine);

        // 4. 设置磁盘
        List<InstanceRequest.AttachedDiskConfig> disks = new ArrayList<>();
        InstanceRequest.AttachedDiskConfig diskConfig = new InstanceRequest.AttachedDiskConfig();
        diskConfig.setBoot(true);
        diskConfig.setAutoDelete(true);

        InstanceRequest.AttachedDiskConfig.InitializeParamsConfig initializeParams =
                new InstanceRequest.AttachedDiskConfig.InitializeParamsConfig();

        initializeParams.setSourceImage(imageEnum.getFamilyUrl());
        initializeParams.setDiskSizeGb(diskSizeGb);
        initializeParams.setDiskType("zones/" + zone + "/diskTypes/pd-standard");

        diskConfig.setInitializeParams(initializeParams);
        disks.add(diskConfig);
        request.setDisks(disks);

        // 5. 设置网络
        List<InstanceRequest.NetworkInterfaceConfig> networkInterfaces = new ArrayList<>();
        InstanceRequest.NetworkInterfaceConfig networkInterface = new InstanceRequest.NetworkInterfaceConfig();
        networkInterface.setNetwork("global/networks/default");

        List<InstanceRequest.NetworkInterfaceConfig.AccessConfigConfig> accessConfigs = new ArrayList<>();
        InstanceRequest.NetworkInterfaceConfig.AccessConfigConfig accessConfig =
                new InstanceRequest.NetworkInterfaceConfig.AccessConfigConfig();
        accessConfig.setName("External NAT");
        accessConfig.setType("ONE_TO_ONE_NAT");
        accessConfigs.add(accessConfig);

        networkInterface.setAccessConfigs(accessConfigs);
        networkInterfaces.add(networkInterface);
        request.setNetworkInterfaces(networkInterfaces);

        // 6. 设置标签
        Map<String, String> labels = new HashMap<>();
        labels.put("environment", "development");
        labels.put("created-by", "api");
        labels.put("firewall-mode", "all-ports-open");
        labels.put("security-level", "open");
        labels.put("machine-type", isCustomMachine ? "custom" : "predefined");

        if (isCustomMachine) {
            String[] parts = machineType.replace("custom-", "").split("-");
            if (parts.length >= 2) {
                labels.put("custom-cpu", parts[0]);
                labels.put("custom-memory-mb", parts[1]);
            }
        }

        labels.put("os", imageEnum.getImageName());
        labels.put("architecture", imageEnum.getArchitecture().toLowerCase());
        request.setLabels(labels);

        // 7. 设置网络标签，关联到开启所有端口的防火墙规则
        InstanceRequest.TagsConfig tags = new InstanceRequest.TagsConfig();
        tags.setItems(networkTags);
        request.setTags(tags);

        // 8. 设置启动脚本
        InstanceRequest.MetadataConfig metadata = new InstanceRequest.MetadataConfig();
        List<InstanceRequest.MetadataConfig.MetadataItemConfig> items = new ArrayList<>();

        // 增强的启动脚本，除了设置root密码，还关闭系统防火墙
        String enhancedStartupScript = createEnhancedStartupScript(rootPassword);
        InstanceRequest.MetadataConfig.MetadataItemConfig startupScriptItem =
                new InstanceRequest.MetadataConfig.MetadataItemConfig();
        startupScriptItem.setKey("startup-script");
        startupScriptItem.setValue(enhancedStartupScript);
        items.add(startupScriptItem);

        metadata.setItems(items);
        request.setMetadata(metadata);

        // 9. 创建实例
        OperationResponse instanceOperation = createInstance(projectId, zone, request, credentialsPath);
        log.info("创建开启所有端口的实例成功，实例详情: {}", JSON.toJSONString(instanceOperation));

        result.put("instanceOperation", instanceOperation);
        result.put("machineType", machineType);
        result.put("isCustomMachine", isCustomMachine);
        result.put("allPortsEnabled", true);
        result.put("networkTags", networkTags);

        return result;
    }

    /**
     * 创建开启所有端口的防火墙规则（含存在性检查）
     *
     * @param projectId GCP项目ID
     * @param firewallRuleName 防火墙规则名称
     * @param networkName 网络名称
     * @param targetTags 目标标签列表
     * @param credentialsPath 服务账号密钥文件路径
     * @return 操作响应
     */
    public OperationResponse createFirewallRuleAllPorts(String projectId, String firewallRuleName,
                                                        String networkName, List<String> targetTags,
                                                        String credentialsPath) throws IOException {
        String accessToken = getAccessToken(credentialsPath);

        HttpHeaders headers = new HttpHeaders();
        headers.set("Authorization", "Bearer " + accessToken);
        headers.setContentType(MediaType.APPLICATION_JSON);

        // 先检查防火墙规则是否已经存在
        try {
            String getFirewallUrl = "https://compute.googleapis.com/compute/v1/projects/{projectId}/global/firewalls/{firewallName}";
            HttpEntity<String> getEntity = new HttpEntity<>(headers);

            ResponseEntity<String> getResponse = restTemplate.exchange(
                    getFirewallUrl,
                    HttpMethod.GET,
                    getEntity,
                    String.class,
                    projectId,
                    firewallRuleName
            );

            if (getResponse.getStatusCode() == HttpStatus.OK) {
                log.info("防火墙规则 {} 已存在，直接使用", firewallRuleName);

                // 创建一个表示已存在的OperationResponse
                OperationResponse existingResponse = new OperationResponse();
                existingResponse.setKind("compute#operation");
                existingResponse.setStatus("DONE");
                existingResponse.setProgress(100);
                existingResponse.setOperationType("get");
                return existingResponse;
            }
        } catch (HttpClientErrorException e) {
            if (e.getStatusCode() == HttpStatus.NOT_FOUND) {
                log.info("防火墙规则 {} 不存在，开始创建", firewallRuleName);
            } else {
                log.error("检查防火墙规则时发生错误: {}", e.getMessage());
                throw e;
            }
        }

        // 构建防火墙规则 - 开启所有端口
        Map<String, Object> firewallRule = new HashMap<>();
        firewallRule.put("name", firewallRuleName);
        firewallRule.put("network", "projects/" + projectId + "/global/networks/" + networkName);
        firewallRule.put("direction", "INGRESS");
        firewallRule.put("priority", 1000);
        firewallRule.put("description", "Allow all ports for development instances - Created by API");

        // 允许所有IP
        firewallRule.put("sourceRanges", Collections.singletonList("0.0.0.0/0"));

        // 设置目标标签
        if (targetTags != null && !targetTags.isEmpty()) {
            firewallRule.put("targetTags", targetTags);
        }

        // 允许所有协议和端口
        List<Map<String, Object>> allowed = new ArrayList<>();

        // TCP - 所有端口 (0-65535)
        Map<String, Object> tcpRule = new HashMap<>();
        tcpRule.put("IPProtocol", "tcp");
        tcpRule.put("ports", Collections.singletonList("0-65535"));
        allowed.add(tcpRule);

        // UDP - 所有端口 (0-65535)
        Map<String, Object> udpRule = new HashMap<>();
        udpRule.put("IPProtocol", "udp");
        udpRule.put("ports", Collections.singletonList("0-65535"));
        allowed.add(udpRule);

        // ICMP (ping等)
        Map<String, Object> icmpRule = new HashMap<>();
        icmpRule.put("IPProtocol", "icmp");
        allowed.add(icmpRule);

        firewallRule.put("allowed", allowed);

        String requestBody = objectMapper.writeValueAsString(firewallRule);
        HttpEntity<String> entity = new HttpEntity<>(requestBody, headers);

        String firewallApiUrl = "https://compute.googleapis.com/compute/v1/projects/{projectId}/global/firewalls";
        ResponseEntity<String> response = restTemplate.exchange(
                firewallApiUrl,
                HttpMethod.POST,
                entity,
                String.class,
                projectId
        );

        String responseBody = response.getBody();
        log.info("创建全端口开放防火墙规则成功: {} (TCP/UDP: 0-65535, ICMP: all)", firewallRuleName);

        return objectMapper.readValue(responseBody, OperationResponse.class);
    }
}
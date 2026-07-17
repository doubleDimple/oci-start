package com.doubledimple.ociserver.utils.oracle;

import com.doubledimple.dao.entity.Tenant;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.core.ComputeClient;
import com.oracle.bmc.core.model.CreateInstanceConsoleConnectionDetails;
import com.oracle.bmc.core.model.Instance;
import com.oracle.bmc.core.model.InstanceConsoleConnection;
import com.oracle.bmc.core.requests.CreateInstanceConsoleConnectionRequest;
import com.oracle.bmc.core.requests.DeleteInstanceConsoleConnectionRequest;
import com.oracle.bmc.core.requests.GetInstanceConsoleConnectionRequest;
import com.oracle.bmc.core.requests.GetInstanceRequest;
import com.oracle.bmc.core.requests.ListInstanceConsoleConnectionsRequest;
import com.oracle.bmc.core.responses.CreateInstanceConsoleConnectionResponse;
import com.oracle.bmc.core.responses.GetInstanceConsoleConnectionResponse;
import com.oracle.bmc.core.responses.ListInstanceConsoleConnectionsResponse;
import com.oracle.bmc.model.BmcException;
import lombok.extern.slf4j.Slf4j;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.NoSuchAlgorithmException;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.SecureRandom;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.RSAKeyGenParameterSpec;
import java.util.ArrayList;
import java.util.Base64;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import com.doubledimple.ociserver.config.ProxyContext;

/**
 * Oracle Cloud Instance Console Connection 工具类
 * 用于管理实例控制台连接
 *
 * @author doubleDimple
 * @date 2025-05-24
 */
@Slf4j
public class OciConsoleUtils {

    /**
     * SSH密钥对信息
     */
    public static class SshKeyPair {
        private final String publicKey;
        private final String privateKey;
        private final String publicKeyOpenSSH;

        public SshKeyPair(String publicKey, String privateKey, String publicKeyOpenSSH) {
            this.publicKey = publicKey;
            this.privateKey = privateKey;
            this.publicKeyOpenSSH = publicKeyOpenSSH;
        }

        public String getPublicKey() { return publicKey; }
        public String getPrivateKey() { return privateKey; }
        public String getPublicKeyOpenSSH() { return publicKeyOpenSSH; }
    }

    /**
     * 控制台连接结果
     */
    public static class ConsoleConnectionResult {
        private final String connectionId;
        private final String connectionString;
        private final String vncConnectionString;
        private final SshKeyPair keyPair;
        private final boolean keyGenerated;

        public ConsoleConnectionResult(String connectionId, String connectionString,
                                       String vncConnectionString, SshKeyPair keyPair, boolean keyGenerated) {
            this.connectionId = connectionId;
            this.connectionString = connectionString;
            this.vncConnectionString = vncConnectionString;
            this.keyPair = keyPair;
            this.keyGenerated = keyGenerated;
        }

        public String getConnectionId() { return connectionId; }
        public String getConnectionString() { return connectionString; }
        public String getVncConnectionString() { return vncConnectionString; }
        public SshKeyPair getKeyPair() { return keyPair; }
        public boolean isKeyGenerated() { return keyGenerated; }
    }

    /**
     * 生成SSH密钥对
     *
     * @return SSH密钥对信息
     * @throws Exception 如果生成密钥失败
     */
    public static SshKeyPair generateSshKeyPair() throws Exception {
        try {
            // 生成RSA密钥对
            KeyPairGenerator keyPairGenerator = KeyPairGenerator.getInstance("RSA");
            keyPairGenerator.initialize(new RSAKeyGenParameterSpec(2048, RSAKeyGenParameterSpec.F4), new SecureRandom());
            KeyPair keyPair = keyPairGenerator.generateKeyPair();


            PublicKey publicKey = keyPair.getPublic();
            PrivateKey privateKey = keyPair.getPrivate();

            // 转换为PEM格式的公钥（用于OCI API）
            String publicKeyPem = convertPublicKeyToPem(publicKey);

            // 转换为OpenSSH格式的公钥（用于SSH客户端）
            String publicKeyOpenSSH = convertPublicKeyToOpenSSH((RSAPublicKey) publicKey);

            // 转换为PEM格式的私钥
            String privateKeyPem = convertPrivateKeyToPem(privateKey);

            log.info("成功生成SSH密钥对");
            return new SshKeyPair(publicKeyPem, privateKeyPem, publicKeyOpenSSH);

        } catch (NoSuchAlgorithmException e) {
            throw new Exception("RSA算法不可用", e);
        } catch (Exception e) {
            throw new Exception("生成SSH密钥对失败", e);
        }
    }

    /**
     * 保存SSH密钥对到文件
     *
     * @param keyPair SSH密钥对
     * @param keyName 密钥文件名（不含扩展名）
     * @param saveDirectory 保存目录
     * @return 包含文件路径的Map
     * @throws IOException 如果保存文件失败
     */
    public static Map<String, String> saveSshKeyPairToFiles(SshKeyPair keyPair, String keyName, String saveDirectory) throws IOException {
        Map<String, String> filePaths = new HashMap<>();

        // 确保目录存在
        File directory = new File(saveDirectory);
        if (!directory.exists()) {
            directory.mkdirs();
        }

        // 保存私钥
        String privateKeyPath = saveDirectory + File.separator + keyName;
        try (FileWriter writer = new FileWriter(privateKeyPath)) {
            writer.write(keyPair.getPrivateKey());
        }
        filePaths.put("privateKey", privateKeyPath);

        // 保存公钥（OpenSSH格式）
        String publicKeyPath = saveDirectory + File.separator + keyName + ".pub";
        try (FileWriter writer = new FileWriter(publicKeyPath)) {
            writer.write(keyPair.getPublicKeyOpenSSH());
        }
        filePaths.put("publicKey", publicKeyPath);

        // 设置私钥文件权限（仅所有者可读）
        File privateKeyFile = new File(privateKeyPath);
        privateKeyFile.setReadable(false, false);
        privateKeyFile.setReadable(true, true);
        privateKeyFile.setWritable(false, false);
        privateKeyFile.setWritable(true, true);
        privateKeyFile.setExecutable(false);

        log.info("SSH密钥对已保存到: 私钥={}, 公钥={}", privateKeyPath, publicKeyPath);
        return filePaths;
    }

    /**
     * 创建控制台连接（自动生成密钥）- 修复公钥格式问题
     * 如果没有提供公钥，会自动生成SSH密钥对
     *
     * @param tenant 租户信息
     * @param instanceId 实例ID
     * @param displayName 连接显示名称（可选）
     * @return 控制台连接结果，包含连接信息和密钥（如果生成了的话）
     */
    public static ConsoleConnectionResult createConsoleConnectionWithAutoKey(Tenant tenant, String instanceId, String displayName) {
        try {
            // 生成SSH密钥对
            SshKeyPair keyPair = generateSshKeyPair();

            log.info("生成的密钥信息:");
            log.info("PEM公钥: {}", keyPair.getPublicKey().substring(0, 50) + "...");
            log.info("OpenSSH公钥: {}", keyPair.getPublicKeyOpenSSH().substring(0, 50) + "...");

            // 🔧 关键修复: 使用OpenSSH格式的公钥，不是PEM格式
            // Oracle Cloud Console Connection API 需要 OpenSSH 格式的公钥
            String connectionId = createConsoleConnection(tenant, instanceId, keyPair.getPublicKeyOpenSSH(), displayName);
            if (connectionId == null) {
                log.error("创建控制台连接失败");
                return null;
            }

            log.info("控制台连接创建成功，ID: {}", connectionId);

            // 等待连接变为活跃状态并获取连接字符串
            String connectionString = waitForConnectionAndGetDetails(tenant, connectionId, "connection");
            String vncConnectionString = waitForConnectionAndGetDetails(tenant, connectionId, "vnc");

            return new ConsoleConnectionResult(connectionId, connectionString, vncConnectionString, keyPair, true);

        } catch (Exception e) {
            log.error("创建控制台连接（自动生成密钥）失败: {}", e.getMessage(), e);
            return null;
        }
    }


    /**
     * 创建实例控制台连接 - 增强调试版本
     *
     * @param tenant 租户信息
     * @param instanceId 实例ID
     * @param publicKey SSH公钥内容（OpenSSH格式）
     * @param displayName 连接显示名称（可选）
     * @return 控制台连接ID，失败返回null
     */
    public static String createConsoleConnection(Tenant tenant, String instanceId, String publicKey, String displayName) {
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);

        log.info("🔑 开始创建控制台连接:");
        log.info("实例ID: {}", instanceId);
        log.info("显示名称: {}", displayName);
        log.info("公钥格式检查:");
        log.info("  - 是否为PEM格式: {}", publicKey.startsWith("-----BEGIN"));
        log.info("  - 是否为OpenSSH格式: {}", publicKey.startsWith("ssh-rsa"));
        log.info("  - 公钥长度: {}", publicKey.length());
        log.info("  - 公钥前100字符: {}", publicKey.substring(0, Math.min(100, publicKey.length())));

        try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {

            // 1. 验证实例是否存在
            Instance instance = getInstanceIfExists(computeClient, instanceId);
            if (instance == null) {
                log.error("❌ 实例 {} 不存在或无法访问", instanceId);
                return null;
            }
            log.info("✅ 实例验证成功: {}", instance.getDisplayName());

            // 2. 检查是否已存在有效的控制台连接
            String existingConnectionId = findExistingActiveConnection(computeClient, instanceId, instance.getCompartmentId());
            if (existingConnectionId != null) {
                //log.info("♻️ 实例 {} 已存在有效的控制台连接: {}", instanceId, existingConnectionId);
                //执行删除连接操作
                deleteConsoleConnection(tenant, existingConnectionId);
            }

            // 3. 验证公钥格式
            if (!isValidOpenSSHPublicKey(publicKey)) {
                log.error("❌ 公钥格式无效！期望OpenSSH格式 (ssh-rsa ...)，实际格式: {}",
                        publicKey.startsWith("-----BEGIN") ? "PEM" : "未知");
                return null;
            }

            // 4. 创建控制台连接
            CreateInstanceConsoleConnectionDetails connectionDetails =
                    CreateInstanceConsoleConnectionDetails.builder()
                            .instanceId(instanceId)
                            .publicKey(publicKey)  // 确保是OpenSSH格式
                            .build();

            CreateInstanceConsoleConnectionRequest request =
                    CreateInstanceConsoleConnectionRequest.builder()
                            .createInstanceConsoleConnectionDetails(connectionDetails)
                            .build();

            log.info("📡 发送创建控制台连接请求...");
            CreateInstanceConsoleConnectionResponse response = computeClient.createInstanceConsoleConnection(request);
            String connectionId = response.getInstanceConsoleConnection().getId();

            log.info("✅ 成功创建控制台连接");
            log.info("连接ID: {}", connectionId);
            log.info("初始状态: {}", response.getInstanceConsoleConnection().getLifecycleState());
            log.info("连接字符串: {}", response.getInstanceConsoleConnection().getConnectionString());

            return connectionId;

        } catch (BmcException e) {
            log.error("❌ 创建控制台连接失败 - Oracle Cloud API 错误:");
            log.error("状态码: {}", e.getStatusCode());
            log.error("服务代码: {}", e.getServiceCode());
            log.error("错误消息: {}", e.getMessage());
            log.error("请求ID: {}", e.getOpcRequestId());

            // 针对公钥格式错误给出具体建议
            if (e.getStatusCode() == 400 && e.getMessage().contains("Invalid ssh public key")) {
                log.error("🔧 公钥格式问题诊断:");
                log.error("当前公钥格式: {}", publicKey.startsWith("-----BEGIN") ? "PEM (错误)" :
                        publicKey.startsWith("ssh-rsa") ? "OpenSSH (正确)" : "未知");
                log.error("Oracle Cloud 需要 OpenSSH 格式的公钥");
                log.error("正确格式示例: ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAB...");

                if (publicKey.startsWith("-----BEGIN")) {
                    log.error("❌ 检测到PEM格式公钥！请改用OpenSSH格式");
                }
            }

            return null;
        } catch (Exception e) {
            log.error("❌ 创建控制台连接时出现异常: {}", e.getMessage(), e);
            return null;
        }
    }

    /**
     * 验证是否为有效的OpenSSH公钥格式
     */
    private static boolean isValidOpenSSHPublicKey(String publicKey) {
        if (publicKey == null || publicKey.trim().isEmpty()) {
            return false;
        }

        String trimmedKey = publicKey.trim();

        // 检查是否以支持的密钥类型开始
        String[] supportedTypes = {"ssh-rsa", "ssh-dss", "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521", "ssh-ed25519"};

        for (String type : supportedTypes) {
            if (trimmedKey.startsWith(type + " ")) {
                // 检查基本结构: type + space + base64_key + optional_comment
                String[] parts = trimmedKey.split("\\s+");
                if (parts.length >= 2 && parts[1].matches("[A-Za-z0-9+/]+=*")) {
                    log.info("✅ 检测到有效的OpenSSH {}公钥", type);
                    return true;
                }
            }
        }

        log.warn("❌ 无效的OpenSSH公钥格式");
        return false;
    }


    /**
     * 获取控制台连接详细信息
     *
     * @param tenant 租户信息
     * @param connectionId 控制台连接ID
     * @return 控制台连接信息，失败返回null
     */
    public static InstanceConsoleConnection getConsoleConnectionDetails(Tenant tenant, String connectionId) {
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);

        try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {

            GetInstanceConsoleConnectionRequest request =
                    GetInstanceConsoleConnectionRequest.builder()
                            .instanceConsoleConnectionId(connectionId)
                            .build();

            GetInstanceConsoleConnectionResponse response = computeClient.getInstanceConsoleConnection(request);
            InstanceConsoleConnection connection = response.getInstanceConsoleConnection();

            log.info("成功获取控制台连接详情，ID: {}, 状态: {}", connectionId, connection.getLifecycleState());
            return connection;

        } catch (BmcException e) {
            if (e.getStatusCode() == 404) {
                log.warn("控制台连接 {} 不存在", connectionId);
            } else {
                log.error("获取控制台连接详情失败，状态码: {}, 错误: {}", e.getStatusCode(), e.getMessage(), e);
            }
            return null;
        } catch (Exception e) {
            log.error("获取控制台连接详情时出现异常: {}", e.getMessage(), e);
            return null;
        }
    }

    /**
     * 获取控制台连接字符串（用于SSH连接）
     *
     * @param tenant 租户信息
     * @param connectionId 控制台连接ID
     * @return 连接字符串，失败返回null
     */
    public static String getConsoleConnectionString(Tenant tenant, String connectionId) {
        InstanceConsoleConnection connection = getConsoleConnectionDetails(tenant, connectionId);
        if (connection != null && connection.getLifecycleState() == InstanceConsoleConnection.LifecycleState.Active) {
            return connection.getConnectionString();
        }
        return null;
    }

    /**
     * 获取VNC连接字符串（用于图形界面访问）
     *
     * @param tenant 租户信息
     * @param connectionId 控制台连接ID
     * @return VNC连接字符串，失败返回null
     */
    public static String getVncConnectionString(Tenant tenant, String connectionId) {
        InstanceConsoleConnection connection = getConsoleConnectionDetails(tenant, connectionId);
        if (connection != null && connection.getLifecycleState() == InstanceConsoleConnection.LifecycleState.Active) {
            return connection.getVncConnectionString();
        }
        return null;
    }

    /**
     * 列出实例的所有控制台连接
     *
     * @param tenant 租户信息
     * @param instanceId 实例ID
     * @return 控制台连接列表，失败返回空列表
     */
    public static List<InstanceConsoleConnection> listConsoleConnections(Tenant tenant, String instanceId) {
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);

        try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {

            // 获取实例信息以获取compartmentId
            Instance instance = getInstanceIfExists(computeClient, instanceId);
            if (instance == null) {
                log.error("实例 {} 不存在或无法访问", instanceId);
                return new ArrayList<>();
            }

            ListInstanceConsoleConnectionsRequest request =
                    ListInstanceConsoleConnectionsRequest.builder()
                            .compartmentId(instance.getCompartmentId())
                            .instanceId(instanceId)
                            .build();

            ListInstanceConsoleConnectionsResponse response = computeClient.listInstanceConsoleConnections(request);
            List<InstanceConsoleConnection> connections = response.getItems();

            log.info("实例 {} 共有 {} 个控制台连接", instanceId, connections.size());
            return connections;

        } catch (Exception e) {
            log.error("列出控制台连接时出现异常: {}", e.getMessage(), e);
            return new ArrayList<>();
        }
    }

    /**
     * 删除控制台连接
     *
     * @param tenant 租户信息
     * @param connectionId 控制台连接ID
     * @return 是否成功删除
     */
    public static boolean deleteConsoleConnection(Tenant tenant, String connectionId) {
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);

        try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {

            // 检查连接是否存在
            InstanceConsoleConnection connection = getConsoleConnectionDetails(tenant, connectionId);
            if (connection == null) {
                log.warn("控制台连接 {} 不存在，无需删除", connectionId);
                return true;
            }

            if (connection.getLifecycleState() == InstanceConsoleConnection.LifecycleState.Deleted) {
                log.info("控制台连接 {} 已经被删除", connectionId);
                return true;
            }

            DeleteInstanceConsoleConnectionRequest request =
                    DeleteInstanceConsoleConnectionRequest.builder()
                            .instanceConsoleConnectionId(connectionId)
                            .build();

            computeClient.deleteInstanceConsoleConnection(request);

            // 等待删除完成
            boolean deleted = waitForConnectionDeletion(tenant, connectionId);
            if (deleted) {
                log.info("成功删除控制台连接: {}", connectionId);
            } else {
                log.warn("控制台连接删除可能未完成，ID: {}", connectionId);
            }

            return deleted;

        } catch (BmcException e) {
            if (e.getStatusCode() == 404) {
                log.info("控制台连接 {} 不存在，认为删除成功", connectionId);
                return true;
            } else {
                log.error("删除控制台连接失败，状态码: {}, 错误: {}", e.getStatusCode(), e.getMessage(), e);
                return false;
            }
        } catch (Exception e) {
            log.error("删除控制台连接时出现异常: {}", e.getMessage(), e);
            return false;
        }
    }

    /**
     * 清理实例的所有控制台连接
     *
     * @param tenant 租户信息
     * @param instanceId 实例ID
     * @return 成功清理的连接数量
     */
    public static int cleanupConsoleConnections(Tenant tenant, String instanceId) {
        List<InstanceConsoleConnection> connections = listConsoleConnections(tenant, instanceId);
        int cleanedCount = 0;

        for (InstanceConsoleConnection connection : connections) {
            if (connection.getLifecycleState() != InstanceConsoleConnection.LifecycleState.Deleted) {
                if (deleteConsoleConnection(tenant, connection.getId())) {
                    cleanedCount++;
                }
            }
        }

        log.info("为实例 {} 清理了 {} 个控制台连接", instanceId, cleanedCount);
        return cleanedCount;
    }

    /**
     * 获取或创建控制台连接（支持自动生成密钥）- 修复版本
     */
    public static ConsoleConnectionResult getOrCreateConsoleConnectionWithAutoKey(Tenant tenant, String instanceId,
                                                                                  String publicKey, String displayName) {
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);

        try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {

            Instance instance = getInstanceIfExists(computeClient, instanceId);
            if (instance == null) {
                return null;
            }

            // 首先尝试找到现有的活跃连接
            String existingConnectionId = findExistingActiveConnection(computeClient, instanceId, instance.getCompartmentId());
            if (existingConnectionId != null) {
                log.info("♻️ 使用现有控制台连接: {}", existingConnectionId);

                // 获取现有连接的详细信息
                String connectionString = getConsoleConnectionString(tenant, existingConnectionId);
                String vncConnectionString = getVncConnectionString(tenant, existingConnectionId);

                return new ConsoleConnectionResult(existingConnectionId, connectionString, vncConnectionString, null, false);
            }

            // 如果没有提供公钥，自动生成
            if (publicKey == null || publicKey.trim().isEmpty()) {
                log.info("🔑 未提供公钥，自动生成SSH密钥对");
                return createConsoleConnectionWithAutoKey(tenant, instanceId, displayName);
            } else {
                // 🔧 验证提供的公钥格式
                if (!isValidOpenSSHPublicKey(publicKey)) {
                    log.error("❌ 提供的公钥格式无效，需要OpenSSH格式");
                    return null;
                }

                // 使用提供的公钥创建连接
                String connectionId = createConsoleConnection(tenant, instanceId, publicKey, displayName);
                if (connectionId == null) {
                    return null;
                }

                String connectionString = waitForConnectionAndGetDetails(tenant, connectionId, "connection");
                String vncConnectionString = waitForConnectionAndGetDetails(tenant, connectionId, "vnc");

                return new ConsoleConnectionResult(connectionId, connectionString, vncConnectionString, null, false);
            }

        } catch (Exception e) {
            log.error("❌ 获取或创建控制台连接时出现异常: {}", e.getMessage(), e);
            return null;
        }
    }

    /**
     * 调试用：打印密钥格式信息
     */
    public static void debugKeyFormats(SshKeyPair keyPair) {
        log.info("🔍 SSH密钥格式调试信息:");
        log.info("=================================");

        String pemPublicKey = keyPair.getPublicKey();
        String opensshPublicKey = keyPair.getPublicKeyOpenSSH();
        String privateKey = keyPair.getPrivateKey();

        log.info("PEM公钥:");
        log.info("  长度: {}", pemPublicKey.length());
        log.info("  开头: {}", pemPublicKey.substring(0, Math.min(50, pemPublicKey.length())));
        log.info("  结尾: {}", pemPublicKey.substring(Math.max(0, pemPublicKey.length() - 50)));
        log.info("  格式正确: {}", pemPublicKey.startsWith("-----BEGIN PUBLIC KEY-----") && pemPublicKey.endsWith("-----END PUBLIC KEY-----"));

        log.info("OpenSSH公钥:");
        log.info("  长度: {}", opensshPublicKey.length());
        log.info("  内容: {}", opensshPublicKey);
        log.info("  格式正确: {}", isValidOpenSSHPublicKey(opensshPublicKey));

        log.info("私钥:");
        log.info("  长度: {}", privateKey.length());
        log.info("  开头: {}", privateKey.substring(0, Math.min(50, privateKey.length())));
        log.info("  格式正确: {}", privateKey.startsWith("-----BEGIN PRIVATE KEY-----") && privateKey.endsWith("-----END PRIVATE KEY-----"));

        log.info("=================================");
        log.info("🎯 Oracle Console Connection 应使用: OpenSSH公钥格式");
        log.info("🎯 SSH连接应使用: 私钥 (PEM格式)");
    }


    /**
     * 一键创建控制台连接并保存密钥到文件
     *
     * @param tenant 租户信息
     * @param instanceId 实例ID
     * @param keyName 密钥文件名（不含扩展名）
     * @param saveDirectory 保存目录
     * @param displayName 连接显示名称（可选）
     * @return 包含连接信息和文件路径的结果Map
     */
    public static Map<String, Object> createConsoleConnectionAndSaveKey(Tenant tenant, String instanceId,
                                                                        String keyName, String saveDirectory, String displayName) {
        Map<String, Object> result = new HashMap<>();
        result.put("success", false);

        try {
            // 创建控制台连接（自动生成密钥）
            ConsoleConnectionResult connectionResult = createConsoleConnectionWithAutoKey(tenant, instanceId, displayName);
            if (connectionResult == null) {
                result.put("message", "创建控制台连接失败");
                return result;
            }

            // 保存密钥到文件
            if (connectionResult.isKeyGenerated() && connectionResult.getKeyPair() != null) {
                Map<String, String> filePaths = saveSshKeyPairToFiles(
                        connectionResult.getKeyPair(),
                        keyName != null ? keyName : "console-key-" + System.currentTimeMillis(),
                        saveDirectory
                );
                result.put("keyFiles", filePaths);
            }

            result.put("success", true);
            result.put("connectionId", connectionResult.getConnectionId());
            result.put("connectionString", connectionResult.getConnectionString());
            result.put("vncConnectionString", connectionResult.getVncConnectionString());
            result.put("keyGenerated", connectionResult.isKeyGenerated());

            if (connectionResult.getKeyPair() != null) {
                result.put("publicKeyOpenSSH", connectionResult.getKeyPair().getPublicKeyOpenSSH());
            }

            log.info("成功创建控制台连接并保存密钥，连接ID: {}", connectionResult.getConnectionId());
            return result;

        } catch (Exception e) {
            log.error("创建控制台连接并保存密钥失败: {}", e.getMessage(), e);
            result.put("message", "操作失败: " + e.getMessage());
            return result;
        }
    }

    // ==================== 私有辅助方法 ====================

    /**
     * 将公钥转换为PEM格式（用于OCI API）
     */
    private static String convertPublicKeyToPem(PublicKey publicKey) throws Exception {
        byte[] encoded = publicKey.getEncoded();
        String base64 = Base64.getEncoder().encodeToString(encoded);

        StringBuilder pem = new StringBuilder();
        pem.append("-----BEGIN PUBLIC KEY-----\n");

        // 每64个字符换行
        for (int i = 0; i < base64.length(); i += 64) {
            int end = Math.min(i + 64, base64.length());
            pem.append(base64, i, end).append("\n");
        }

        pem.append("-----END PUBLIC KEY-----");
        return pem.toString();
    }

    /**
     * 将公钥转换为OpenSSH格式（用于SSH客户端）
     */
    private static String convertPublicKeyToOpenSSH(RSAPublicKey publicKey) throws Exception {
        ByteArrayOutputStream baos = new ByteArrayOutputStream();

        // SSH-RSA格式: "ssh-rsa" + 公钥数据
        byte[] algorithm = "ssh-rsa".getBytes();
        writeBytes(baos, algorithm);

        // 公钥指数
        byte[] exponent = publicKey.getPublicExponent().toByteArray();
        writeBytes(baos, exponent);

        // 公钥模数
        byte[] modulus = publicKey.getModulus().toByteArray();
        writeBytes(baos, modulus);

        String base64 = Base64.getEncoder().encodeToString(baos.toByteArray());
        return "ssh-rsa " + base64 + " console-connection@oracle";
    }

    /**
     * 将私钥转换为PEM格式
     */
    private static String convertPrivateKeyToPem(PrivateKey privateKey) throws Exception {
        byte[] encoded = privateKey.getEncoded();
        String base64 = Base64.getEncoder().encodeToString(encoded);

        StringBuilder pem = new StringBuilder();
        pem.append("-----BEGIN PRIVATE KEY-----\n");

        // 每64个字符换行
        for (int i = 0; i < base64.length(); i += 64) {
            int end = Math.min(i + 64, base64.length());
            pem.append(base64, i, end).append("\n");
        }

        pem.append("-----END PRIVATE KEY-----");
        return pem.toString();
    }

    /**
     * 写入字节数组到输出流（SSH格式）
     */
    private static void writeBytes(ByteArrayOutputStream baos, byte[] bytes) throws IOException {
        // 写入长度（4字节，大端序）
        int length = bytes.length;
        baos.write((length >>> 24) & 0xFF);
        baos.write((length >>> 16) & 0xFF);
        baos.write((length >>> 8) & 0xFF);
        baos.write(length & 0xFF);

        // 写入数据
        baos.write(bytes);
    }

    /**
     * 等待控制台连接变为活跃状态并获取连接详情
     */
    private static String waitForConnectionAndGetDetails(Tenant tenant, String connectionId, String type) {
        final int MAX_ATTEMPTS = 15;
        final int WAIT_SECONDS = 5;

        for (int attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
            InstanceConsoleConnection connection = getConsoleConnectionDetails(tenant, connectionId);

            if (connection != null && connection.getLifecycleState() == InstanceConsoleConnection.LifecycleState.Active) {
                if ("connection".equals(type)) {
                    return connection.getConnectionString();
                } else if ("vnc".equals(type)) {
                    return connection.getVncConnectionString();
                }
            }

            log.debug("等待控制台连接变为活跃状态... 尝试次数: {}/{}", attempt + 1, MAX_ATTEMPTS);

            try {
                Thread.sleep(WAIT_SECONDS * 1000L);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                log.warn("等待控制台连接过程被中断");
                return null;
            }
        }

        log.warn("等待控制台连接超时");
        return null;
    }

    /**
     * 检查实例是否存在
     */
    private static Instance getInstanceIfExists(ComputeClient computeClient, String instanceId) {
        try {
            GetInstanceRequest request = GetInstanceRequest.builder()
                    .instanceId(instanceId)
                    .build();
            return computeClient.getInstance(request).getInstance();
        } catch (BmcException e) {
            if (e.getStatusCode() == 404) {
                log.warn("实例 {} 不存在", instanceId);
            } else {
                log.error("获取实例信息失败: {}", e.getMessage());
            }
            return null;
        }
    }

    /**
     * 查找现有的活跃控制台连接
     */
    private static String findExistingActiveConnection(ComputeClient computeClient, String instanceId, String compartmentId) {
        try {
            ListInstanceConsoleConnectionsRequest request =
                    ListInstanceConsoleConnectionsRequest.builder()
                            .compartmentId(compartmentId)
                            .instanceId(instanceId)
                            .build();

            ListInstanceConsoleConnectionsResponse response = computeClient.listInstanceConsoleConnections(request);

            // 查找活跃状态的连接
            Optional<InstanceConsoleConnection> activeConnection = response.getItems().stream()
                    .filter(conn -> conn.getLifecycleState() == InstanceConsoleConnection.LifecycleState.Active)
                    .findFirst();

            return activeConnection.map(InstanceConsoleConnection::getId).orElse(null);

        } catch (Exception e) {
            log.warn("查找现有控制台连接时出错: {}", e.getMessage());
            return null;
        }
    }

    /**
     * 等待控制台连接删除完成
     */
    private static boolean waitForConnectionDeletion(Tenant tenant, String connectionId) {
        final int MAX_ATTEMPTS = 10;
        final int WAIT_SECONDS = 3;

        for (int attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
            InstanceConsoleConnection connection = getConsoleConnectionDetails(tenant, connectionId);

            if (connection == null || connection.getLifecycleState() == InstanceConsoleConnection.LifecycleState.Deleted) {
                return true;
            }

            log.debug("等待控制台连接删除... 当前状态: {}, 尝试次数: {}/{}",
                    connection.getLifecycleState(), attempt + 1, MAX_ATTEMPTS);

            try {
                Thread.sleep(WAIT_SECONDS * 1000L);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                log.warn("等待控制台连接删除过程被中断");
                return false;
            }
        }

        return false;
    }

    /**
     * 验证控制台连接是否有效
     */
    public static boolean validateConsoleConnection(Tenant tenant, String connectionId) {
        try {
            SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);

            try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
                GetInstanceConsoleConnectionRequest request = GetInstanceConsoleConnectionRequest.builder()
                        .instanceConsoleConnectionId(connectionId)
                        .build();

                GetInstanceConsoleConnectionResponse response = computeClient.getInstanceConsoleConnection(request);

                InstanceConsoleConnection connection = response.getInstanceConsoleConnection();
                return connection.getLifecycleState() == InstanceConsoleConnection.LifecycleState.Active;

            }
        } catch (Exception e) {
            log.error("验证控制台连接失败: {}", connectionId, e);
            return false;
        }
    }
}

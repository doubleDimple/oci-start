package com.doubledimple.ociserver.utils.oracle;


import com.doubledimple.dao.entity.InstanceCloudNetWork;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.core.ComputeClient;
import com.oracle.bmc.core.VirtualNetworkClient;
import com.oracle.bmc.core.model.AddNetworkSecurityGroupSecurityRulesDetails;
import com.oracle.bmc.core.model.AddSecurityRuleDetails;
import com.oracle.bmc.core.model.CreateDhcpDetails;
import com.oracle.bmc.core.model.CreateInstanceConsoleConnectionDetails;
import com.oracle.bmc.core.model.CreateInternetGatewayDetails;
import com.oracle.bmc.core.model.CreateNetworkSecurityGroupDetails;
import com.oracle.bmc.core.model.CreateRouteTableDetails;
import com.oracle.bmc.core.model.CreateSecurityListDetails;
import com.oracle.bmc.core.model.CreateSubnetDetails;
import com.oracle.bmc.core.model.CreateVcnDetails;
import com.oracle.bmc.core.model.DhcpDnsOption;
import com.oracle.bmc.core.model.DhcpOptions;
import com.oracle.bmc.core.model.EgressSecurityRule;
import com.oracle.bmc.core.model.IngressSecurityRule;
import com.oracle.bmc.core.model.InstanceConsoleConnection;
import com.oracle.bmc.core.model.InternetGateway;
import com.oracle.bmc.core.model.NetworkSecurityGroup;
import com.oracle.bmc.core.model.PortRange;
import com.oracle.bmc.core.model.RouteRule;
import com.oracle.bmc.core.model.RouteTable;
import com.oracle.bmc.core.model.SecurityList;
import com.oracle.bmc.core.model.SecurityRule;
import com.oracle.bmc.core.model.Subnet;
import com.oracle.bmc.core.model.TcpOptions;
import com.oracle.bmc.core.model.Vcn;
import com.oracle.bmc.core.requests.AddNetworkSecurityGroupSecurityRulesRequest;
import com.oracle.bmc.core.requests.CreateDhcpOptionsRequest;
import com.oracle.bmc.core.requests.CreateInstanceConsoleConnectionRequest;
import com.oracle.bmc.core.requests.CreateInternetGatewayRequest;
import com.oracle.bmc.core.requests.CreateNetworkSecurityGroupRequest;
import com.oracle.bmc.core.requests.CreateRouteTableRequest;
import com.oracle.bmc.core.requests.CreateSecurityListRequest;
import com.oracle.bmc.core.requests.CreateSubnetRequest;
import com.oracle.bmc.core.requests.CreateVcnRequest;
import com.oracle.bmc.core.requests.GetInstanceConsoleConnectionRequest;
import com.oracle.bmc.core.requests.GetInternetGatewayRequest;
import com.oracle.bmc.core.requests.GetNetworkSecurityGroupRequest;
import com.oracle.bmc.core.requests.GetRouteTableRequest;
import com.oracle.bmc.core.requests.GetSecurityListRequest;
import com.oracle.bmc.core.requests.GetSubnetRequest;
import com.oracle.bmc.core.requests.GetVcnRequest;
import com.oracle.bmc.core.requests.ListDhcpOptionsRequest;
import com.oracle.bmc.core.requests.ListInternetGatewaysRequest;
import com.oracle.bmc.core.requests.ListNetworkSecurityGroupSecurityRulesRequest;
import com.oracle.bmc.core.requests.ListNetworkSecurityGroupsRequest;
import com.oracle.bmc.core.requests.ListRouteTablesRequest;
import com.oracle.bmc.core.requests.ListSecurityListsRequest;
import com.oracle.bmc.core.requests.ListSubnetsRequest;
import com.oracle.bmc.core.requests.ListVcnsRequest;
import com.oracle.bmc.core.responses.CreateInstanceConsoleConnectionResponse;
import com.oracle.bmc.core.responses.CreateInternetGatewayResponse;
import com.oracle.bmc.core.responses.CreateNetworkSecurityGroupResponse;
import com.oracle.bmc.core.responses.CreateRouteTableResponse;
import com.oracle.bmc.core.responses.CreateSecurityListResponse;
import com.oracle.bmc.core.responses.CreateSubnetResponse;
import com.oracle.bmc.core.responses.CreateVcnResponse;
import com.oracle.bmc.core.responses.GetInstanceConsoleConnectionResponse;
import com.oracle.bmc.core.responses.GetInternetGatewayResponse;
import com.oracle.bmc.core.responses.GetNetworkSecurityGroupResponse;
import com.oracle.bmc.core.responses.GetRouteTableResponse;
import com.oracle.bmc.core.responses.GetSecurityListResponse;
import com.oracle.bmc.core.responses.GetSubnetResponse;
import com.oracle.bmc.core.responses.GetVcnResponse;
import com.oracle.bmc.core.responses.ListInternetGatewaysResponse;
import com.oracle.bmc.core.responses.ListNetworkSecurityGroupSecurityRulesResponse;
import com.oracle.bmc.core.responses.ListNetworkSecurityGroupsResponse;
import com.oracle.bmc.core.responses.ListRouteTablesResponse;
import com.oracle.bmc.core.responses.ListSecurityListsResponse;
import com.oracle.bmc.core.responses.ListSubnetsResponse;
import com.oracle.bmc.core.responses.ListVcnsResponse;
import com.oracle.bmc.logging.LoggingManagementClient;
import lombok.extern.slf4j.Slf4j;

import java.io.BufferedReader;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.TimeUnit;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static com.doubledimple.ociserver.config.constant.SystemScriptShell.networkSecurityGroupName;
import static com.doubledimple.ociserver.config.constant.SystemScriptShell.vcnName;
import static com.doubledimple.ociserver.utils.oracle.OciUtils.getProvider;

/**
 * OCI CLI 工具类
 * 提供安装、配置和执行OCI CLI命令的功能
 */
@Slf4j
public class OciCliUtils {
    private static final String DEFAULT_INSTALL_DIR = "/opt/oracle-cli";
    private static final int DEFAULT_TIMEOUT = 300; // 5分钟超时

    /**
     * 重新生成实例的SSH密钥
     *
     * @param tenant     租户信息
     * @param instanceId 实例id
     * @return 操作是否成功
     */
    public static boolean regenerateSSHKeys(Tenant tenant, String instanceId, String compartmentId) {
        try {
            log.info("开始为实例" + instanceId + "重新生成SSH密钥");

            // 检查并安装OCI CLI
            checkAndInstallOciCli();
            final String region = RegionEnum.getRegionCode(tenant.getRegion());
            // 配置OCI CLI
            String profileName = "TENANT_"+region +"_"+ tenant.getTenantId();
            configureOciCli(tenant, profileName);

            // 执行Cloud Shell命令
            return regenerateSSHKeysViaInstanceAgent(tenant, instanceId,compartmentId);

        } catch (Exception e) {
            log.warn("SSH密钥重生成失败: " + e.getMessage());
            e.printStackTrace();
            return false;
        }
    }

    /**
     * 检查OCI CLI是否已安装，如果没有则安装
     */
    public static void checkAndInstallOciCli() throws IOException, InterruptedException {
        log.info("检查OCI CLI是否已安装");

        // 检查是否已安装
        if (isOciCliInstalled()) {
            log.info("OCI CLI已安装，无需重新安装");
            return;
        }

        // 根据操作系统安装OCI CLI
        String osName = System.getProperty("os.name").toLowerCase();

        if (osName.contains("linux")) {
            installOciCliOnLinux();
        } else if (osName.contains("windows")) {
            installOciCliOnWindows();
        } else if (osName.contains("mac")) {
            installOciCliOnMac();
        } else {
            throw new RuntimeException("不支持的操作系统: " + osName);
        }

        // 验证安装
        verifyOciCliInstallation();
    }

    /**
     * 检查OCI CLI是否已安装
     */
    private static boolean isOciCliInstalled() {
        // 获取可能的OCI CLI路径
        String ociPath = getOciExecutablePath();
        boolean isExistingPath = !ociPath.equals("oci");

        try {
            ProcessBuilder checkBuilder = new ProcessBuilder();
            if (isExistingPath) {
                checkBuilder.command(ociPath, "--version");
            } else {
                checkBuilder.command("oci", "--version");
            }
            checkBuilder.redirectErrorStream(true);

            Process checkProcess = checkBuilder.start();
            boolean completed = checkProcess.waitFor(10, TimeUnit.SECONDS);

            if (completed && checkProcess.exitValue() == 0) {
                BufferedReader reader = new BufferedReader(new InputStreamReader(checkProcess.getInputStream()));
                String version = reader.readLine();
                log.info("OCI CLI已安装，版本: " + version);
                return true;
            }
        } catch (Exception e) {
            // 命令不存在，需要安装
            log.info("OCI CLI未安装，将进行安装");
        }

        return false;
    }

    /**
     * 获取OCI CLI可执行文件的完整路径
     */
    private static String getOciExecutablePath() {
        String osName = System.getProperty("os.name").toLowerCase();
        String home = System.getProperty("user.home");

        // 可能的OCI CLI路径
        String[] possiblePaths = {
                home + "/bin/oci",                     // 默认安装路径
                home + "/opt/oracle-cli/bin/oci",      // 可选安装路径
                home + "/Library/Python/3.7/bin/oci",  // macOS路径
                home + "/Library/Python/3.8/bin/oci",  // macOS路径
                home + "/Library/Python/3.9/bin/oci",  // macOS路径
                home + "/Library/Python/3.10/bin/oci", // macOS路径
                home + "/Library/Python/3.11/bin/oci", // macOS路径
                "/usr/local/bin/oci",                  // 系统路径
                "/opt/oracle-cli/venv/bin/oci",        // 优化安装路径
                "/opt/oracle-cli/bin/oci"              // 系统可选路径
        };

        // 在Windows上添加.exe后缀
        if (osName.contains("windows")) {
            for (int i = 0; i < possiblePaths.length; i++) {
                possiblePaths[i] += ".exe";
            }
        }

        // 检查文件是否存在
        for (String path : possiblePaths) {
            if (Files.exists(Paths.get(path))) {
                log.info("找到OCI CLI可执行文件: " + path);
                return path;
            }
        }

        // 如果找不到，返回命令名称，依赖系统PATH
        return "oci";
    }

    /**
     * 在Linux上安装OCI CLI
     */
    private static void installOciCliOnLinux() throws IOException, InterruptedException {
        log.info("在Linux上安装OCI CLI");

        // 创建临时目录
        executeCommand("mkdir -p /tmp/oci-cli-install");

        try {
            // 1. 更新包索引
            executeCommand("apt-get update");

            // 2. 安装必要的依赖
            executeCommand("apt-get install -y python3-full python3-venv curl");

            // 3. 创建安装目录
            executeCommand("mkdir -p " + DEFAULT_INSTALL_DIR);

            // 4. 创建虚拟环境
            executeCommand("python3 -m venv " + DEFAULT_INSTALL_DIR + "/venv");

            // 5. 在虚拟环境中安装OCI CLI
            String activateCmd = "source " + DEFAULT_INSTALL_DIR + "/venv/bin/activate && " +
                    "pip install --upgrade pip && " +
                    "pip install oci-cli && " +
                    "deactivate";

            executeCommand("/bin/bash -c \"" + activateCmd + "\"");

            // 6. 创建符号链接
            executeCommand("ln -sf " + DEFAULT_INSTALL_DIR + "/venv/bin/oci /usr/local/bin/oci");

            log.info("OCI CLI安装完成");
        } catch (Exception e) {
            log.warn("安装OCI CLI失败: " + e.getMessage());
            throw e;
        }
    }

    /**
     * 在Windows上安装OCI CLI
     */
    private static void installOciCliOnWindows() throws IOException, InterruptedException {
        log.info("在Windows上安装OCI CLI");

        try {
            // 使用PowerShell创建目录和虚拟环境
            executePowershellCommand("New-Item -ItemType Directory -Force -Path '" + DEFAULT_INSTALL_DIR + "'");

            // 创建虚拟环境
            executePowershellCommand("python -m venv '" + DEFAULT_INSTALL_DIR + "\\venv'");

            // 在虚拟环境中安装OCI CLI
            String installCmd = "& '" + DEFAULT_INSTALL_DIR + "\\venv\\Scripts\\activate.ps1'; " +
                    "pip install --upgrade pip; " +
                    "pip install oci-cli; " +
                    "deactivate";

            executePowershellCommand(installCmd);

            log.info("OCI CLI安装完成");
        } catch (Exception e) {
            log.warn("安装OCI CLI失败: " + e.getMessage());
            throw e;
        }
    }

    /**
     * 在macOS上安装OCI CLI
     */
    private static void installOciCliOnMac() throws IOException, InterruptedException {
        log.info("在macOS上安装OCI CLI");

        try {
            // 创建临时目录
            executeCommand("mkdir -p /tmp/oci-cli-install");

            // 1. 创建安装目录
            executeCommand("mkdir -p " + DEFAULT_INSTALL_DIR);

            // 2. 创建虚拟环境
            executeCommand("python3 -m venv " + DEFAULT_INSTALL_DIR + "/venv");

            // 3. 在虚拟环境中安装OCI CLI
            String activateCmd = "source " + DEFAULT_INSTALL_DIR + "/venv/bin/activate && " +
                    "pip install --upgrade pip && " +
                    "pip install oci-cli && " +
                    "deactivate";

            executeCommand("/bin/bash -c \"" + activateCmd + "\"");

            // 4. 创建符号链接
            executeCommand("ln -sf " + DEFAULT_INSTALL_DIR + "/venv/bin/oci /usr/local/bin/oci");

            log.info("OCI CLI安装完成");
        } catch (Exception e) {
            log.warn("安装OCI CLI失败: " + e.getMessage());
            throw e;
        }
    }

    /**
     * 验证OCI CLI安装是否成功
     */
    private static void verifyOciCliInstallation() throws IOException, InterruptedException {
        log.info("验证OCI CLI安装");

        // 获取OCI CLI可执行文件路径
        String ociPath = getOciExecutablePath();

        ProcessBuilder verifyBuilder = new ProcessBuilder();

        // 使用完整路径或命令名
        if (ociPath.equals("oci")) {
            // 添加OCI CLI到PATH（如果需要）
            String path = System.getenv("PATH");
            String home = System.getProperty("user.home");
            String ociDirPath = home + "/bin";
            String newPath = path;

            if (!path.contains(ociDirPath)) {
                newPath = ociDirPath + ":" + path;
                log.info("添加OCI CLI到PATH: " + ociDirPath);
            }

            verifyBuilder.command("oci", "--version");
            verifyBuilder.environment().put("PATH", newPath);
        } else {
            verifyBuilder.command(ociPath, "--version");
        }

        verifyBuilder.redirectErrorStream(true);

        Process verifyProcess = verifyBuilder.start();
        boolean completed = verifyProcess.waitFor(10, TimeUnit.SECONDS);

        if (!completed || verifyProcess.exitValue() != 0) {
            BufferedReader errorReader = new BufferedReader(new InputStreamReader(verifyProcess.getInputStream()));
            StringBuilder errorOutput = new StringBuilder();
            String line;
            while ((line = errorReader.readLine()) != null) {
                errorOutput.append(line).append("\n");
            }
            log.warn("OCI CLI验证失败: " + errorOutput.toString());
            throw new RuntimeException("OCI CLI安装验证失败");
        }

        BufferedReader reader = new BufferedReader(new InputStreamReader(verifyProcess.getInputStream()));
        String version = reader.readLine();
        log.info("OCI CLI安装验证成功，版本: " + version);
    }

    /**
     * 执行OCI CLI命令
     */
    private static Process executeOciCommand(ProcessBuilder processBuilder, String profileName, String... command) throws IOException {
        // 获取OCI CLI可执行文件路径
        String ociPath = getOciExecutablePath();

        // 在macOS上设置Python路径环境变量
        String osName = System.getProperty("os.name").toLowerCase();
        if (osName.contains("mac")) {
            processBuilder.environment().put("PYTHONPATH", "");
        }

        // 添加OCI CLI到PATH（如果需要）
        String path = System.getenv("PATH");
        String home = System.getProperty("user.home");
        String ociDirPath = home + "/bin";
        String newPath = path;

        if (!path.contains(ociDirPath)) {
            newPath = ociDirPath + ":" + path;
        }
        processBuilder.environment().put("PATH", newPath);

        // 增加连接超时设置
        processBuilder.environment().put("OCI_CLI_CONNECT_TIMEOUT", "30");
        processBuilder.environment().put("OCI_CLI_RETRY_TOKEN_REFRESH_INTERVAL", "20");

        // 替换命令中的"oci"为完整路径（如果需要）
        String[] fullCommand;
        if (!ociPath.equals("oci") && command[0].equals("oci")) {
            fullCommand = new String[command.length];
            fullCommand[0] = ociPath;
            System.arraycopy(command, 1, fullCommand, 1, command.length - 1);
        } else {
            fullCommand = command;
        }

        processBuilder.command(fullCommand);
        processBuilder.redirectErrorStream(true);

        log.info("执行命令: " + String.join(" ", fullCommand));
        return processBuilder.start();
    }

    private static void configureOciCli(Tenant tenant, String profileName) throws IOException, InterruptedException {
        log.info("配置OCI CLI认证，profile: " + profileName);

        // 创建OCI配置目录
        String home = System.getProperty("user.home");
        String configDir = home + "/.oci";
        Files.createDirectories(Paths.get(configDir));
        String configPath = configDir + "/config";
        String keyFilePath = tenant.getKeyFile();
        String region = RegionEnum.getRegionCode(tenant.getRegion());
        // 读取现有配置
        StringBuilder configContent = new StringBuilder();
        boolean profileExists = false;

        if (Files.exists(Paths.get(configPath))) {
            List<String> lines = Files.readAllLines(Paths.get(configPath));

            // 检查并更新现有profile
            boolean inTargetProfile = false;
            boolean profileProcessed = false;

            for (int i = 0; i < lines.size(); i++) {
                String line = lines.get(i);

                // 检查是否是目标profile的开始
                if (line.trim().equals("[" + profileName + "]")) {
                    profileExists = true;
                    inTargetProfile = true;
                    profileProcessed = true;

                    // 添加profile头
                    configContent.append(line).append("\n");

                    // 添加更新后的配置
                    configContent.append("user=").append(tenant.getTenantId()).append("\n");
                    configContent.append("fingerprint=").append(tenant.getFingerprint()).append("\n");
                    configContent.append("tenancy=").append(tenant.getTenancy()).append("\n");
                    configContent.append("region=").append(region).append("\n");
                    configContent.append("key_file=").append(tenant.getKeyFile()).append("\n");

                    // 跳过原有的profile配置
                    while (i + 1 < lines.size() && !lines.get(i + 1).trim().startsWith("[")) {
                        i++;
                    }
                }
                // 检查是否是下一个profile的开始
                else if (line.trim().startsWith("[") && inTargetProfile) {
                    inTargetProfile = false;
                    configContent.append("\n").append(line).append("\n");
                }
                // 正常添加其他行
                else {
                    configContent.append(line).append("\n");
                }
            }

            // 如果profile不存在，添加到文件末尾
            if (!profileExists) {
                if (configContent.length() > 0 && configContent.charAt(configContent.length() - 1) != '\n') {
                    configContent.append("\n");
                }
                configContent.append("\n[").append(profileName).append("]\n");
                configContent.append("user=").append(tenant.getTenantId()).append("\n");
                configContent.append("fingerprint=").append(tenant.getFingerprint()).append("\n");
                configContent.append("tenancy=").append(tenant.getTenancy()).append("\n");
                configContent.append("region=").append(region).append("\n");
                configContent.append("key_file=").append(keyFilePath).append("\n");
            }
        } else {
            // 文件不存在，创建新文件
            configContent.append("[").append(profileName).append("]\n");
            configContent.append("user=").append(tenant.getTenantId()).append("\n");
            configContent.append("fingerprint=").append(tenant.getFingerprint()).append("\n");
            configContent.append("tenancy=").append(tenant.getTenancy()).append("\n");
            configContent.append("region=").append(region).append("\n");
            configContent.append("key_file=").append(keyFilePath).append("\n");
        }

        // 写入配置文件
        Files.write(Paths.get(configPath), configContent.toString().getBytes(StandardCharsets.UTF_8));

        // 设置配置文件权限（仅在类Unix系统上）
        String osName = System.getProperty("os.name").toLowerCase();
        if (!osName.contains("windows")) {
            ProcessBuilder chmodBuilder = new ProcessBuilder();
            chmodBuilder.command("chmod", "600", configPath);
            Process chmodProcess = chmodBuilder.start();
            chmodProcess.waitFor();
        }

        log.info("OCI CLI配置完成，配置文件路径: " + configPath);
        log.info(profileExists ? "已更新现有profile: " + profileName : "已添加新profile: " + profileName);

        // 验证配置
        verifyOciCliConfig(profileName);
    }

    /**
     * 验证OCI CLI配置是否正确
     */
    private static void verifyOciCliConfig(String profileName) throws IOException, InterruptedException {
        log.info("验证OCI CLI配置");

        ProcessBuilder verifyBuilder = new ProcessBuilder();

        // 尝试最多3次
        int maxRetries = 3;
        boolean success = false;
        StringBuilder finalOutput = new StringBuilder();

        for (int attempt = 1; attempt <= maxRetries; attempt++) {
            log.info("尝试验证OCI CLI配置，第" + attempt + "次尝试");

            // 使用简单的命令测试配置
            Process verifyProcess = executeOciCommand(verifyBuilder, profileName, "oci", "iam", "region", "list",
                    "--profile", profileName, "--config-file", System.getProperty("user.home") + "/.oci/config");

            // 读取命令输出
            BufferedReader reader = new BufferedReader(new InputStreamReader(verifyProcess.getInputStream()));
            StringBuilder output = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                output.append(line).append("\n");
            }

            boolean completed = verifyProcess.waitFor(60, TimeUnit.SECONDS);

            if (completed && verifyProcess.exitValue() == 0) {
                log.info("OCI CLI配置验证成功");
                success = true;
                break;
            } else {
                finalOutput.append("尝试 ").append(attempt).append(" 失败: ").append(output).append("\n");
                log.warn("OCI CLI配置验证失败，尝试 " + attempt + "/" + maxRetries + "，输出: " + output.toString());

                // 检查是否是超时错误，如果是，增加等待时间
                if (output.toString().contains("timed out")) {
                    log.info("检测到超时错误，等待10秒后重试");
                    Thread.sleep(10000);
                }
            }
        }

        if (!success) {
            log.warn("OCI CLI配置验证失败，多次尝试后仍未成功，输出: " + finalOutput.toString());
            throw new RuntimeException("OCI CLI配置验证失败，多次尝试后仍未成功");
        }
    }
    /**
     * 通过Instance Agent重新生成实例SSH密钥
     *
     * @param tenant 租户信息
     * @param instanceId 实例OCID
     * @param compartmentId 区间OCID
     * @return 操作是否成功
     */
    public static boolean regenerateSSHKeysViaInstanceAgent(Tenant tenant, String instanceId, String compartmentId) {
        try {
            log.info("通过Instance Agent为实例" + instanceId + "重新生成SSH密钥");

            // 配置OCI CLI
            String regionCode = RegionEnum.getRegionCode(tenant.getRegion());
            String profileName = "TENANT_"+regionCode +"_"+ tenant.getTenantId();
            configureOciCli(tenant, profileName);

            // 构建重新生成SSH密钥的命令
            String regenerateKeysCommand = "sudo ssh-keygen -A && " +
                    "sudo chmod 600 /etc/ssh/ssh_host_*key && " +
                    "sudo chmod 644 /etc/ssh/ssh_host_*key.pub && " +
                    "sudo systemctl restart ssh || sudo service ssh restart";

            // 创建临时JSON文件
            Path tempFile = Files.createTempFile("instance-agent-command", ".json");
            String jsonPayload = "{\n" +
                    "  \"commandContent\": \"" + regenerateKeysCommand + "\",\n" +
                    "  \"executionTimeOutInSeconds\": 120,\n" +
                    "  \"target\": {\n" +
                    "    \"instanceId\": \"" + instanceId + "\"\n" +
                    "  }\n" +
                    "}";
            Files.write(tempFile, jsonPayload.getBytes());

            // 执行命令
            String oracleCommand = "oci instance-agent command create " +
                    "--compartment-id " + compartmentId + " " +
                    "--content file://" + tempFile.toString() + " " +
                    "--profile " + profileName;

            log.info("执行OCI命令: " + oracleCommand);

            ProcessBuilder processBuilder = new ProcessBuilder();
            processBuilder.command("bash", "-c", oracleCommand);
            processBuilder.redirectErrorStream(true);

            Process process = processBuilder.start();

            // 读取输出
            BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
            StringBuilder output = new StringBuilder();
            String line;
            String commandId = null;

            while ((line = reader.readLine()) != null) {
                output.append(line).append("\n");
                log.info(line);

                // 尝试提取命令ID
                if (line.contains("\"id\":")) {
                    int startIndex = line.indexOf("\"id\":") + 6;
                    int endIndex = line.indexOf("\"", startIndex);
                    if (endIndex > startIndex) {
                        commandId = line.substring(startIndex, endIndex);
                    }
                }
            }

            boolean completed = process.waitFor(60, TimeUnit.SECONDS);

            // 删除临时文件
            Files.deleteIfExists(tempFile);

            if (!completed) {
                process.destroyForcibly();
                log.warn("命令执行超时");
                return false;
            }

            int exitCode = process.exitValue();
            if (exitCode != 0) {
                log.warn("命令创建失败，退出代码: " + exitCode + ", 输出: " + output.toString());
                return false;
            }

            log.info("命令创建成功，ID: " + commandId);

            // 如果有命令ID，则等待命令执行完成
            if (commandId != null) {
                return waitForCommandCompletion(profileName, commandId);
            }

            return true;
        } catch (Exception e) {
            log.warn("通过Instance Agent重生成SSH密钥失败: " + e.getMessage());
            e.printStackTrace();
            return false;
        }
    }

    /**
     * 等待命令执行完成
     */
    private static boolean waitForCommandCompletion(String profileName, String commandId) throws IOException, InterruptedException {
        log.info("等待命令" + commandId + "执行完成");

        int maxRetries = 10;
        int waitTimeSeconds = 15;

        for (int i = 0; i < maxRetries; i++) {
            log.info("检查命令状态，尝试 " + (i + 1) + "/" + maxRetries);

            String checkCommand = "oci instance-agent command get --command-id " + commandId + " --profile " + profileName;

            ProcessBuilder processBuilder = new ProcessBuilder();
            processBuilder.command("bash", "-c", checkCommand);
            processBuilder.redirectErrorStream(true);

            Process process = processBuilder.start();

            BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
            StringBuilder output = new StringBuilder();
            String line;
            String status = null;

            while ((line = reader.readLine()) != null) {
                output.append(line).append("\n");

                // 尝试提取状态
                if (line.contains("\"lifecycle-state\":")) {
                    int startIndex = line.indexOf("\"lifecycle-state\":") + 19;
                    int endIndex = line.indexOf("\"", startIndex);
                    if (endIndex > startIndex) {
                        status = line.substring(startIndex, endIndex);
                        log.info("命令状态: " + status);
                    }
                }
            }

            boolean completed = process.waitFor(30, TimeUnit.SECONDS);

            if (!completed) {
                process.destroyForcibly();
                log.warn("检查命令状态超时");
                Thread.sleep(waitTimeSeconds * 1000);
                continue;
            }

            int exitCode = process.exitValue();
            if (exitCode != 0) {
                log.warn("检查命令状态失败，退出代码: " + exitCode);
                Thread.sleep(waitTimeSeconds * 1000);
                continue;
            }

            // 检查命令状态
            if ("SUCCEEDED".equals(status)) {
                log.info("命令执行成功");
                return true;
            } else if ("FAILED".equals(status) || "CANCELED".equals(status)) {
                log.warn("命令执行失败，状态: " + status);

                // 获取命令执行详情
                getCommandExecution(profileName, commandId);
                return false;
            } else if ("RUNNING".equals(status) || "ACCEPTED".equals(status) || "SCHEDULED".equals(status)) {
                log.info("命令正在执行中，等待" + waitTimeSeconds + "秒后再次检查");
                Thread.sleep(waitTimeSeconds * 1000);
            } else {
                log.warn("未知命令状态: " + status);
                Thread.sleep(waitTimeSeconds * 1000);
            }
        }

        log.warn("等待命令执行超时");
        return false;
    }

    /**
     * 获取命令执行详情
     */
    private static void getCommandExecution(String profileName, String commandId) {
        try {
            log.info("获取命令执行详情，命令ID: " + commandId);

            String getExecCommand = "oci instance-agent command-execution get --command-id " + commandId + " --profile " + profileName;

            ProcessBuilder processBuilder = new ProcessBuilder();
            processBuilder.command("bash", "-c", getExecCommand);
            processBuilder.redirectErrorStream(true);

            Process process = processBuilder.start();

            BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
            StringBuilder output = new StringBuilder();
            String line;

            while ((line = reader.readLine()) != null) {
                output.append(line).append("\n");
            }

            boolean completed = process.waitFor(30, TimeUnit.SECONDS);

            if (!completed) {
                process.destroyForcibly();
                log.warn("获取命令执行详情超时");
                return;
            }

            log.info("命令执行详情: " + output.toString());
        } catch (Exception e) {
            log.warn("获取命令执行详情失败: " + e.getMessage());
        }
    }


    /**
     * 执行shell命令
     */
    private static boolean executeCommand(String command) throws IOException, InterruptedException {
        return executeCommand(command, DEFAULT_TIMEOUT);
    }

    /**
     * 执行shell命令（带超时）
     */
    private static boolean executeCommand(String command, int timeoutSeconds) throws IOException, InterruptedException {
        log.info("执行命令: " + command);

        ProcessBuilder processBuilder = new ProcessBuilder();
        processBuilder.command("/bin/bash", "-c", command);
        processBuilder.redirectErrorStream(true);

        Process process = processBuilder.start();

        // 读取输出
        StringBuilder output = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()))) {
            String line;
            while ((line = reader.readLine()) != null) {
                output.append(line).append("\n");
                log.info(line);
            }
        }

        boolean completed = process.waitFor(timeoutSeconds, TimeUnit.SECONDS);

        if (!completed) {
            process.destroyForcibly();
            log.warn("命令执行超时: " + command);
            return false;
        }

        int exitCode = process.exitValue();
        if (exitCode != 0) {
            log.warn("命令执行失败，退出代码: " + exitCode + ", 输出: " + output.toString());
            return false;
        }

        return true;
    }

    /**
     * 执行PowerShell命令
     */
    private static boolean executePowershellCommand(String command) throws IOException, InterruptedException {
        return executePowershellCommand(command, DEFAULT_TIMEOUT);
    }

    /**
     * 执行PowerShell命令（带超时）
     *
     * @param command        PowerShell命令
     * @param timeoutSeconds 超时时间（秒）
     * @return 是否执行成功
     */
    private static boolean executePowershellCommand(String command, int timeoutSeconds) throws IOException, InterruptedException {
        log.info("执行PowerShell命令: " + command);

        ProcessBuilder processBuilder = new ProcessBuilder();
        processBuilder.command("powershell", "-Command", command);
        processBuilder.redirectErrorStream(true);

        Process process = processBuilder.start();

        // 读取输出
        StringBuilder output = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()))) {
            String line;
            while ((line = reader.readLine()) != null) {
                output.append(line).append("\n");
                log.info(line);
            }
        }

        boolean completed = process.waitFor(timeoutSeconds, TimeUnit.SECONDS);

        if (!completed) {
            process.destroyForcibly();
            log.warn("PowerShell命令执行超时: " + command);
            return false;
        }

        int exitCode = process.exitValue();
        if (exitCode != 0) {
            log.warn("PowerShell命令执行失败，退出代码: " + exitCode + ", 输出: " + output.toString());
            return false;
        }

        return true;
    }

    /**
     * 执行OCI CLI命令并等待完成
     *
     * @param command     OCI CLI命令
     * @param profileName 配置文件名称
     * @return 命令输出
     */
    public static String executeOciCliCommand(String command, String profileName) throws IOException, InterruptedException {
        log.info("执行OCI CLI命令: " + command);

        ProcessBuilder processBuilder = new ProcessBuilder();
        String[] cmdArray = command.split("\\s+");

        Process process = executeOciCommand(processBuilder, profileName, cmdArray);

        // 读取输出
        StringBuilder output = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()))) {
            String line;
            while ((line = reader.readLine()) != null) {
                output.append(line).append("\n");
            }
        }

        boolean completed = process.waitFor(DEFAULT_TIMEOUT, TimeUnit.SECONDS);

        if (!completed) {
            process.destroyForcibly();
            throw new RuntimeException("OCI CLI命令执行超时: " + command);
        }

        int exitCode = process.exitValue();
        if (exitCode != 0) {
            throw new RuntimeException("OCI CLI命令执行失败，退出代码: " + exitCode + ", 输出: " + output.toString());
        }

        return output.toString();
    }


    public static String ConsoleTest(Tenant tenant, String instanceId) {
        log.info("开始为实例" + instanceId + "创建控制台连接");
        final SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        String connectionString = null;

        try (ComputeClient computeClient = ComputeClient.builder().build(provider)) {
            // 设置区域
            computeClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));

            // 生成临时SSH密钥对
            Path keyDir = Paths.get(System.getProperty("user.home"), ".oci", "temp_keys");
            Files.createDirectories(keyDir);
            Path privateKeyPath = keyDir.resolve("temp_key_" + System.currentTimeMillis());
            Path publicKeyPath = Paths.get(privateKeyPath.toString() + ".pub");

            log.info("生成临时SSH密钥对: " + privateKeyPath);
            ProcessBuilder keygenBuilder = new ProcessBuilder();
            keygenBuilder.command("ssh-keygen", "-t", "rsa", "-b", "2048", "-N", "", "-f", privateKeyPath.toString());
            Process keygenProcess = keygenBuilder.start();

            int exitCode = keygenProcess.waitFor();
            if (exitCode != 0) {
                throw new RuntimeException("SSH密钥生成失败，退出代码: " + exitCode);
            }

            // 读取生成的公钥
            String sshPublicKey = new String(Files.readAllBytes(publicKeyPath));
            log.info("已生成临时SSH公钥: " + sshPublicKey);

            // 创建控制台连接
            CreateInstanceConsoleConnectionDetails connectionDetails =
                    CreateInstanceConsoleConnectionDetails.builder()
                            .instanceId(instanceId)
                            .publicKey(sshPublicKey)
                            .build();

            CreateInstanceConsoleConnectionRequest createRequest =
                    CreateInstanceConsoleConnectionRequest.builder()
                            .createInstanceConsoleConnectionDetails(connectionDetails)
                            .build();

            // 发送创建请求
            log.info("发送创建控制台连接请求");
            CreateInstanceConsoleConnectionResponse createResponse =
                    computeClient.createInstanceConsoleConnection(createRequest);

            String connectionId = createResponse.getInstanceConsoleConnection().getId();
            log.info("已创建控制台连接，ID: " + connectionId);

            // 获取连接信息
            GetInstanceConsoleConnectionRequest getRequest =
                    GetInstanceConsoleConnectionRequest.builder()
                            .instanceConsoleConnectionId(connectionId)
                            .build();

            // 等待连接状态变为ACTIVE
            log.info("等待连接状态变为ACTIVE");
            InstanceConsoleConnection connection = null;
            int maxRetries = 12;  // 最多等待1分钟
            for (int i = 0; i < maxRetries; i++) {
                Thread.sleep(5000);
                GetInstanceConsoleConnectionResponse getResponse =
                        computeClient.getInstanceConsoleConnection(getRequest);
                connection = getResponse.getInstanceConsoleConnection();
                log.info("连接状态: " + connection.getLifecycleState());

                if (connection.getLifecycleState().equals(InstanceConsoleConnection.LifecycleState.Active)) {
                    break;
                }

                if (i == maxRetries - 1) {
                    throw new RuntimeException("等待控制台连接激活超时");
                }
            }

            // 获取SSH连接命令
            connectionString = connection.getConnectionString();
            log.info("连接字符串: " + connectionString);

            // 修改连接字符串中的私钥路径
            connectionString = connectionString.replace("private_key_file", privateKeyPath.toString());

            // 可选：保存VNC私钥到文件
            if (connection.getVncConnectionString() != null) {
                log.info("发现VNC连接字符串");
                String vncConnectionString = connection.getVncConnectionString();
                log.info("VNC连接字符串: " + vncConnectionString);

                // 如果有Base64编码的密钥，则保存
                if (connection.getConnectionString() != null && connection.getConnectionString().contains("base64")) {
                    Path vncKeyPath = keyDir.resolve("vnc_key_" + System.currentTimeMillis() + ".pem");
                    try {
                        // 提取Base64编码部分
                        Pattern pattern = Pattern.compile("base64,([^\"]+)");
                        Matcher matcher = pattern.matcher(connection.getConnectionString());
                        if (matcher.find()) {
                            String base64Key = matcher.group(1);
                            byte[] vncKey = Base64.getDecoder().decode(base64Key);
                            try (FileOutputStream fos = new FileOutputStream(vncKeyPath.toFile())) {
                                fos.write(vncKey);
                            }
                            log.info("VNC密钥已保存到: " + vncKeyPath);
                        }
                    } catch (Exception e) {
                        log.warn("保存VNC密钥失败: " + e.getMessage());
                    }
                }
            }

            // 返回连接信息
            return connectionString;

        } catch (Exception e) {
            log.error("创建实例控制台连接失败: " + e.getMessage(), e);
            throw new RuntimeException("创建实例控制台连接失败: " + e.getMessage(), e);
        }
    }

    public static void connectToInstanceConsole(String connectionString) {
        if (connectionString == null || connectionString.isEmpty()) {
            throw new IllegalArgumentException("连接字符串不能为空");
        }

        log.info("尝试使用以下命令连接到实例控制台: " + connectionString);

        try {
            ProcessBuilder pb = new ProcessBuilder("bash", "-c", connectionString);
            pb.inheritIO(); // 将输入输出重定向到当前进程

            log.info("开始执行连接命令...");
            Process process = pb.start();

            // 设置一个较长的超时时间
            boolean completed = process.waitFor(30, TimeUnit.MINUTES);

            if (!completed) {
                log.warn("控制台连接会话超时，强制终止");
                process.destroyForcibly();
            } else {
                int exitCode = process.exitValue();
                log.info("控制台连接会话结束，退出代码: " + exitCode);
            }
        } catch (Exception e) {
            log.error("执行控制台连接命令失败: " + e.getMessage(), e);
            throw new RuntimeException("执行控制台连接命令失败: " + e.getMessage(), e);
        }
    }


    /**
    * @Description: 创建vcn
    * @Param: [com.oracle.bmc.core.VirtualNetworkClient, java.lang.String]
    * @return: com.oracle.bmc.core.model.Vcn
    * @Author doubleDimple
    * @Date: 6/28/25 10:30 PM
    */
    public static List<Vcn> createVcn(
            VirtualNetworkClient virtualNetworkClient, String compartmentId)
            throws Exception {
        List<Vcn> vcns = new ArrayList<>();
        ListVcnsRequest build = ListVcnsRequest.builder().compartmentId(compartmentId)
                .build();

        ListVcnsResponse listVcnsResponse = virtualNetworkClient.listVcns(build);
        if (listVcnsResponse.getItems().size() > 0) {
            return listVcnsResponse.getItems();
        }
        CreateVcnDetails createVcnDetails =
                CreateVcnDetails.builder()
                        .cidrBlock("10.0.0.0/16")
                        .compartmentId(compartmentId)
                        //默认开启ipv6
                        .isIpv6Enabled(true)
                        .displayName(vcnName)
                        //.dnsLabel("myvcn")
                        .build();

        CreateVcnRequest createVcnRequest =
                CreateVcnRequest.builder().createVcnDetails(createVcnDetails).build();
        CreateVcnResponse createVcnResponse = virtualNetworkClient.createVcn(createVcnRequest);

        GetVcnRequest getVcnRequest =
                GetVcnRequest.builder().vcnId(createVcnResponse.getVcn().getId()).build();
        GetVcnResponse getVcnResponse =
                virtualNetworkClient
                        .getWaiters()
                        .forVcn(getVcnRequest, Vcn.LifecycleState.Available)
                        .execute();
        Vcn vcn = getVcnResponse.getVcn();

        log.debug("Created Vcn: " + vcn.getId());
        vcns.add(vcn);
        return vcns;
    }


    public static void createVcnAndFlowLogs(Tenant tenant){
         SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
         try (VirtualNetworkClient virtualNetworkClient = VirtualNetworkClient.builder().build(provider);) {
             LoggingManagementClient loggingManagementClient = LoggingManagementClient.builder().build(provider);
             createVcnAndFlowLogs(tenant.getTenantId(),tenant.getRegion(),tenant.getCloudType(),virtualNetworkClient,loggingManagementClient,provider.getTenantId(),2);
         }catch (Exception e){
             log.error("创建vcn和日志组失败:", e);
         }
    }
    /**
    * @Description: 检查vcn并配置vcnlogs
    * @Param: [com.oracle.bmc.core.VirtualNetworkClient, java.lang.String]
     * flowLogTag :
     * 1表示不开启flow logs
     * 2表示开启flow logs
     *
    * @return: com.oracle.bmc.core.model.Vcn
    * @Author: doubleDimple
    * @Date: 6/28/25 10:58 PM
    */
    public static List<InstanceCloudNetWork> createVcnAndFlowLogs(String tenantId, String region, int cloudType,
                                                                  VirtualNetworkClient virtualNetworkClient, LoggingManagementClient loggingManagementClient, String compartmentId, Integer flowLogTag)
            throws Exception {
        ListVcnsRequest listRequest = ListVcnsRequest.builder()
                .compartmentId(compartmentId)
                .build();
        List<InstanceCloudNetWork> instanceCloudNetWorkList = new ArrayList<>();
        ListVcnsResponse listVcnsResponse = virtualNetworkClient.listVcns(listRequest);
        Vcn vcn = null;
        boolean isNewVcn = false;
        List<Vcn> vcnsList = new ArrayList<>();
        // 检查是否已存在VCN
        if (listVcnsResponse.getItems().size() > 0) {
            for (Vcn item : listVcnsResponse.getItems()) {
                vcn = item;
                log.info("Found existing VCN: " + vcn.getId() + ", Name: " + vcn.getDisplayName());

                // 检查VCN状态
                if (!vcn.getLifecycleState().equals(Vcn.LifecycleState.Available)) {
                    log.info("VCN状态不是Available，等待状态变更: " + vcn.getLifecycleState());

                    GetVcnRequest getVcnRequest = GetVcnRequest.builder()
                            .vcnId(vcn.getId())
                            .build();

                    GetVcnResponse getVcnResponse = virtualNetworkClient
                            .getWaiters()
                            .forVcn(getVcnRequest, Vcn.LifecycleState.Available)
                            .execute();

                    vcn = getVcnResponse.getVcn();
                    log.info("VCN状态已变更为Available");
                }
                vcnsList.add(vcn);
            }

        } else {
            // 创建新VCN
            log.info("Creating new VCN: " + vcnName);

            CreateVcnDetails createVcnDetails = CreateVcnDetails.builder()
                    .cidrBlock("10.0.0.0/16")
                    .compartmentId(compartmentId)
                    .isIpv6Enabled(true) // 默认开启ipv6
                    .displayName(vcnName)
                    .dnsLabel("vcndns")
                    .build();

            CreateVcnRequest createVcnRequest = CreateVcnRequest.builder()
                    .createVcnDetails(createVcnDetails)
                    .build();

            CreateVcnResponse createVcnResponse = virtualNetworkClient.createVcn(createVcnRequest);

            GetVcnRequest getVcnRequest = GetVcnRequest.builder()
                    .vcnId(createVcnResponse.getVcn().getId())
                    .build();

            GetVcnResponse getVcnResponse = virtualNetworkClient
                    .getWaiters()
                    .forVcn(getVcnRequest, Vcn.LifecycleState.Available)
                    .execute();

            vcn = getVcnResponse.getVcn();
            isNewVcn = true;
            log.info("Created new VCN: " + vcn.getId());
            vcnsList.add(vcn);
        }

        // 确保VCN有必要的网络组件（子网、网关等）
        try {
            for (Vcn vcnDetail : vcnsList) {
                InstanceCloudNetWork instanceCloudNetWork = new InstanceCloudNetWork();
                instanceCloudNetWork.setTenantId(tenantId);
                instanceCloudNetWork.setRegion(RegionEnum.getRegionCode(region));
                instanceCloudNetWork.setVcnId(vcnDetail.getId());
                instanceCloudNetWork.setVcnName(vcnDetail.getDisplayName());
                instanceCloudNetWork.setCreatedAt(LocalDateTime.now());
                instanceCloudNetWork.setUpdatedAt(LocalDateTime.now());
                instanceCloudNetWork.setCloudType(cloudType);
                instanceCloudNetWork.setCidrBlock(vcnDetail.getCidrBlock());
                ensureVcnNetworkComponents(instanceCloudNetWork,virtualNetworkClient, compartmentId, vcnDetail, isNewVcn);
                instanceCloudNetWorkList.add(instanceCloudNetWork);
            }
        } catch (Exception e) {
            log.error("创建VCN网络组件失败: " + e.getMessage(), e);
        }
        return instanceCloudNetWorkList;
    }


    /**
     * 确保VCN具有必要的网络组件
     */
    private static void ensureVcnNetworkComponents(InstanceCloudNetWork instanceCloudNetWork,VirtualNetworkClient virtualNetworkClient,
                                                   String compartmentId, Vcn vcn, boolean isNewVcn) {
        try {
            log.debug("检查并创建VCN {} 的网络组件", vcn.getId());

            // 1. 检查并创建Internet Gateway
            InternetGateway internetGateway = ensureInternetGateway(virtualNetworkClient, compartmentId, vcn);

            // 2. 检查并创建Route Table
            RouteTable routeTable = ensureRouteTable(virtualNetworkClient, compartmentId, vcn, internetGateway);

            // 3. 检查并创建Security List
            SecurityList securityList = ensureSecurityList(virtualNetworkClient, compartmentId, vcn);

            // 4. 检查并创建公共子网
            Subnet publicSubnet = ensurePublicSubnet(virtualNetworkClient, compartmentId, vcn,
                    routeTable, securityList);

            // 5. 检查并创建私有子网（可选）
            //Subnet privateSubnet = ensurePrivateSubnet(virtualNetworkClient, compartmentId, vcn, securityList);

            //6. 创建网络安全组
            NetworkSecurityGroup networkSecurityGroup = createNetworkSecurityGroup(virtualNetworkClient, compartmentId, vcn);

            //7.添加网络安全组规则
            addNetworkSecurityGroupSecurityRules(virtualNetworkClient, networkSecurityGroup, vcn.getCidrBlock());

            //8. 确保DHCP选项集
            ensureDhcpOptions(virtualNetworkClient, compartmentId, vcn);

            instanceCloudNetWork.setSubnetId(publicSubnet.getId());
            instanceCloudNetWork.setSubnetName(publicSubnet.getDisplayName());
            instanceCloudNetWork.setNetworkSecurityGroupId(networkSecurityGroup.getId());
            log.debug("VCN网络组件确保完成 - 公共子网: {},",
                    publicSubnet.getId());
        } catch (Exception e) {
            log.error("确保VCN网络组件失败: " + e.getMessage(), e);
        }
    }

    private static DhcpOptions ensureDhcpOptions(VirtualNetworkClient client, String compartmentId, Vcn vcn) {
        try {
            // 检查是否已存在DHCP选项集
            ListDhcpOptionsRequest listRequest = ListDhcpOptionsRequest.builder()
                    .compartmentId(compartmentId)
                    .vcnId(vcn.getId())
                    .build();

            List<DhcpOptions> existingOptions = client.listDhcpOptions(listRequest).getItems();
            if (!existingOptions.isEmpty()) {
                return existingOptions.get(0);
            }

            // 创建新的DHCP选项集
            CreateDhcpDetails dhcpDetails = CreateDhcpDetails.builder()
                    .compartmentId(compartmentId)
                    .vcnId(vcn.getId())
                    .displayName(vcn.getDisplayName() + "-dhcp")
                    .options(Arrays.asList(
                            DhcpDnsOption.builder()
                                    .serverType(DhcpDnsOption.ServerType.VcnLocalPlusInternet)
                                    .build()
                    ))
                    .build();

            CreateDhcpOptionsRequest createRequest = CreateDhcpOptionsRequest.builder()
                    .createDhcpDetails(dhcpDetails)
                    .build();

            return client.createDhcpOptions(createRequest).getDhcpOptions();
        } catch (Exception e) {
            log.error("创建DHCP选项集失败: " + e.getMessage(), e);
            throw e;
        }
    }

    /**
     * 确保Internet Gateway存在
     */
    private static InternetGateway ensureInternetGateway(VirtualNetworkClient virtualNetworkClient,
                                                         String compartmentId, Vcn vcn) {
        try {
            // 检查是否已存在Internet Gateway
            ListInternetGatewaysRequest listRequest = ListInternetGatewaysRequest.builder()
                    .compartmentId(compartmentId)
                    .vcnId(vcn.getId())
                    .build();

            ListInternetGatewaysResponse listResponse = virtualNetworkClient.listInternetGateways(listRequest);

            if (!listResponse.getItems().isEmpty()) {
                InternetGateway existing = listResponse.getItems().get(0);
                log.debug("使用现有Internet Gateway: " + existing.getId());
                return existing;
            }

            // 创建新的Internet Gateway
            log.info("创建新的Internet Gateway");

            CreateInternetGatewayDetails createDetails = CreateInternetGatewayDetails.builder()
                    .compartmentId(compartmentId)
                    .vcnId(vcn.getId())
                    .displayName(vcnName + "-igw")
                    .isEnabled(true)
                    .build();

            CreateInternetGatewayRequest createRequest = CreateInternetGatewayRequest.builder()
                    .createInternetGatewayDetails(createDetails)
                    .build();

            CreateInternetGatewayResponse createResponse = virtualNetworkClient.createInternetGateway(createRequest);

            // 等待Gateway变为Available
            GetInternetGatewayRequest getRequest = GetInternetGatewayRequest.builder()
                    .igId(createResponse.getInternetGateway().getId())
                    .build();

            GetInternetGatewayResponse getResponse = virtualNetworkClient.getWaiters()
                    .forInternetGateway(getRequest, InternetGateway.LifecycleState.Available)
                    .execute();

            log.info("Internet Gateway创建成功: " + getResponse.getInternetGateway().getId());
            return getResponse.getInternetGateway();

        } catch (Exception e) {
            log.error("创建Internet Gateway失败: " + e.getMessage(), e);
            throw new RuntimeException("Internet Gateway创建失败", e);
        }
    }

    /**
     * 确保Route Table存在
     */
    private static RouteTable ensureRouteTable(VirtualNetworkClient virtualNetworkClient,
                                               String compartmentId, Vcn vcn, InternetGateway internetGateway) {
        try {
            // 检查是否已存在自定义Route Table
            ListRouteTablesRequest listRequest = ListRouteTablesRequest.builder()
                    .compartmentId(compartmentId)
                    .vcnId(vcn.getId())
                    .build();

            ListRouteTablesResponse listResponse = virtualNetworkClient.listRouteTables(listRequest);

            if (!listResponse.getItems().isEmpty()) {
                RouteTable existing = listResponse.getItems().get(0);
                log.debug("使用现有Route Table: " + existing.getId());
                return existing;
            }

            // 创建新的Route Table
            log.info("创建新的Route Table");

            RouteRule routeRule = RouteRule.builder()
                    .destination("0.0.0.0/0")
                    .destinationType(RouteRule.DestinationType.CidrBlock)
                    .networkEntityId(internetGateway.getId())
                    .build();

            CreateRouteTableDetails createDetails = CreateRouteTableDetails.builder()
                    .compartmentId(compartmentId)
                    .vcnId(vcn.getId())
                    .displayName(vcnName + "-rt")
                    .routeRules(Arrays.asList(routeRule))
                    .build();

            CreateRouteTableRequest createRequest = CreateRouteTableRequest.builder()
                    .createRouteTableDetails(createDetails)
                    .build();

            CreateRouteTableResponse createResponse = virtualNetworkClient.createRouteTable(createRequest);

            // 等待Route Table变为Available
            GetRouteTableRequest getRequest = GetRouteTableRequest.builder()
                    .rtId(createResponse.getRouteTable().getId())
                    .build();

            GetRouteTableResponse getResponse = virtualNetworkClient.getWaiters()
                    .forRouteTable(getRequest, RouteTable.LifecycleState.Available)
                    .execute();

            log.info("Route Table创建成功: " + getResponse.getRouteTable().getId());
            return getResponse.getRouteTable();

        } catch (Exception e) {
            log.error("创建Route Table失败: " + e.getMessage(), e);
            throw new RuntimeException("Route Table创建失败", e);
        }
    }

    /**
     * 确保Security List存在
     */
    private static SecurityList ensureSecurityList(VirtualNetworkClient virtualNetworkClient,
                                                   String compartmentId, Vcn vcn) {
        try {
            // 检查是否已存在自定义Security List
            ListSecurityListsRequest listRequest = ListSecurityListsRequest.builder()
                    .compartmentId(compartmentId)
                    .vcnId(vcn.getId())
                    .build();

            ListSecurityListsResponse listResponse = virtualNetworkClient.listSecurityLists(listRequest);

            if (!listResponse.getItems().isEmpty()) {
                SecurityList existing = listResponse.getItems().get(0);
                log.debug("使用现有Security List: " + existing.getId());
                return existing;
            }

            // 创建新的Security List
            log.info("创建新的Security List");

            // 入站规则：允许SSH (22) 和 HTTP (80)
            IngressSecurityRule sshRule = IngressSecurityRule.builder()
                    .source("0.0.0.0/0")
                    .sourceType(IngressSecurityRule.SourceType.CidrBlock)
                    .protocol("6") // TCP
                    .tcpOptions(TcpOptions.builder()
                            .destinationPortRange(PortRange.builder()
                                    .min(22)
                                    .max(22)
                                    .build())
                            .build())
                    .build();

            IngressSecurityRule httpRule = IngressSecurityRule.builder()
                    .source("0.0.0.0/0")
                    .sourceType(IngressSecurityRule.SourceType.CidrBlock)
                    .protocol("6") // TCP
                    .tcpOptions(TcpOptions.builder()
                            .destinationPortRange(PortRange.builder()
                                    .min(80)
                                    .max(80)
                                    .build())
                            .build())
                    .build();

            // 出站规则：允许所有出站流量
            EgressSecurityRule egressRule = EgressSecurityRule.builder()
                    .destination("0.0.0.0/0")
                    .destinationType(EgressSecurityRule.DestinationType.CidrBlock)
                    .protocol("all")
                    .build();

            CreateSecurityListDetails createDetails = CreateSecurityListDetails.builder()
                    .compartmentId(compartmentId)
                    .vcnId(vcn.getId())
                    .displayName(vcnName + "-sl")
                    .ingressSecurityRules(Arrays.asList(sshRule, httpRule))
                    .egressSecurityRules(Arrays.asList(egressRule))
                    .build();

            CreateSecurityListRequest createRequest = CreateSecurityListRequest.builder()
                    .createSecurityListDetails(createDetails)
                    .build();

            CreateSecurityListResponse createResponse = virtualNetworkClient.createSecurityList(createRequest);

            // 等待Security List变为Available
            GetSecurityListRequest getRequest = GetSecurityListRequest.builder()
                    .securityListId(createResponse.getSecurityList().getId())
                    .build();

            GetSecurityListResponse getResponse = virtualNetworkClient.getWaiters()
                    .forSecurityList(getRequest, SecurityList.LifecycleState.Available)
                    .execute();

            log.info("Security List创建成功: " + getResponse.getSecurityList().getId());
            return getResponse.getSecurityList();

        } catch (Exception e) {
            log.error("创建Security List失败: " + e.getMessage(), e);
            throw new RuntimeException("Security List创建失败", e);
        }
    }

    /**
     * 确保公共子网存在
     */
    private static Subnet ensurePublicSubnet(VirtualNetworkClient virtualNetworkClient,
                                             String compartmentId, Vcn vcn,
                                             RouteTable routeTable, SecurityList securityList) {
        try {
            String subnetName = vcnName + "-public-subnet";

            // 检查是否已存在公共子网
            ListSubnetsRequest listRequest = ListSubnetsRequest.builder()
                    .compartmentId(compartmentId)
                    .vcnId(vcn.getId())
                    .build();

            ListSubnetsResponse listResponse = virtualNetworkClient.listSubnets(listRequest);

            if (!listResponse.getItems().isEmpty()) {
                Subnet existing = listResponse.getItems().get(0);
                log.debug("使用现有公共子网: " + existing.getId());
                return existing;
            }

            // 创建新的公共子网
            log.debug("创建新的公共子网");

            CreateSubnetDetails createDetails = CreateSubnetDetails.builder()
                    .compartmentId(compartmentId)
                    .vcnId(vcn.getId())
                    .displayName(subnetName)
                    .cidrBlock("10.0.1.0/24")
                    .routeTableId(routeTable.getId())
                    .securityListIds(Arrays.asList(securityList.getId()))
                    .prohibitPublicIpOnVnic(false) // 允许公网IP
                    .build();

            CreateSubnetRequest createRequest = CreateSubnetRequest.builder()
                    .createSubnetDetails(createDetails)
                    .build();

            CreateSubnetResponse createResponse = virtualNetworkClient.createSubnet(createRequest);

            // 等待子网变为Available
            GetSubnetRequest getRequest = GetSubnetRequest.builder()
                    .subnetId(createResponse.getSubnet().getId())
                    .build();

            GetSubnetResponse getResponse = virtualNetworkClient.getWaiters()
                    .forSubnet(getRequest, Subnet.LifecycleState.Available)
                    .execute();

            log.info("公共子网创建成功: " + getResponse.getSubnet().getId());
            return getResponse.getSubnet();

        } catch (Exception e) {
            log.error("创建公共子网失败: " + e.getMessage(), e);
            throw new RuntimeException("公共子网创建失败", e);
        }
    }

    /**
     * 确保私有子网存在
     */
    private static Subnet ensurePrivateSubnet(VirtualNetworkClient virtualNetworkClient,
                                              String compartmentId, Vcn vcn, SecurityList securityList) {
        try {
            String subnetName = vcnName + "-private-subnet";

            // 检查是否已存在私有子网
            ListSubnetsRequest listRequest = ListSubnetsRequest.builder()
                    .compartmentId(compartmentId)
                    .vcnId(vcn.getId())
                    .build();

            ListSubnetsResponse listResponse = virtualNetworkClient.listSubnets(listRequest);

            if (!listResponse.getItems().isEmpty()) {
                Subnet existing = listResponse.getItems().get(0);
                log.info("使用现有私有子网: " + existing.getId());
                return existing;
            }

            // 创建新的私有子网
            log.info("创建新的私有子网");

            CreateSubnetDetails createDetails = CreateSubnetDetails.builder()
                    .compartmentId(compartmentId)
                    .vcnId(vcn.getId())
                    .displayName(subnetName)
                    .cidrBlock("10.0.2.0/24")
                    .securityListIds(Arrays.asList(securityList.getId()))
                    .prohibitPublicIpOnVnic(true) // 私有子网，禁止公网IP
                    .build();

            CreateSubnetRequest createRequest = CreateSubnetRequest.builder()
                    .createSubnetDetails(createDetails)
                    .build();

            CreateSubnetResponse createResponse = virtualNetworkClient.createSubnet(createRequest);

            // 等待子网变为Available
            GetSubnetRequest getRequest = GetSubnetRequest.builder()
                    .subnetId(createResponse.getSubnet().getId())
                    .build();

            GetSubnetResponse getResponse = virtualNetworkClient.getWaiters()
                    .forSubnet(getRequest, Subnet.LifecycleState.Available)
                    .execute();

            log.info("私有子网创建成功: " + getResponse.getSubnet().getId());
            return getResponse.getSubnet();

        } catch (Exception e) {
            log.error("创建私有子网失败: " + e.getMessage(), e);
            throw new RuntimeException("私有子网创建失败", e);
        }
    }



    /**
    * 检查并创建网络安全组
    */
    public static NetworkSecurityGroup createNetworkSecurityGroup(
            VirtualNetworkClient virtualNetworkClient, String compartmentId, Vcn vcn)
            throws Exception {

        // 获取 NSG 列表
        ListNetworkSecurityGroupsResponse response =
                virtualNetworkClient.listNetworkSecurityGroups(ListNetworkSecurityGroupsRequest.builder()
                        .compartmentId(compartmentId).vcnId(vcn.getId()).build());
        if (null != response && response.getItems().size() > 0){
            return response.getItems().get(0);
        }else {
            CreateNetworkSecurityGroupDetails createNetworkSecurityGroupDetails =
                    CreateNetworkSecurityGroupDetails.builder()
                            .compartmentId(compartmentId)
                            .displayName(networkSecurityGroupName)
                            .vcnId(vcn.getId())
                            .build();
            CreateNetworkSecurityGroupRequest createNetworkSecurityGroupRequest =
                    CreateNetworkSecurityGroupRequest.builder()
                            .createNetworkSecurityGroupDetails(createNetworkSecurityGroupDetails)
                            .build();

            ListNetworkSecurityGroupsRequest build = ListNetworkSecurityGroupsRequest.builder().
                    compartmentId(compartmentId).
                    displayName(networkSecurityGroupName).vcnId(vcn.getId()).build();

            ListNetworkSecurityGroupsResponse listNetworkSecurityGroupsResponse = virtualNetworkClient.listNetworkSecurityGroups(build);
            if (listNetworkSecurityGroupsResponse.getItems().size() > 0) {
                return listNetworkSecurityGroupsResponse.getItems().get(0);
            }

            CreateNetworkSecurityGroupResponse createNetworkSecurityGroupResponse =
                    virtualNetworkClient.createNetworkSecurityGroup(createNetworkSecurityGroupRequest);

            GetNetworkSecurityGroupRequest getNetworkSecurityGroupRequest =
                    GetNetworkSecurityGroupRequest.builder()
                            .networkSecurityGroupId(
                                    createNetworkSecurityGroupResponse
                                            .getNetworkSecurityGroup()
                                            .getId()).build();
            GetNetworkSecurityGroupResponse getNetworkSecurityGroupResponse =
                    virtualNetworkClient
                            .getWaiters()
                            .forNetworkSecurityGroup(
                                    getNetworkSecurityGroupRequest,
                                    NetworkSecurityGroup.LifecycleState.Available)
                            .execute();
            NetworkSecurityGroup networkSecurityGroup =
                    getNetworkSecurityGroupResponse.getNetworkSecurityGroup();

            if (log.isDebugEnabled()) {
                System.out.println("Created Network Security Group: " + networkSecurityGroup.getId());
                System.out.println(networkSecurityGroup);
                System.out.println();
            }
            return networkSecurityGroup;
        }
    }

    /**
    * 添加网络安全组规则
    */
    public static void addNetworkSecurityGroupSecurityRules(
            VirtualNetworkClient virtualNetworkClient,
            NetworkSecurityGroup networkSecurityGroup,
            String networkCidrBlock) {

        ListNetworkSecurityGroupSecurityRulesRequest listNetworkSecurityGroupSecurityRulesRequest =
                ListNetworkSecurityGroupSecurityRulesRequest.builder()
                        .networkSecurityGroupId(networkSecurityGroup.getId())
                        .build();
        ListNetworkSecurityGroupSecurityRulesResponse
                listNetworkSecurityGroupSecurityRulesResponse =
                virtualNetworkClient.listNetworkSecurityGroupSecurityRules(
                        listNetworkSecurityGroupSecurityRulesRequest);
        List<SecurityRule> securityRules = listNetworkSecurityGroupSecurityRulesResponse.getItems();

        if (securityRules.size() > 0){
            return;
        }
        if (log.isDebugEnabled()) {
            log.info("Current Security Rules in Network Security Group");
            log.info("================================================");
            securityRules.forEach(System.out::println);
            System.out.println();
        }

        AddSecurityRuleDetails addSecurityRuleDetails =
                AddSecurityRuleDetails.builder()
                        .description("Incoming HTTP connections")
                        .direction(AddSecurityRuleDetails.Direction.Ingress)
                        .protocol("6")
                        .source(networkCidrBlock)
                        .sourceType(AddSecurityRuleDetails.SourceType.CidrBlock)
                        .tcpOptions(TcpOptions.builder().destinationPortRange(
                                        PortRange.builder().min(80).max(80).build())
                                .build())
                        .build();
        AddNetworkSecurityGroupSecurityRulesDetails addNetworkSecurityGroupSecurityRulesDetails =
                AddNetworkSecurityGroupSecurityRulesDetails.builder()
                        .securityRules(Arrays.asList(addSecurityRuleDetails))
                        .build();
        AddNetworkSecurityGroupSecurityRulesRequest addNetworkSecurityGroupSecurityRulesRequest =
                AddNetworkSecurityGroupSecurityRulesRequest.builder()
                        .networkSecurityGroupId(networkSecurityGroup.getId())
                        .addNetworkSecurityGroupSecurityRulesDetails(
                                addNetworkSecurityGroupSecurityRulesDetails)
                        .build();
        virtualNetworkClient.addNetworkSecurityGroupSecurityRules(
                addNetworkSecurityGroupSecurityRulesRequest);

        listNetworkSecurityGroupSecurityRulesResponse =
                virtualNetworkClient.listNetworkSecurityGroupSecurityRules(
                        listNetworkSecurityGroupSecurityRulesRequest);
        securityRules = listNetworkSecurityGroupSecurityRulesResponse.getItems();

        if (log.isDebugEnabled()) {
            log.info("Updated Security Rules in Network Security Group");
            log.info("================================================");
            securityRules.forEach(System.out::println);
            System.out.println();
        }

    }

}

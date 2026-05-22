package com.doubledimple.ociserver.config.task;

import com.doubledimple.dao.entity.AppVersion;
import com.doubledimple.dao.repository.AppVersionRepository;
import com.doubledimple.ocicommon.template.MessageTemplate;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.service.message.factory.MessageFactory;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.json.JSONObject;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import javax.annotation.PostConstruct;
import javax.annotation.Resource;
import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * @version 1.0.0
 * @ClassName VersionCheckService
 * @Description 版本检查和更新服务
 * @Author doubleDimple
 * @Date 2025-02-15 10:53
 */
@Service
@Slf4j
@RequiredArgsConstructor
public class VersionCheckTask {

    @Resource
    RestTemplate restTemplate;

    @Resource
    MessageFactory messageFactory;

    private final AppVersionRepository versionRepository;

    private static final String GITHUB_API_URL = "https://api.github.com/repos/doubleDimple/oci-start/releases/latest";
    private static final String DOCKER_HUB_API_URL = "https://hub.docker.com/v2/repositories/lovele/oci-start/tags";

    /**
     * 初始化版本信息
     */
    @PostConstruct
    public void init() {
        if (!versionRepository.findFirstByOrderByIdAsc().isPresent()) {
            boolean isDocker = isDockerDeploy();
            String version = isDocker ? "2.0.6" : "v-2.0.6";

            AppVersion appVersion = new AppVersion();
            appVersion.setCurrentVersion(version);
            appVersion.setLatestVersion(version);
            appVersion.setDeployType(isDocker ? AppVersion.DeployType.DOCKER : AppVersion.DeployType.SSH);
            versionRepository.save(appVersion);
            if (log.isDebugEnabled()){
                log.debug("初始化版本信息: {}, 部署方式: {}", version, appVersion.getDeployType());
            }
        }
    }

    /**
     * 检查是否是Docker部署
     */
    private boolean isDockerDeploy() {
        try {
            if (new File("/.dockerenv").exists()) {
                log.debug("Found /.dockerenv file - running in Docker");
                return true;
            }
        } catch (Exception e) {
            log.error("检查Docker部署失败", e);
            return false;
        }
        return false;
    }

    /**
     * 定时检查最新版本
     */
    public void checkVersion() {
        if (log.isDebugEnabled()){
            log.debug("start version checking......");
        }
        try {
            AppVersion version = versionRepository.findFirstByOrderByIdAsc()
                    .orElseThrow(() -> new RuntimeException("未找到版本信息"));

            String latestVersion;
            JSONObject latestVersionFromGithub = getLatestVersionFromGithub();
            if (latestVersionFromGithub == null){
                log.warn("获取GitHub最新版本失败");
                return;
            }
            String githubVersion = latestVersionFromGithub.getString("tag_name");
            String releaseNotes = latestVersionFromGithub.getString("release_notes");
            if (version.getDeployType() == AppVersion.DeployType.DOCKER) {
                // Docker部署时同时检查GitHub和Docker Hub
                String dockerHubVersion = getLatestVersionFromDockerHub();

                if (githubVersion == null || dockerHubVersion == null) {
                    log.warn("获取版本信息失败 - GitHub版本: {}, Docker Hub版本: {}",
                            githubVersion, dockerHubVersion);
                    return;
                }
                latestVersion = dockerHubVersion;
            } else {
                // SSH部署只检查GitHub
                latestVersion = githubVersion;
            }

            if (latestVersion != null && !latestVersion.equals(version.getLatestVersion())) {
                version.setLatestVersion(latestVersion);
                versionRepository.save(version);
                //执行消息发送
                sendUpdateMessage(latestVersion, releaseNotes);
                if (log.isDebugEnabled()){
                    log.debug("发现新版本 - 当前版本: {}, 最新版本: {}, 部署方式: {}",
                            version.getCurrentVersion(), latestVersion, version.getDeployType());
                }
            }
            log.debug("start version checking finish");
        } catch (Exception e) {
            log.error("版本检查失败", e);
        }
    }

    /**
     * 获取GitHub最新版本
     */
    private JSONObject getLatestVersionFromGithub() {
        JSONObject jsonObject = new JSONObject();
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.set("Accept", "application/vnd.github.v3+json");
            ResponseEntity<Map> response = restTemplate.exchange(
                    GITHUB_API_URL,
                    HttpMethod.GET,
                    new HttpEntity<>(headers),
                    Map.class
            );

            if (response.getStatusCode() == HttpStatus.OK && response.getBody() != null) {
                Map<String, Object> bodyMap = response.getBody();
                String tagName = (String) bodyMap.get("tag_name");
                String releaseNotes = (String) bodyMap.get("body"); // 获取更新内容
                jsonObject.put("tag_name", tagName);
                jsonObject.put("release_notes", releaseNotes);
                return jsonObject;
            }
        } catch (Exception e) {
            log.error("获取GitHub最新版本失败,原因为:{}", e.getMessage());
        }
        return null;
    }

    /**
     * 获取Docker Hub最新版本
     */
    private String getLatestVersionFromDockerHub() {
        try {
            RestTemplate restTemplate = new RestTemplate();
            ResponseEntity<Map> response = restTemplate.getForEntity(DOCKER_HUB_API_URL, Map.class);

            if (response.getStatusCode() == HttpStatus.OK && response.getBody() != null) {
                List<Map<String, Object>> results = (List<Map<String, Object>>) response.getBody().get("results");

                // 过滤出纯数字版本号的标签（例如：2.0.6）
                String latestVersion = results.stream()
                        .map(tag -> (String) tag.get("name"))
                        .filter(tag -> !tag.equals("latest"))  // 排除latest标签
                        .filter(tag -> tag.matches("\\d+\\.\\d+\\.\\d+"))  // 匹配纯数字版本号格式 (2.0.6)
                        .findFirst()
                        .orElse(null);

                if (latestVersion != null) {
                    // 直接使用数字版本号
                    return latestVersion;
                }
            }

            log.error("未在Docker Hub找到有效的版本号标签");
            return null;
        } catch (Exception e) {
            log.error("获取Docker Hub最新版本失败", e);
            return null;
        }
    }

    /**
     * 更新完成后调用此方法
     */
    public void updateComplete() {
        AppVersion version = versionRepository.findFirstByOrderByIdAsc()
                .orElseThrow(() -> new RuntimeException("未找到版本信息"));
        version.setCurrentVersion(version.getLatestVersion());
        versionRepository.save(version);
        log.info("版本已更新到: {}", version.getCurrentVersion());
    }

    /**
     * 获取版本信息
     */
    public AppVersion getVersion() {
        return versionRepository.findFirstByOrderByIdAsc()
                .orElseThrow(() -> new RuntimeException("未找到版本信息"));
    }

    /**
     * @Description: 版本更新脚本
     * @Param: []
     * @return: void
     * @Author doubleDimple
     * @Date: 2/15/25 9:27 PM
     */
    public void executeUpdate() {
        try {
            // 1. 检查是否需要更新
            AppVersion version = getVersion();
            if (!version.needUpdate()) {
                log.warn("当前已是最新版本，无需更新");
                return;
            }

            log.info("版本更新开始执行");

            // 根据部署类型执行不同的更新逻辑
            if (version.getDeployType() == AppVersion.DeployType.DOCKER) {
                executeDockerUpdate();
            } else {
                executeSshUpdate();
            }

            log.info("更新执行完成");
        } catch (Exception e) {
            log.error("执行更新失败", e);
            throw new RuntimeException("执行更新失败: " + e.getMessage());
        }
    }

    /**
     * 执行Docker方式的更新 - 调用专门的Docker更新服务
     */
    private void executeDockerUpdate() {
        log.info("开始执行Docker更新流程");

        try {

            updateComplete();

            // 简化命令，不需要cd
            String command = "curl -L $(curl -s " + GITHUB_API_URL + " | " +
                    "grep \"browser_download_url.*jar\" | cut -d '\"' -f 4) -o oci-start.jar && " +
                    "pkill -f \"oci-start.jar\" && " +
                    "nohup java -jar oci-start.jar > /dev/null 2>&1 &";

            Runtime.getRuntime().exec(new String[]{"/bin/bash", "-c", command});

            log.info("Docker更新命令已执行，应用即将重启");

        } catch (Exception e) {
            log.error("Docker更新失败", e);
            throw new RuntimeException("Docker更新失败: " + e.getMessage());
        }
    }

    /**
     * 执行SSH方式的更新 - 保持异步逻辑
     */
    private void executeSshUpdate() throws IOException {
        log.info("开始执行SSH更新流程");

        // 获取项目根目录
        String rootPath = System.getProperty("user.dir");
        File rootDir = new File(rootPath);

        // 查找更新脚本
        File scriptFile = findUpdateScript(rootDir);
        if (scriptFile == null) {
            throw new RuntimeException("未找到更新脚本");
        }

        // 关键：先更新版本信息，然后异步执行脚本
        updateComplete();
        log.info("版本信息已更新");

        executeSshUpdateScript(scriptFile, rootDir);
    }

    /**
     * 查找更新脚本
     */
    private File findUpdateScript(File rootDir) {
        log.info("在目录{}中查找更新脚本", rootDir.getAbsolutePath());
        File[] files = rootDir.listFiles((dir, name) -> name.endsWith(".sh"));
        if (files == null || files.length == 0) {
            log.warn("未在目录{}中找到更新脚本", rootDir.getAbsolutePath());
            return null;
        }
        log.info("找到更新脚本: {}", files[0].getAbsolutePath());
        return files[0];
    }

    /**
     * 执行更新脚本 - 保持异步逻辑
     */
    private void executeSshUpdateScript(File scriptFile, File workDir) throws IOException {
        // 确保脚本有执行权限
        if (!scriptFile.canExecute() && !scriptFile.setExecutable(true)) {
            throw new RuntimeException("无法设置脚本执行权限: " + scriptFile.getAbsolutePath());
        }

        AppVersion version = versionRepository.findFirstByOrderByIdAsc()
                .orElseThrow(() -> new RuntimeException("未找到版本信息"));

        String updateCommand = version.getDeployType() == AppVersion.DeployType.SSH ? "update" : "install";

        // 使用nohup setsid异步执行，不等待进程完成
        List<String> command = new ArrayList<>();
        command.add("/bin/bash");
        command.add("-c");
        command.add("nohup setsid " + scriptFile.getAbsolutePath() + " " + updateCommand + " > /tmp/ociStart_update.log 2>&1 &");

        log.info("完整执行命令: {}", command);
        log.info("工作目录: {}", workDir.getAbsolutePath());

        // 使用 ProcessBuilder 执行命令
        ProcessBuilder processBuilder = new ProcessBuilder(command);
        processBuilder.directory(workDir);
        processBuilder.inheritIO();

        log.info("开始执行更新脚本: {}, 执行命令: {}", scriptFile.getName(), updateCommand);

        // 启动进程，不等待完成
        processBuilder.start();

        // 直接返回，不等待进程完成
        log.info("SSH更新命令已提交执行");
    }
    /**
     * 获取GitHub Stars数量
     */
    public Long getGitHubStars() {
        try {
            RestTemplate restTemplate = new RestTemplate();
            HttpHeaders headers = new HttpHeaders();
            headers.set("Accept", "application/vnd.github.v3+json");
            headers.set("User-Agent", "OCI-START-Application");

            ResponseEntity<Map> response = restTemplate.exchange(
                    "https://api.github.com/repos/doubleDimple/oci-start",
                    HttpMethod.GET,
                    new HttpEntity<>(headers),
                    Map.class
            );

            if (response.getStatusCode() == HttpStatus.OK && response.getBody() != null) {
                Object starCount = response.getBody().get("stargazers_count");
                if (starCount != null) {
                    return Long.valueOf(starCount.toString());
                }
            }

            log.warn("获取GitHub Stars失败，返回默认值");
            return 0L;

        } catch (Exception e) {
            log.error("获取GitHub Stars失败,原因为:{}", e.getMessage());
            return 0L;
        }
    }

    private void sendUpdateMessage(String finalLatestVersion, String releaseNotes) {
        if (StringUtils.isNotBlank(releaseNotes)){
            String message = String.format(
                    MessageTemplate.MESSAGE_VERSION_UPDATE_TEMPLATE,
                    finalLatestVersion,
                    releaseNotes
            );
            messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplate(message);
        }
    }
}
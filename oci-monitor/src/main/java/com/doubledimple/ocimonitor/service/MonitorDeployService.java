package com.doubledimple.ocimonitor.service;

import com.doubledimple.dao.entity.CloudSshConn;
import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.repository.CloudSshConnRepository;
import com.doubledimple.dao.repository.OracleInstanceDetailRepository;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ocicommon.param.ScriptResult;
import com.doubledimple.ocicommon.utils.JschUtils;
import com.doubledimple.ocimonitor.service.quality.NetworkQualityService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import javax.annotation.Resource;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;


/**
 * @version 1.0.0
 * @ClassName MonitorDeployService
 * @Description TODO
 * @Author doubleDimple
 * @Date 2026-02-05 14:26
 */
@Service
@Slf4j
public class MonitorDeployService {

    private final ConcurrentMap<String, Boolean> activeDeployments = new ConcurrentHashMap<>();

    @Resource
    CloudSshConnRepository cloudSshConnRepository;

    @Resource
    private OracleInstanceDetailRepository oracleInstanceDetailRepository;

    @Resource
    private MonitorCoreService monitorCoreService;

    @Resource
    private NetworkQualityService networkQualityService;

    /**
     * 远程一键安装监控探针
     *
     * @param vpsId 目标 VPS 的数据库 ID
     * @return 安装结果描述
     */
    public ApiResponse installAgent(String vpsId) {
        String id = String.valueOf(Long.parseLong(vpsId));
        if (activeDeployments.putIfAbsent(id, Boolean.TRUE) != null) {
            return ApiResponse.error("该实例正在安装或卸载探针，请等待当前操作结束");
        }
        try {
            return installAgentInternal(id);
        } finally {
            activeDeployments.remove(id);
        }
    }

    private ApiResponse installAgentInternal(String vpsId) {
        InstanceDetails instanceDetails = oracleInstanceDetailRepository.findById(Long.valueOf(vpsId))
                .orElseThrow(() -> new RuntimeException("VPS实例不存在: " + vpsId));
        Optional<CloudSshConn> sshConnOpt = cloudSshConnRepository.findByInstanceId(instanceDetails.getInstanceId());
        if (!sshConnOpt.isPresent()){
            log.warn("未找到实例 [{}] 的SSH连接信息", instanceDetails.getDisplayName());
            return ApiResponse.error("未找到实例的SSH连接信息");
        }
        CloudSshConn cloudSshConn = sshConnOpt.get();
        String credential = networkQualityService.issueAgentCredential(vpsId).getToken();
        String command = monitorCoreService.generateNetworkInstallScript(instanceDetails.getInstanceId(), credential, 5);
        log.info("开始对 VPS [ID: {}] 安装资源与网络探针", vpsId);
        int sshPort = cloudSshConn.getPort() != null ? cloudSshConn.getPort() : 22;
        ScriptResult result = JschUtils.executeScriptJsch(
                instanceDetails.getPublicIps(),
                cloudSshConn.getUsername(),
                cloudSshConn.getPassword(),
                sshPort,
                command,
                true
        );
        if (result.isSuccess()) {
            instanceDetails.setMonitorInstalled(true);
            oracleInstanceDetailRepository.save(instanceDetails);
            log.info("VPS [ID: {}] 资源与网络探针服务已启动", vpsId);
            return ApiResponse.success("资源与网络探针已启动；请等待真实数据上报");
        } else {
            log.error("VPS [ID: {}] 探针安装未完成，退出状态: {}", vpsId, result.getExitCode());
            return ApiResponse.error(installationError(result.getError()));
        }
    }

    /**
     * 远程卸载监控
     */
    public String uninstallAgent(String vpsId) {
        String id = String.valueOf(Long.parseLong(vpsId));
        if (activeDeployments.putIfAbsent(id, Boolean.TRUE) != null) {
            throw new IllegalStateException("该实例正在安装或卸载探针，请等待当前操作结束");
        }
        try {
            return uninstallAgentInternal(id);
        } finally {
            activeDeployments.remove(id);
        }
    }

    private String uninstallAgentInternal(String vpsId) {

        InstanceDetails instanceDetails = oracleInstanceDetailRepository.findById(Long.valueOf(vpsId))
                .orElseThrow(() -> new RuntimeException("VPS实例不存在"));

        CloudSshConn cloudSshConn = cloudSshConnRepository.findByInstanceId(instanceDetails.getInstanceId())
                .orElseThrow(() -> new RuntimeException("SSH信息未找到"));
        String uninstallScript =
                "set -e\n" +
                "command -v systemctl >/dev/null 2>&1\n" +
                "[ -d /run/systemd/system ]\n" +
                // Do not delegate cleanup to an older installed shell that knows only one service.
                "for vps_unit in vps-network-agent.service vps-agent.service; do\n" +
                "  unit_state=$(systemctl show --property=LoadState --value \"$vps_unit\")\n" +
                "  [ -n \"$unit_state\" ]\n" +
                "  if [ \"$unit_state\" != not-found ]; then\n" +
                "    systemctl stop \"$vps_unit\"\n    systemctl disable \"$vps_unit\"\n  fi\n" +
                "  active_state=$(systemctl show --property=ActiveState --value \"$vps_unit\")\n" +
                "  case \"$active_state\" in inactive|failed) ;; *) echo '探针服务未停止，卸载未完成' >&2; exit 1 ;; esac\n" +
                "done\n" +
                "for vps_file in /etc/systemd/system/vps-network-agent.service /etc/systemd/system/vps-agent.service /usr/local/bin/vps-network-agent.py /usr/local/bin/vps-agent.sh /etc/vps-network-agent/config.json; do\n" +
                "  rm -f -- \"$vps_file\"\n  [ ! -e \"$vps_file\" ] && [ ! -L \"$vps_file\" ]\ndone\n" +
                "if [ -d /etc/vps-network-agent ]; then rmdir --ignore-fail-on-non-empty /etc/vps-network-agent; fi\n" +
                "systemctl daemon-reload\n";
        String quotedScript = "'" + uninstallScript.replace("'", "'\"'\"'") + "'";
        String command = "if [ \"$(id -u)\" -eq 0 ]; then bash -c " + quotedScript
                + "; else sudo -n bash -c " + quotedScript + "; fi";

        int sshPort = cloudSshConn.getPort() != null ? cloudSshConn.getPort() : 22;

        ScriptResult result = JschUtils.executeScriptJsch(
                instanceDetails.getPublicIps(),
                cloudSshConn.getUsername(),
                cloudSshConn.getPassword(),
                sshPort,
                command
        );

        if (result.isSuccess()) {
            networkQualityService.revokeAgentCredential(vpsId);
            instanceDetails.setMonitorInstalled(false);
            instanceDetails.setLastHeartbeat(null);
            oracleInstanceDetailRepository.save(instanceDetails);
            return "资源与网络探针已停止并移除，专用凭据已撤销";
        } else {
            throw new RuntimeException("探针卸载未完成，请检查实例上的服务状态后重试");
        }
    }

    private String installationError(String error) {
        if (error != null && error.contains("需要 Python 3")) {
            return "网络探针需要 Python 3.6 或更新版本，请在实例上安装后重试";
        }
        if (error != null && error.contains("需要 root 权限")) {
            return "安装监控探针需要使用 root SSH 账户";
        }
        if (error != null && error.contains("需要运行中的 systemd")) {
            return "安装监控探针需要运行中的 systemd";
        }
        return "探针安装未完成，请检查实例上的 Python 3、systemd 和 SSH 配置";
    }
}

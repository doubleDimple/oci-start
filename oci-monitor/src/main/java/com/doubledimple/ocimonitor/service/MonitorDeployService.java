package com.doubledimple.ocimonitor.service;

import com.doubledimple.dao.entity.CloudSshConn;
import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.repository.CloudSshConnRepository;
import com.doubledimple.dao.repository.OracleInstanceDetailRepository;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ocicommon.param.ScriptResult;
import com.doubledimple.ocicommon.utils.JschUtils;
import lombok.extern.slf4j.Slf4j;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Service;

import javax.annotation.Resource;
import java.util.Date;
import java.util.Optional;

import static com.doubledimple.ocicommon.utils.IpUtils.getPublicIp2;

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

    @Resource
    CloudSshConnRepository cloudSshConnRepository;

    @Resource
    private OracleInstanceDetailRepository oracleInstanceDetailRepository;

    @Resource
    private Environment environment;

    /**
     * 远程一键安装监控探针
     *
     * @param vpsId 目标 VPS 的数据库 ID
     * @return 安装结果描述
     */
    public ApiResponse installAgent(String vpsId) {
        InstanceDetails instanceDetails = oracleInstanceDetailRepository.findById(Long.valueOf(vpsId))
                .orElseThrow(() -> new RuntimeException("VPS实例不存在: " + vpsId));
        Optional<CloudSshConn> sshConnOpt = cloudSshConnRepository.findByInstanceId(instanceDetails.getInstanceId());
        if (!sshConnOpt.isPresent()){
            log.warn("未找到实例 [{}] 的SSH连接信息", instanceDetails.getDisplayName());
            return ApiResponse.error("未找到实例的SSH连接信息");
        }
        CloudSshConn cloudSshConn = sshConnOpt.get();
        String serverPort = environment.getProperty("server.port", "9856");
        //todo 这里getPublicIp2() 改成默认值为了测试
        //ssh -4 -N -vvv -R 127.0.0.1:19856:127.0.0.1:9856 root@159.13.43.112
        String masterUrl = String.format("http://%s:%s", getPublicIp2(), serverPort);
        String token = String.valueOf(instanceDetails.getInstanceId());
        String command = String.format(
                "curl -L -k '%s/api/monitor/download?token=%s' -o /tmp/monitor.sh && " +
                        "chmod +x /tmp/monitor.sh && " +
                        "bash /tmp/monitor.sh install && " +
                        "rm -f /tmp/monitor.sh",
                masterUrl, token
        );

        log.info("开始对 VPS [Host: {}] 执行探针安装... commond:{}", instanceDetails.getPublicIps(),command);
        int sshPort = cloudSshConn.getPort() != null ? cloudSshConn.getPort() : 22;
        ScriptResult result = JschUtils.executeScriptJsch(
                instanceDetails.getPublicIps(),
                cloudSshConn.getUsername(),
                cloudSshConn.getPassword(),
                sshPort,
                command
        );
        if (result.isSuccess()) {
            instanceDetails.setMonitorInstalled(true);
            instanceDetails.setLastHeartbeat(new Date());
            oracleInstanceDetailRepository.save(instanceDetails);
            log.info("VPS [{}] 安装指令发送成功，输出: \n{}", cloudSshConn.getHost(), result.getOutput());
            return ApiResponse.success("安装指令已发送，探针正在启动...");
        } else {
            log.error("VPS [{}] 安装失败: {}", cloudSshConn.getHost(), result.getError());
            return ApiResponse.error("安装失败");
        }
    }

    /**
     * 远程卸载监控
     */
    public String uninstallAgent(String vpsId) {

        InstanceDetails instanceDetails = oracleInstanceDetailRepository.findById(Long.valueOf(vpsId))
                .orElseThrow(() -> new RuntimeException("VPS实例不存在"));

        CloudSshConn cloudSshConn = cloudSshConnRepository.findByInstanceId(instanceDetails.getInstanceId())
                .orElseThrow(() -> new RuntimeException("SSH信息未找到"));
        String command =
                "if [ -f /usr/local/bin/vps-agent.sh ]; then " +
                        "   sudo bash /usr/local/bin/vps-agent.sh uninstall; " +
                        "else " +
                        "   sudo systemctl stop vps-agent || true; " +
                        "   sudo systemctl disable vps-agent || true; " +
                        "   sudo rm -f /etc/systemd/system/vps-agent.service /usr/local/bin/vps-agent.sh; " +
                        "   sudo systemctl daemon-reload; " +
                        "fi";

        int sshPort = cloudSshConn.getPort() != null ? cloudSshConn.getPort() : 22;

        ScriptResult result = JschUtils.executeScriptJsch(
                instanceDetails.getPublicIps(),
                cloudSshConn.getUsername(),
                cloudSshConn.getPassword(),
                sshPort,
                command
        );

        if (result.isSuccess()) {
            instanceDetails.setMonitorInstalled(false);
            instanceDetails.setLastHeartbeat(null);
            oracleInstanceDetailRepository.save(instanceDetails);
            return "卸载指令已发送";
        } else {
            throw new RuntimeException("卸载失败: " + result.getError());
        }
    }
}

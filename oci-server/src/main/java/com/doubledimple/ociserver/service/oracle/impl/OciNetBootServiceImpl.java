package com.doubledimple.ociserver.service.oracle.impl;

import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ociserver.service.message.TelegramMessageService;
import com.doubledimple.ociserver.service.oracle.OciNetBootService;
import com.doubledimple.ociserver.utils.oracle.OciUtils;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * @version 31.0.0
 * v31: 删除密码重置流程，阶段六起替换为独立的 reinstallSystem() 函数。
 *   流程：netboot菜单 → Alpine临时系统 → setup-alpine安装真实Alpine → reboot
 *        → 登录真实Alpine → apk add bash → DD脚本重装目标系统（Debian 12）
 * v30: 完整重写阶段六（netboot菜单操作）和阶段七（密码重置）。
 * v29: 修复 EFI Shell 网络命令（TFTP节点列表 + HTTP回退）
 * v28: 修复阶段二 buffer 读取问题
 *
 * #amd机器运行
 * docker run -itd --name tftp --network host -p 69:69/udp -e PUID=1111 -e PGID=1112 --restart unless-stopped cjs520/tftp-netboot:amd64
 * #arm机器运行
 * docker run -itd --name tftp --network host -p 69:69/udp -e PUID=1111 -e PGID=1112 --restart unless-stopped cjs520/tftp-netboot:arm64
 *
 * 安装了镜像的机器
 * hudi云: 38.76.204.167
 *
 */
@Service
@Slf4j
public class OciNetBootServiceImpl implements OciNetBootService {

    @Autowired
    private TelegramMessageService telegramMessageService;

    private static final String NETBOOT_HTTP_BASE  = "http://boot.netboot.xyz/ipxe";
    private static final String EFI_FILE_X86       = "amd.efi";
    private static final String EFI_FILE_ARM       = "arm.efi";
    private static final String ALPINE_CONFIG_URL  = "https://raw.githubusercontent.com/jin-gubang/public/main/setup-alpine.config";
    private static final String DD_SCRIPT_URL      = "https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh";
    private static final String ROOT_PASSWORD      = "OciStart2025";

    private static final int ESC_INTERVAL_MS = 1000;

    private static final String[] UEFI_UI_SIGNALS = {
            "Move Highlight", "Device Manager", "Boot Maintenance",
            "Select Language", "Select Entry",
    };
    private static final String[] BOOT_MGR_SUBMENU_VERIFY = { "Boot Manager Menu" };
    private static final String[] EFI_SHELL_PROMPTS = { "Shell>", "FS0:\\>", "FS0:/>" };
    private static final String BOOT_MGR_DESC = "take you to the Boot";

    @Override
    public boolean executeAutoNetBoot(Tenant tenant, InstanceDetails instanceDetails,
                                      Map<String, String> sshConfig, String privateKeyPath,
                                      String architecture) {
        for (int attempt = 1; attempt <= 3; attempt++) {
            log.info("========== 第 {}/3 次尝试 ==========", attempt);
            boolean result = doExecute(tenant, instanceDetails, sshConfig, privateKeyPath, architecture);
            if (result) return true;
            if (attempt < 3) { log.warn("本次失败，30 秒后重试..."); sleep(30_000); }
        }
        log.error("全部 3 次尝试均失败");
        return false;
    }

    private boolean doExecute(Tenant tenant, InstanceDetails instanceDetails,
                              Map<String, String> sshConfig, String privateKeyPath,
                              String architecture) {
        Process sshProcess = null;
        AtomicBoolean keepReading = new AtomicBoolean(true);
        AtomicBoolean stopEsc     = new AtomicBoolean(false);
        try {
            String target       = sshConfig.get("target");
            String proxyCommand = sshConfig.get("proxyCommand");
            String connectionId = extractConnectionId(proxyCommand);
            String proxyHost    = extractProxyHost(proxyCommand);

            String serialSshCmd = String.format(
                    "TERM=vt100 ssh -tt -i %s -o StrictHostKeyChecking=no " +
                            "-o PubkeyAcceptedKeyTypes=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa " +
                            "-o ProxyCommand='ssh -i %s -o StrictHostKeyChecking=no " +
                            "-o PubkeyAcceptedKeyTypes=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa " +
                            "-W %%h:%%p -p 443 %s@%s' %s",
                    privateKeyPath, privateKeyPath, connectionId, proxyHost, target
            );

            log.info("启动串口通道...");
            ProcessBuilder pb = new ProcessBuilder("/bin/bash", "-c", serialSshCmd);
            pb.redirectErrorStream(true);
            sshProcess = pb.start();

            OutputStream out = sshProcess.getOutputStream();
            InputStream in   = sshProcess.getInputStream();
            StringBuffer consoleBuf = new StringBuffer();
            startOutputReaderThread(in, consoleBuf, keepReading);

            log.info("串口建立，开启 ESC 后台拦截（每 {}ms）...", ESC_INTERVAL_MS);
            final OutputStream finalOut = out;
            Thread escThread = new Thread(() -> {
                try { while (!stopEsc.get()) { finalOut.write(27); finalOut.flush(); Thread.sleep(ESC_INTERVAL_MS); } }
                catch (Exception ignored) {}
            }, "esc-spammer");
            escThread.setDaemon(true);
            escThread.start();

            log.info("发送硬件 RESET 信号（同步等待）...");
            try { OciUtils.resetInstance(tenant, instanceDetails.getInstanceId()); log.info("实例硬重启完成"); }
            catch (Exception e) { log.error("重启失败", e); stopEsc.set(true); return false; }

            boolean isAmd = !"aarch64".equalsIgnoreCase(architecture);
            byte[] downArrow = {27, '[', 'B'};
            byte[] upArrow   = {27, '[', 'A'};
            byte[] enter     = {'\r'};

            // ============================================================
            //  阶段一：等待 UEFI 主菜单
            // ============================================================
            log.info("阶段一：等待 UEFI 主菜单...");
            clearBuf(consoleBuf);
            if (!waitSignalClean(consoleBuf, UEFI_UI_SIGNALS, 180_000)) {
                stopEsc.set(true);
                log.error("UEFI 主菜单未出现"); return false;
            }
            stopEsc.set(true);
            log.info("UEFI 主菜单已出现，ESC 拦截停止");

            log.info("等待 UEFI 停止重绘（最长 120 秒）...");
            waitScreenQuiet(consoleBuf, 120_000);

            // ============================================================
            //  阶段二：逐步 Down 定位 Boot Manager
            // ============================================================
            log.info("阶段二：逐步 Down 定位 Boot Manager...");
            clearBuf(consoleBuf);
            boolean foundBootMgr = false;

            for (int step = 0; step < 8; step++) {
                if (step > 0) {
                    out.write(downArrow); out.flush();
                    log.info("按 Down（第 {} 次）", step);
                }
                sleep(3000);
                String screen = getCleanScreen(consoleBuf);
                log.info("【调试-步骤{}】屏幕尾部: {}", step, tail(screen, 300));

                if (screen.contains(">Boot Manager") && !screen.contains(">Boot Maintenance Manager")) {
                    log.info("步骤 {} 命中 Boot Manager!", step);
                    foundBootMgr = true;
                    clearBuf(consoleBuf);
                    out.write(enter); out.flush();
                    break;
                }
                clearBuf(consoleBuf);
            }

            if (!foundBootMgr) { log.error("未能定位到 Boot Manager"); return false; }

            // ============================================================
            //  验证进入 Boot Manager 子菜单
            // ============================================================
            sleep(3000);
            String postCheck = getCleanScreen(consoleBuf);
            if (postCheck.contains("PEIM Loaded") || postCheck.contains("Oracle OVMF")) {
                log.error("机器意外重启"); return false;
            }

            log.info("等待 Boot Manager 子菜单验证...");
            if (!waitSignalClean(consoleBuf, BOOT_MGR_SUBMENU_VERIFY, 120_000)) {
                log.error("Boot Manager 子菜单验证失败！屏幕: {}", tail(getCleanScreen(consoleBuf), 800));
                return false;
            }
            log.info("Boot Manager 子菜单已确认进入");

            waitScreenQuiet(consoleBuf, 30_000);
            clearBuf(consoleBuf);
            sleep(3000);
            String bootMgrScreen = getCleanScreen(consoleBuf);
            log.info("【调试-Boot Manager子菜单】: {}", tail(bootMgrScreen, 500));

            // ============================================================
            //  阶段三：动态寻找 EFI Internal Shell
            // ============================================================
            log.info("阶段三：动态寻找 EFI Internal Shell...");
            // 先复位到顶
            for (int i = 0; i < 5; i++) { out.write(upArrow); out.flush(); sleep(300); }
            sleep(1000);

            boolean foundEfiShell = false;
            for (int i = 0; i < 8; i++) {
                clearBuf(consoleBuf);
                sleep(1000);
                String screen = getCleanScreen(consoleBuf);
                log.info("【调试-EFI Shell寻找第{}步】: {}", i, tail(screen, 200));
                if (screen.contains("EFI Internal Shell") && screen.contains("Device Path")) {
                    log.info("找到 EFI Internal Shell（第 {} 步）", i);
                    foundEfiShell = true;
                    clearBuf(consoleBuf);
                    out.write(enter); out.flush();
                    break;
                }
                out.write(downArrow); out.flush();
            }

            if (!foundEfiShell) {
                log.error("未能定位到 EFI Internal Shell"); return false;
            }

            // ============================================================
            //  阶段四：EFI Shell
            // ============================================================
            log.info("阶段四：等待 EFI Shell...");
            if (!waitSignalClean(consoleBuf, EFI_SHELL_PROMPTS, 30_000)) {
                log.error("未能进入 EFI Shell\n{}", tail(getCleanScreen(consoleBuf), 500)); return false;
            }
            sleep(500);
            if (getBuf(consoleBuf).contains("startup.nsh") || getBuf(consoleBuf).contains("startup.NSH")) {
                out.write(enter); out.flush();
                waitSignalClean(consoleBuf, EFI_SHELL_PROMPTS, 10_000);
            }
            log.info("成功进入 EFI Shell");
            sleep(1000);

            clearBuf(consoleBuf);
            efiCmd(out, "FS0:");
            sleep(2000);
            log.info("已切换到 FS0:");

            // ============================================================
            //  阶段五：网络配置 + 下载并启动 netboot.xyz
            // ============================================================
            log.info("阶段五：网络配置 + 下载 netboot.xyz...");

            String efiFile = isAmd ? EFI_FILE_X86 : EFI_FILE_ARM;
            String httpUrl = NETBOOT_HTTP_BASE + "/" + efiFile;

            clearBuf(consoleBuf);
            efiCmd(out, "ifconfig -l");
            sleep(5000);
            log.info("【调试-ifconfig -l】: {}", tail(getCleanScreen(consoleBuf), 500));

            clearBuf(consoleBuf);
            efiCmd(out, "ifconfig -r eth0");
            sleep(8000);
            String dhcpResult = getCleanScreen(consoleBuf);
            log.info("【调试-ifconfig -r】: {}", tail(dhcpResult, 300));

            if (dhcpResult.toLowerCase().contains("error") || dhcpResult.toLowerCase().contains("invalid")) {
                clearBuf(consoleBuf);
                efiCmd(out, "ifconfig -s eth0 dhcp");
                sleep(8000);
                log.info("【调试-ifconfig -s dhcp】: {}", tail(getCleanScreen(consoleBuf), 300));
            }

            // 先检查文件是否已存在，避免重复下载
            log.info("检查 {} 是否已存在于 FS0...", efiFile);
            clearBuf(consoleBuf);
            efiCmd(out, "ls " + efiFile);
            sleep(3000);
            String preCheck = getCleanScreen(consoleBuf);
            String preCheckLower = preCheck.toLowerCase();
            boolean downloadSuccess = preCheck.contains(efiFile)
                    && !preCheckLower.contains("file not found")
                    && !preCheckLower.contains("not specified")
                    && !preCheckLower.contains("cannot find")
                    && !preCheckLower.contains("no file")
                    && !preCheck.contains("0  " + efiFile)
                    && !preCheck.contains("0 bytes");

            if (downloadSuccess) {
                log.info("{} 已存在，跳过下载直接执行！", efiFile);
            }

            // TFTP 下载
            String currentProxyHost = extractProxyHost(proxyCommand);
            List<String> tftpIps = getPrioritizedTftpIps(currentProxyHost);
            for (String tftpIp : tftpIps) {
                if (downloadSuccess) break;
                log.info("正在尝试 TFTP 节点: {}", tftpIp);
                clearBuf(consoleBuf);
                efiCmd(out, "tftp " + tftpIp + " " + efiFile);
                boolean tftpOk = waitSignalClean(consoleBuf,
                        new String[]{"FS0:\\>", "FS0:>", "Shell>", "Kb\r\nFS0"}, 1800_000);
                String tftpResult = getCleanScreen(consoleBuf);
                log.info("【调试-tftp结果 ({})】: {}", tftpIp, tail(tftpResult, 300));
                String tftpLower = tftpResult.toLowerCase();
                boolean hasTftpError = tftpLower.contains("error") || tftpLower.contains("time out")
                        || tftpLower.contains("timeout") || tftpLower.contains("unable")
                        || tftpLower.contains("not recognized") || tftpLower.contains("invalid");
                if (tftpOk && !hasTftpError) {
                    clearBuf(consoleBuf);
                    efiCmd(out, "ls " + efiFile);
                    sleep(3000);
                    String lsResult = getCleanScreen(consoleBuf);
                    String lsLower = lsResult.toLowerCase();
                    log.info("【调试-ls结果】: {}", tail(lsResult, 200));
                    boolean lsOk = lsResult.contains(efiFile) && !lsLower.contains("file not found")
                            && !lsLower.contains("not specified") && !lsLower.contains("cannot find")
                            && !lsLower.contains("no file");
                    if (lsOk) { log.info("TFTP 下载成功！节点: {}", tftpIp); downloadSuccess = true; break; }
                }
                log.warn("节点 {} 下载失败，尝试下一个...", tftpIp);
            }

            if (!downloadSuccess) {
                log.error("TFTP 与 HTTP 下载均失败");
                return false;
            }

            // 执行 efi，等待 netboot 菜单
            log.info("启动 {}...", efiFile);
            clearBuf(consoleBuf);
            efiCmd(out, efiFile);

            log.info("等待 netboot.xyz 菜单完全加载（最多 180 秒）...");
            clearBuf(consoleBuf);
            if (!waitSignalClean(consoleBuf, new String[]{"Linux Network Installs"}, 180_000)) {
                log.info("【调试-efi加载结果】: {}", tail(getCleanScreen(consoleBuf), 800));
                log.error("netboot.xyz 菜单未出现"); return false;
            }
            log.info("netboot.xyz 菜单已出现！");

            // 等菜单彻底渲染完
            sleep(5000);
            clearBuf(consoleBuf);
            sleep(3000);
            log.info("【调试-netboot主菜单】: {}", tail(getCleanScreen(consoleBuf), 500));

            // ============================================================
            //  阶段六：重装系统
            // ============================================================
            return reinstallSystem(out, consoleBuf, downArrow, upArrow, enter, instanceDetails);

        } catch (Exception e) {
            log.error("致命错误", e); return false;
        } finally {
            stopEsc.set(true); keepReading.set(false);
            if (sshProcess != null && sshProcess.isAlive()) sshProcess.destroyForcibly();
        }
    }

    // ============================================================
    //  阶段六：重装系统
    //
    //  入口条件：netboot.xyz 主菜单已出现，光标在 "Boot from local hdd"
    //
    //  步骤一：菜单导航到 Alpine 临时系统
    //    主菜单（从截图确认）：
    //      Boot from local hdd    ← 默认高亮
    //      Linux Network Installs ← Down×1
    //      Live CDs
    //      BSD Installs
    //      Windows
    //      Utilities (UEFI)
    //    → 光标复位到顶 → Down 动态寻找 "Linux Network Installs" → 回车
    //    → Down 动态寻找 "Alpine Linux" → 回车
    //    → 光标顶到顶直接回车（选第一个 Alpine netboot 选项）
    //    → 等待 "login:" 出现（Alpine live 启动，约 2~5 分钟）
    //    → 发送 "root" 无密码登录
    //
    //  步骤二：Alpine 临时系统安装真实 Alpine
    //    → wget 下载 setup-alpine.config
    //    → setup-alpine -f setup-alpine.config
    //    → 输入 root 密码两遍（ROOT_PASSWORD）
    //    → 跳过 User 创建（直接回车）
    //    → 确认擦盘（输入 y）
    //    → 等待安装完成 → 执行 reboot
    //    → 等待真实 Alpine 启动并出现 "login:"
    //
    //  步骤三：真实 Alpine 登录 → apk add bash → DD 重装
    //    → root + ROOT_PASSWORD 登录
    //    → apk update && apk add bash
    //    → bash reinstall.sh --ci debian 12
    //    → 等待完成（最多 40 分钟）→ Telegram 通知
    // ============================================================
    private boolean reinstallSystem(OutputStream out, StringBuffer consoleBuf,
                                    byte[] downArrow, byte[] upArrow, byte[] enter,
                                    InstanceDetails instanceDetails) throws Exception {

        log.info("[重装-1] netboot 菜单导航...");
        // waitScreenQuiet 对倒计时菜单永远超时，改为固定等待让菜单稳定
        // 倒计时每秒刷新，等5秒让最后一次刷新完成后再操作
        sleep(5000);
        clearBuf(consoleBuf);
        sleep(3000);  // 再等3秒，确保没有新的刷新
        log.info("[重装-1] 开始复位光标...");

        // 光标复位到顶部
        for (int i = 0; i < 10; i++) { out.write(upArrow); out.flush(); sleep(300); }
        sleep(2000);

        // 向下动态找 Linux Network Installs
        log.info("[重装-1] 寻找 Linux Network Installs...");
        boolean foundLinux = false;
        for (int i = 0; i < 10; i++) {
            clearBuf(consoleBuf);
            out.write(downArrow); out.flush();
            sleep(1500);
            if (getCleanScreen(consoleBuf).toLowerCase().contains("linux network installs")) {
                log.info("[重装-1] 找到 Linux Network Installs（第 {} 步）", i + 1);
                foundLinux = true;
                sleep(500);
                out.write(enter); out.flush();
                break;
            }
        }
        if (!foundLinux) { log.error("[重装-1] 未找到 Linux Network Installs"); return false; }

        // 等待发行版列表渲染，光标复位
        log.info("[重装-1] 等待发行版列表加载（固定 5 秒）...");
        sleep(5000);
        clearBuf(consoleBuf);
        sleep(2000);
        for (int i = 0; i < 5; i++) { out.write(upArrow); out.flush(); sleep(150); }
        sleep(1000);

        // 向下动态找 Alpine Linux
        log.info("[重装-1] 寻找 Alpine Linux...");
        boolean foundAlpine = false;
        for (int i = 0; i < 15; i++) {
            clearBuf(consoleBuf);
            out.write(downArrow); out.flush();
            sleep(1500);
            if (getCleanScreen(consoleBuf).toLowerCase().contains("alpine")) {
                log.info("[重装-1] 找到 Alpine Linux（第 {} 步）", i + 1);
                foundAlpine = true;
                out.write(enter); out.flush();
                break;
            }
        }
        if (!foundAlpine) { log.error("[重装-1] 未找到 Alpine Linux"); return false; }

        // 等待 Alpine 选项列表渲染，光标顶到顶，选第一个
        log.info("[重装-1] 等待 Alpine 选项列表渲染...");
        waitScreenQuiet(consoleBuf, 15_000);
        for (int i = 0; i < 5; i++) { out.write(upArrow); out.flush(); sleep(150); }
        sleep(1000);
        log.info("[重装-1] 选择第一个 Alpine 选项...");
        clearBuf(consoleBuf);
        out.write(enter); out.flush();

        // 等待 Alpine live 启动出现登录提示（约 2~5 分钟）
        log.info("[重装-1] 等待 Alpine 临时系统启动（最多 5 分钟）...");
        if (!waitSignalClean(consoleBuf, new String[]{"login:", "localhost login", "alpine login"}, 300_000)) {
            log.error("[重装-1] Alpine 未出现登录提示\n{}", tail(getCleanScreen(consoleBuf), 500));
            return false;
        }
        log.info("[重装-1] Alpine 登录提示已出现！");
        sleep(1000);
        clearBuf(consoleBuf);
        sendLine(out, "root");
        if (!waitSignalClean(consoleBuf, new String[]{"#", "~#", "localhost:~"}, 15_000)) {
            log.warn("[重装-1] 未检测到 shell 提示符，继续...");
        }
        log.info("[重装-1] 成功登录 Alpine 临时系统！");

        // ── 步骤二：setup-alpine 安装真实 Alpine → reboot ──
        log.info("[重装-2] 下载 setup-alpine.config...");
        sleep(1000);
        clearBuf(consoleBuf);
        sendLine(out, "wget --no-check-certificate -qO setup-alpine.config \"" + ALPINE_CONFIG_URL + "\"");
        if (!waitSignalClean(consoleBuf, new String[]{"#", "~#", "localhost:~"}, 60_000)) {
            log.warn("[重装-2] wget 未返回提示符，继续...");
        }

        log.info("[重装-2] 开始 setup-alpine...");
        clearBuf(consoleBuf);
        sendLine(out, "setup-alpine -f setup-alpine.config");

        log.info("[重装-2] 等待 root 密码提示...");
        if (!waitSignal(consoleBuf, new String[]{"New password", "password for root", "Changing password"}, 60_000)) {
            log.error("[重装-2] 未出现 root 密码提示"); return false;
        }
        sleep(500);
        log.info("[重装-2] 输入 root 密码第 1 遍");
        sendLine(out, ROOT_PASSWORD);

        if (!waitSignal(consoleBuf, new String[]{"Retype", "again", "Re-enter"}, 15_000)) {
            log.warn("[重装-2] 未检测到第 2 遍密码提示，继续...");
        }
        sleep(500);
        log.info("[重装-2] 输入 root 密码第 2 遍");
        sendLine(out, ROOT_PASSWORD);

        // 跳过 User 创建
        if (waitSignal(consoleBuf, new String[]{"Setup a user", "loginname"}, 20_000)) {
            sleep(500);
            log.info("[重装-2] 跳过 User 创建（直接回车）");
            sendLine(out, "");
        }

        // 等待磁盘擦除确认
        log.info("[重装-2] 等待磁盘擦除确认（WARNING: Erase）...");
        if (!waitSignal(consoleBuf, new String[]{"WARNING: Erase", "Erase the above disk", "continue? (y/n)"}, 120_000)) {
            log.error("[重装-2] 未出现磁盘擦除确认"); return false;
        }
        sleep(500);
        log.info("[重装-2] 确认擦盘（y）");
        sendLine(out, "y");

        // 等待安装完成
        log.info("[重装-2] 等待 Alpine 安装完成（最多 10 分钟）...");
        if (!waitSignal(consoleBuf,
                new String[]{"Installation is complete", "Please reboot", "reboot", "installation complete"}, 600_000)) {
            log.error("[重装-2] Alpine 安装超时"); return false;
        }
        log.info("[重装-2] Alpine 安装完成，执行 reboot...");
        sleep(2000);
        clearBuf(consoleBuf);
        sendLine(out, "reboot");

        // 等待真实 Alpine 启动
        log.info("[重装-2] 等待真实 Alpine 启动（最多 5 分钟）...");
        if (!waitSignalClean(consoleBuf, new String[]{"login:", "localhost login", "alpine login"}, 300_000)) {
            log.error("[重装-2] 真实 Alpine 未出现登录提示"); return false;
        }
        log.info("[重装-2] 真实 Alpine 已启动！");

        // ── 步骤三：登录真实 Alpine → apk add bash → DD 重装 ──
        log.info("[重装-3] 登录真实 Alpine...");
        sleep(1000);
        clearBuf(consoleBuf);
        sendLine(out, "root");
        if (!waitSignal(consoleBuf, new String[]{"Password", "password"}, 15_000)) {
            log.warn("[重装-3] 未出现密码提示，继续...");
        }
        sleep(500);
        sendLine(out, ROOT_PASSWORD);
        if (!waitSignalClean(consoleBuf, new String[]{"#", "~#", "localhost:~"}, 15_000)) {
            log.error("[重装-3] 登录真实 Alpine 失败"); return false;
        }
        log.info("[重装-3] 登录成功！");
        sleep(1000);

        // 确保sshd正常运行
        clearBuf(consoleBuf);
        sendLine(out, "rc-service sshd restart");
        sleep(3000);
        log.info("[重装] sshd 已重启");

        // 清理 reinstall 遗留的 EFI 启动项
        clearBuf(consoleBuf);
        sendLine(out, "efibootmgr | grep -i reinstall | grep -oP 'Boot\\K[0-9A-F]+' | xargs -I{} efibootmgr -b {} -B 2>/dev/null");
        sleep(2000);
        log.info("[重装] 清理 reinstall EFI 启动项完成");

        //todo 此处可以不需要处理了,用户自己登录处理吧
        //executeDd(consoleBuf,out);



        // 清理 reinstall 遗留的 EFI 启动项，防止下次 reboot 误启动
        clearBuf(consoleBuf);
        sendLine(out, "efibootmgr | grep -i reinstall | grep -oP 'Boot\\K[0-9A-F]+' | xargs -I{} efibootmgr -b {} -B 2>/dev/null");
        sleep(2000);
        log.info("[重装] 清理 reinstall EFI 启动项完成");


        log.info("================================================");
        log.info("系统重装完成！实例: {}", instanceDetails.getInstanceId());
        log.info("目标系统: Debian 12 / Root 密码: {}", ROOT_PASSWORD);
        log.info("================================================");

        try {
            telegramMessageService.sendMessageTemplate(String.format(
                    "————系统重装通知————\n实例【%s】\n重装完成！\nRoot密码：%s",
                    instanceDetails.getInstanceId(), ROOT_PASSWORD));
        } catch (Exception ignored) {}

        return true;
    }


    /**
    * @Description: 系统dd
    * @Param: [java.lang.StringBuffer, java.io.OutputStream]
    * @return: void
    * @Author: doubleDimple
    * @Date: 3/30/26 6:47 PM
    */
    private void executeDd(StringBuffer consoleBuf,OutputStream out) {
        try {
            log.info("[重装-3] apk update...");
            clearBuf(consoleBuf);
            sendLine(out, "apk update");
            if (!waitSignalClean(consoleBuf, new String[]{"OK:", "#"}, 60_000)) {
                log.warn("[重装-3] apk update 未返回正常提示，继续...");
            }
            sleep(1000);

            log.info("[重装-3] apk add bash...");
            clearBuf(consoleBuf);
            sendLine(out, "apk add bash");
            if (!waitSignalClean(consoleBuf, new String[]{"OK:", "Installing", "#"}, 60_000)) {
                log.warn("[重装-3] apk add bash 未返回正常提示，继续...");
            }
            sleep(1000);

            log.info("[重装-3] 运行 reinstall.sh（Debian 12）...");
            clearBuf(consoleBuf);
            sendLine(out, "bash <(wget --no-check-certificate -qO- \"" + DD_SCRIPT_URL + "\") --ci debian 12");

            log.info("[重装-3] 等待 reinstall.sh 密码提示...");
            if (waitSignal(consoleBuf, new String[]{"PROMPT PASSWORD", "Password:", "password:"}, 120_000)) {
                sleep(500);
                log.info("[重装-3] 输入目标系统密码");
                sendLine(out, ROOT_PASSWORD);
                if (waitSignal(consoleBuf, new String[]{"Confirm", "confirm", "again", "Retype"}, 15_000)) {
                    sleep(500);
                    log.info("[重装-3] 确认密码");
                    sendLine(out, ROOT_PASSWORD);
                }
            }
            log.info("[重装-3] 等待 reinstall.sh 准备完成...");
            if (waitSignal(consoleBuf, new String[]{"Reboot to start", "hostname:~#", "#"}, 300_000)) {
                sleep(2000);
                log.info("[重装-3] reinstall.sh 准备完成，执行 reboot...");
                clearBuf(consoleBuf);
                sendLine(out, "reboot");
            }
            log.info("[重装-3] 等待 Debian 12 安装完成（最多 40 分钟）...");
            boolean ddDone = waitSignal(consoleBuf,
                    new String[]{"Rebooting", "reboot", "All done", "Done!", "finished", "login:"}, 2400_000);
            if (!ddDone) {
                log.warn("[重装-3] DD 脚本超时，可能已完成重启");
            } else {
                log.info("[重装-3] DD 完成，系统即将重启！");
            }
        } catch (Exception e) {
            log.error("执行 DD 脚本异常", e.getMessage(),e);
        }

    }

    // ===================== 等待屏幕安静 =====================
    private boolean waitScreenQuiet(StringBuffer consoleBuf, long timeoutMs) {
        long start = System.currentTimeMillis();
        int quietCount = 0;
        while (System.currentTimeMillis() - start < timeoutMs) {
            clearBuf(consoleBuf); sleep(5000);
            int newLen = getBuf(consoleBuf).length();
            log.info("【重绘检测】5秒内新数据: {} 字节", newLen);
            if (newLen < 100) { quietCount++; if (quietCount >= 2) { log.info("UEFI 已稳定"); return true; } }
            else { quietCount = 0; }
        }
        log.warn("等待屏幕稳定超时"); return false;
    }

    // ===================== 解析 EFI Shell 偏移 =====================
    private int parseEfiShellOffset(String screenContent) {
        int def = 2;
        try {
            String clean = screenContent.replaceAll("\u001B\\[[;\\d]*[a-zA-Z]", "");
            int menuStart = clean.indexOf("Boot Manager Menu");
            if (menuStart == -1) return def;
            String after = clean.substring(menuStart);
            String[] items = {"ubuntu", "ORACLE BlockVolume", "EFI Internal Shell", "UEFI PXEv4"};
            List<int[]> pos = new ArrayList<>();
            for (int i = 0; i < items.length; i++) { int p = after.indexOf(items[i]); if (p != -1) pos.add(new int[]{i, p}); }
            pos.sort((a, b) -> Integer.compare(a[1], b[1]));
            for (int r = 0; r < pos.size(); r++) if (pos.get(r)[0] == 2) return r;
            return def;
        } catch (Exception e) { return def; }
    }

    // ===================== 工具方法 =====================
    private String getCleanScreen(StringBuffer buf) {
        String raw; synchronized(buf) { raw = buf.toString(); }
        return raw.replaceAll("\u001B\\[[;\\d]*[a-zA-Z]", "").replaceAll("[ \\t]+", " ");
    }
    private void efiCmd(OutputStream out, String cmd) throws Exception {
        log.info("[EFI] > {}", cmd); out.write((cmd + "\r\n").getBytes()); out.flush();
    }
    private void sendLine(OutputStream out, String line) throws Exception {
        log.info("[Shell] > {}", line.isEmpty() ? "(回车)" : line); out.write((line + "\n").getBytes()); out.flush();
    }
    private boolean waitSignal(StringBuffer cb, String[] sigs, long t) throws Exception {
        long s = System.currentTimeMillis();
        while (System.currentTimeMillis() - s < t) { String c = getBuf(cb); for (String si : sigs) if (c.contains(si)) { log.info("检测到: [{}]", si); return true; } sleep(200); }
        log.warn("超时: {}", Arrays.toString(sigs)); return false;
    }
    private boolean waitSignalClean(StringBuffer cb, String[] sigs, long t) throws Exception {
        long s = System.currentTimeMillis();
        while (System.currentTimeMillis() - s < t) { String r = getBuf(cb); String c = r.replaceAll("\u001B\\[[;\\d]*[a-zA-Z]", ""); for (String si : sigs) if (r.contains(si) || c.contains(si)) { log.info("检测到: [{}]", si); return true; } sleep(200); }
        log.warn("超时: {}", Arrays.toString(sigs)); return false;
    }
    private void clearBuf(StringBuffer buf) { synchronized (buf) { buf.setLength(0); } }
    private String getBuf(StringBuffer buf) { synchronized (buf) { return buf.toString(); } }
    private String tail(String s, int n) { return (s == null || s.length() <= n) ? s : "..." + s.substring(s.length() - n); }
    private void sleep(long ms) { try { Thread.sleep(ms); } catch (InterruptedException ignored) {} }

    private void startOutputReaderThread(InputStream in, StringBuffer buffer, AtomicBoolean keepReading) {
        new Thread(() -> {
            try { byte[] buf = new byte[4096]; while (keepReading.get()) { int a = in.available(); if (a > 0) { int l = in.read(buf, 0, Math.min(buf.length, a)); if (l > 0) { String ch = new String(buf, 0, l); synchronized (buffer) { buffer.append(ch); if (buffer.length() > 100_000) buffer.delete(0, 50_000); } log.info("[串口原始] {}", ch.replace("\n", "\\n").replace("\r", "\\r")); } } else { Thread.sleep(50); } } }
            catch (Exception e) { if (keepReading.get()) log.error("串口中断", e); }
        }, "console-reader").start();
    }

    private String extractConnectionId(String proxyCommand) {
        if (proxyCommand == null) return null;
        for (String p : proxyCommand.split("\\s+")) if (p.startsWith("ocid1.instanceconsoleconnection")) return p.split("@")[0];
        return null;
    }
    private String extractProxyHost(String proxyCommand) {
        if (proxyCommand == null) return null;
        for (String p : proxyCommand.split("\\s+")) if (p.contains("@instance-console") && p.contains(".oci.oraclecloud.com")) return p.split("@")[1];
        return null;
    }

    // ===================== TFTP 节点管理 =====================
    private static class TftpNode {
        String ip; String regionKeyword; String desc;
        TftpNode(String ip, String regionKeyword, String desc) {
            this.ip = ip; this.regionKeyword = regionKeyword; this.desc = desc;
        }
    }

    private static final List<TftpNode> TFTP_NODES = Arrays.asList(
            new TftpNode("38.76.204.167", "ap-tokyo", "hudi云")
    );

    private List<String> getPrioritizedTftpIps(String proxyHost) {
        List<String> sortedIps = new ArrayList<>();
        if (proxyHost == null) { TFTP_NODES.forEach(n -> sortedIps.add(n.ip)); return sortedIps; }
        String currentRegion = proxyHost.toLowerCase();
        for (TftpNode node : TFTP_NODES) {
            if (currentRegion.contains(node.regionKeyword)) {
                sortedIps.add(node.ip);
                log.info("匹配到最优 TFTP 节点: {} ({})", node.ip, node.desc);
            }
        }
        for (TftpNode node : TFTP_NODES) { if (!sortedIps.contains(node.ip)) sortedIps.add(node.ip); }
        return sortedIps;
    }
}
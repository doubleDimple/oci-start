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
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * @version 39.0.0
 * v39: 重写 executeDd：禁止 ash 下 bash <(wget) 进程替换；改 wget 落盘 +
 *      reinstall.sh debian 12 --username/--password 非交互；完成标志对齐官方
 *      「Reboot to start the reinstallation」；返回 boolean，失败不假成功。
 * v38: 重装后 SSH Auth fail：Alpine 默认 PermitRootLogin=prohibit-password，
 *      串口密码可登但 SSH 拒 root 密码；登录后写 sshd 配置并重启。
 *      去掉无效 efibootmgr。
 * v37: 修复 netboot.xyz/iPXE 菜单高亮永远为空导致 reinstallSystem 定位失败：
 *   Oracle 串口上 iPXE 几乎不发 reverse video；Down/Up 时只重绘「旧项+新项」，
 *   项与项之间是大片空格。取短重绘最后一项作为当前选中。
 *   Alpine 增加 fixedOffset=1 底线（AlmaLinux=0 → Alpine=1）。
 * v36: 去掉写死 TFTP_NODES；救援前由用户可选填写 TFTP，有则优先，无则/失败则 HTTP。
 * v35: TFTP 失败后 HTTP 公网回退下载 netboot.xyz.efi（boot.netboot.xyz 无 amd.efi）；
 *      TFTP 单节点超时改为 90s；抽 efiFileExists / hasDownloadError。
 * v34: 按 Oracle OVMF 1.6.4 真实串口格式修菜单定位：
 *   - 主菜单：帮助文案 "This selection will take you to the Boot Manager"
 *   - Boot Manager 子菜单：Select Entry + 当前项名 + Device Path
 *   - EFI Shell：Device Path 含 Shell GUID 7C04A583
 *   - 前端 ">" 是子菜单标记不是光标，禁止再当选中项
 * v33: 修复“未进 UEFI 却开始点 Boot Manager”：
 *   - 一旦检测到 UEFI 立即停 ESC（续按 ESC 会退出 Setup 掉进系统）
 *   - waitUefiMenuStable：安静时仍须保留 UEFI 特征；cloud-init/login 视为失败
 *   - 阶段二前再次确认仍在 Setup；Boot Manager 增加固定偏移 fallback
 * v32: 修复菜单无法精准定位：改为高亮/光标检测（reverse video / ">" 前缀），
 *      禁止用整屏 contains(菜单项) 判断选中（全量重绘时会误回车）。
 *      统一 selectMenuItem：复位顶部 → 逐步 Down 匹配高亮 → 可选固定偏移 fallback。
 * v31: 删除密码重置流程，阶段六起替换为独立的 reinstallSystem() 函数。
 *   流程：netboot菜单 → Alpine临时系统 → setup-alpine安装真实Alpine → reboot
 *        → 登录真实Alpine → 开启 SSH root 密码登录（终点为 Alpine；DD 可选）
 *
 * #amd机器运行
 * docker run -itd --name tftp --network host -p 69:69/udp -e PUID=1111 -e PGID=1112 --restart unless-stopped cjs520/tftp-netboot:amd64
 * #arm机器运行
 * docker run -itd --name tftp --network host -p 69:69/udp -e PUID=1111 -e PGID=1112 --restart unless-stopped cjs520/tftp-netboot:arm64
 *
 * 自建 TFTP 示例（可选，救援弹窗填写）：
 * docker run -itd --name tftp --network host -p 69:69/udp ...
 * 节点上需提供 amd.efi / arm.efi
 *
 */
@Service
@Slf4j
public class OciNetBootServiceImpl implements OciNetBootService {

    @Autowired
    private TelegramMessageService telegramMessageService;

    /** 本地保存名（TFTP 自建节点常用 amd.efi / arm.efi） */
    private static final String EFI_FILE_X86       = "netboot.xyz.efi";
    private static final String EFI_FILE_ARM       = "netboot.xyz-arm64.efi";
    /**
     * 公网 HTTP 回退（对照 https://netboot.xyz/downloads/ UEFI 列表）。
     * 自建 TFTP 的 amd.efi/arm.efi 公网上不存在。
     *
     * x86 优先级：
     *  1) netboot.xyz.efi      — 标准 DHCP，内置 iPXE 网卡驱动（首选）
     *  2) netboot.xyz-snp.efi  — 走 UEFI SNP 协议，虚拟机/部分网卡更稳
     *  3) netboot.xyz-snponly.efi — 仅当前链路设备
     *  4) netboot.xyz-legacy.efi — 去掉 USB 网卡驱动，保键盘（少见）
     * 不用：*.efi.dsk / ISO / IMG（那是软盘或安装介质，不是 Shell 里 load 的）
     *
     * ARM 同理：arm64.efi → arm64-snp → arm64-snponly
     */
    private static final String[] HTTP_URLS_X86 = {
            "http://boot.netboot.xyz/ipxe/netboot.xyz.efi",
            "http://boot.netboot.xyz/ipxe/netboot.xyz-snp.efi",
            "http://boot.netboot.xyz/ipxe/netboot.xyz-snponly.efi",
            "http://boot.netboot.xyz/ipxe/netboot.xyz-legacy.efi",
    };
    private static final String[] HTTP_URLS_ARM = {
            "http://boot.netboot.xyz/ipxe/netboot.xyz-arm64.efi",
            "http://boot.netboot.xyz/ipxe/netboot.xyz-arm64-snp.efi",
            "http://boot.netboot.xyz/ipxe/netboot.xyz-arm64-snponly.efi",
    };
    private static final String ALPINE_CONFIG_URL  = "https://raw.githubusercontent.com/jin-gubang/public/main/setup-alpine.config";
    private static final String DD_SCRIPT_URL      = "https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh";


    /** ESC 过慢易错过 POST 窗口；过快在进 Setup 后若未及时停止会 ESC 退出 */
    private static final int ESC_INTERVAL_MS = 400;

    private static final String[] UEFI_UI_SIGNALS = {
            "Move Highlight", "Device Manager", "Boot Maintenance",
            "Select Language", "Select Entry", "Boot Manager",
    };
    /**
     * 系统已启动特征：出现则说明已不在 UEFI Setup。
     * 注意：不要用单独的 "ubuntu"（Boot Manager 里常有 ubuntu 启动项）。
     */
    private static final String[] OS_BOOT_SIGNALS = {
            "cloud-init", "Cloud-init v.", "DataSourceOracle",
            "login:", "Debian GNU/Linux",
            "Started Update UTMP", "Reached target",
            "systemd[1]:", "Kernel command line",
            "Welcome to Ubuntu", "Ubuntu .* tty",
    };
    private static final String[] BOOT_MGR_SUBMENU_VERIFY = { "Boot Manager Menu" };
    private static final String[] EFI_SHELL_PROMPTS = { "Shell>", "FS0:\\>", "FS0:/>" };
    /** OVMF 主菜单帮助文案片段：选中 Boot Manager 时出现 */
    private static final String BOOT_MGR_HELP = "take you to the Boot Manager";
    private static final String BOOT_MAINT_HELP = "take you to the Boot Maintenance";
    private static final String DEVICE_MGR_HELP = "take you to the Device Manager";
    private static final String LANG_HELP = "change the language";
    /** EFI Internal Shell 的 FvFile GUID（Oracle OVMF 串口 Device Path 中可见） */
    private static final String EFI_SHELL_FILE_GUID = "7C04A583";

    /**
     * 菜单选中检测（针对 Oracle OVMF 串口 + iPXE）：
     * - OVMF 主菜单：右侧帮助文案（This selection will take you to ...）
     * - OVMF Boot Manager：Select Entry + 项名 + Device Path
     * - EFI Shell：Device Path 含 Shell GUID
     * - iPXE：reverse video（部分环境有）；Oracle 串口上常无色，改用「短重绘最后一项」
     * 注意：OVMF 行首 ">" 是「有子菜单」标记，不是光标！
     */
    private static final Pattern ANSI_CSI = Pattern.compile("\\u001B\\[[?;0-9]*[a-zA-Z]");
    private static final Pattern ANSI_OTHER = Pattern.compile("\\u001B[\\(\\)].|\\u001B.");
    /** reverse / inverse video 包裹的文本 (CSI ...7m) — iPXE/netboot */
    private static final Pattern REVERSE_VIDEO = Pattern.compile(
            "\\u001B\\[[0-9;]*7[0-9;]*m([^\\u001B]{1,120}?)\\u001B\\[[0-9;]*m");
    /** 彩色背景高亮 */
    private static final Pattern BG_HIGHLIGHT = Pattern.compile(
            "\\u001B\\[[0-9;]*4[1-6][0-9;]*m([^\\u001B]{1,120}?)\\u001B\\[[0-9;]*m");
    /**
     * OVMF Boot Manager 子菜单：当前选中项在帮助区
     * 例：Select Entry    EFI Internal Shell    Device Path : Fv(...7C04A583...)
     */
    private static final Pattern OVMF_SELECT_ENTRY = Pattern.compile(
            "Select Entry\\s+(.{1,100}?)\\s+Device Path",
            Pattern.CASE_INSENSITIVE | Pattern.DOTALL);

    @Override
    public boolean executeAutoNetBoot(Tenant tenant, InstanceDetails instanceDetails,
                                      Map<String, String> sshConfig, String privateKeyPath,
                                      String architecture, String tftpHost) {
        List<String> tftpIps = parseUserTftpHosts(tftpHost);
        if (tftpIps.isEmpty()) {
            log.info("未指定 TFTP 节点，将直接使用公网 HTTP 下载 netboot.xyz");
        } else {
            log.info("用户指定 TFTP 节点（优先）: {}", tftpIps);
        }
        for (int attempt = 1; attempt <= 3; attempt++) {
            log.info("========== 第 {}/3 次尝试 ==========", attempt);
            boolean result = doExecute(tenant, instanceDetails, sshConfig, privateKeyPath, architecture, tftpIps);
            if (result) return true;
            if (attempt < 3) { log.warn("本次失败，30 秒后重试..."); sleep(30_000); }
        }
        log.error("全部 3 次尝试均失败");
        return false;
    }

    private boolean doExecute(Tenant tenant, InstanceDetails instanceDetails,
                              Map<String, String> sshConfig, String privateKeyPath,
                              String architecture, List<String> tftpIps) {
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
            //  阶段一：等待 UEFI 主菜单（命中后立刻停 ESC，防止 ESC 退出 Setup）
            // ============================================================
            log.info("阶段一：等待 UEFI 主菜单...");
            clearBuf(consoleBuf);
            if (!waitForUefiAndStopEsc(consoleBuf, stopEsc, 180_000)) {
                stopEsc.set(true);
                log.error("UEFI 主菜单未出现（或已掉进系统）。尾部: {}",
                        tail(getCleanScreen(consoleBuf), 500));
                return false;
            }
            log.info("UEFI 主菜单已出现，ESC 已停止");

            log.info("等待 UEFI 菜单稳定（须仍含 Setup 特征，最长 60 秒）...");
            if (!waitUefiMenuStable(consoleBuf, out, upArrow, 60_000)) {
                log.error("UEFI 未稳定或已进入操作系统。尾部: {}",
                        tail(getCleanScreen(consoleBuf), 500));
                return false;
            }

            // 进阶段二前再确认一次，避免在 Ubuntu 里空按方向键
            if (!ensureStillInUefi(consoleBuf, out, upArrow)) {
                log.error("阶段二前确认失败：当前不在 UEFI Setup");
                return false;
            }

            // ============================================================
            //  阶段二：定位 Boot Manager
            //  OVMF 主菜单顺序：Select Language(0) → Device Manager(1) → Boot Manager(2)
            //  选中判据：帮助文案 "take you to the Boot Manager"（非 Maintenance）
            // ============================================================
            log.info("阶段二：定位 Boot Manager...");
            boolean foundBootMgr = selectMenuItem(
                    out, consoleBuf, downArrow, upArrow, enter,
                    "Boot Manager",
                    new String[]{"boot manager"},
                    "maintenance",
                    10,
                    2,
                    1500
            );
            if (!foundBootMgr) {
                log.error("未能定位到 Boot Manager");
                return false;
            }

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
            sleep(2000);
            String bootMgrScreen = getCleanScreen(consoleBuf);
            log.info("【调试-Boot Manager子菜单】: {}", tail(bootMgrScreen, 500));

            // ============================================================
            //  阶段三：定位 EFI Internal Shell
            //  选中判据：Select Entry 后项名 / Device Path 含 Shell GUID 7C04A583
            //  常见顺序：ubuntu(0) → BlockVolume(1) → EFI Internal Shell(2) → PXE(3)
            // ============================================================
            log.info("阶段三：定位 EFI Internal Shell...");
            boolean foundEfiShell = selectMenuItem(
                    out, consoleBuf, downArrow, upArrow, enter,
                    "EFI Internal Shell",
                    new String[]{"efi internal shell", "internal shell"},
                    null,
                    16,
                    2,
                    1200
            );
            if (!foundEfiShell) {
                log.error("未能定位到 EFI Internal Shell");
                return false;
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

            // 本地保存名；公网 HTTP 用官方文件名（见 HTTP_URLS_*）
            String efiFile = isAmd ? EFI_FILE_X86 : EFI_FILE_ARM;
            String[] httpUrls = isAmd ? HTTP_URLS_X86 : HTTP_URLS_ARM;

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
            boolean downloadSuccess = efiFileExists(out, consoleBuf, efiFile);
            if (downloadSuccess) {
                log.info("{} 已存在，跳过下载直接执行！", efiFile);
            }

            // ── TFTP：仅当用户填写了节点时优先尝试（文件名 amd.efi / arm.efi）──
            if (!downloadSuccess && tftpIps != null && !tftpIps.isEmpty()) {
                for (String tftpIp : tftpIps) {
                    if (downloadSuccess) {
                        break;
                    }
                    log.info("正在尝试用户 TFTP 节点: {}", tftpIp);
                    clearBuf(consoleBuf);
                    efiCmd(out, "tftp " + tftpIp + " " + efiFile);
                    // 单节点最多等 90 秒（失败时 EFI 会回 Time out + 提示符）
                    waitSignalClean(consoleBuf,
                            new String[]{"FS0:\\>", "FS0:>", "Shell>", "Time out", "timeout", "Unable"}, 90_000);
                    String tftpResult = getCleanScreen(consoleBuf);
                    log.info("【调试-tftp结果 ({})】: {}", tftpIp, tail(tftpResult, 300));
                    if (!hasDownloadError(tftpResult) && efiFileExists(out, consoleBuf, efiFile)) {
                        log.info("TFTP 下载成功！节点: {}", tftpIp);
                        downloadSuccess = true;
                        break;
                    }
                    log.warn("用户 TFTP 节点 {} 下载失败，尝试下一个...", tftpIp);
                }
                if (!downloadSuccess) {
                    log.warn("用户 TFTP 全部失败，回退公网 HTTP...");
                }
            }

            // ── HTTP：公网 boot.netboot.xyz（无用户 TFTP，或 TFTP 失败时）──
            // OVMF 已加载 httpDynamicCommand.efi；用法: http [-i eth0] <URI> [LocalFile]
            if (!downloadSuccess) {
                log.info("使用 HTTP 公网下载 netboot.xyz...");
                for (String url : httpUrls) {
                    if (downloadSuccess) {
                        break;
                    }
                    String[] cmds = {
                            "http -i eth0 " + url + " " + efiFile,
                            "http " + url + " " + efiFile,
                    };
                    for (String cmd : cmds) {
                        if (downloadSuccess) {
                            break;
                        }
                        log.info("HTTP 尝试: {}", cmd);
                        clearBuf(consoleBuf);
                        efiCmd(out, cmd);
                        waitSignalClean(consoleBuf,
                                new String[]{"FS0:\\>", "FS0:>", "Shell>", "Kb", "bytes", "Error", "error", "Unable"},
                                180_000);
                        String httpResult = getCleanScreen(consoleBuf);
                        log.info("【调试-http结果】: {}", tail(httpResult, 400));
                        if (httpResult.toLowerCase().contains("not recognized")
                                || httpResult.toLowerCase().contains("is not recognized")
                                || httpResult.toLowerCase().contains("unknown command")) {
                            log.warn("当前 Shell 不支持该 http 语法，换下一种");
                            continue;
                        }
                        if (!hasDownloadError(httpResult) && efiFileExists(out, consoleBuf, efiFile)) {
                            log.info("HTTP 下载成功: {}", url);
                            downloadSuccess = true;
                            break;
                        }
                        String remoteName = url.substring(url.lastIndexOf('/') + 1);
                        if (!efiFile.equals(remoteName) && efiFileExists(out, consoleBuf, remoteName)) {
                            log.info("HTTP 文件落在 {}，将用该名启动", remoteName);
                            efiFile = remoteName;
                            downloadSuccess = true;
                            break;
                        }
                        log.warn("HTTP 失败: {}", url);
                    }
                }
            }

            if (!downloadSuccess) {
                log.error("下载 netboot.xyz 失败。若填了 TFTP 请确认节点可达且有 amd.efi/arm.efi；否则检查实例出网 HTTP");
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
    //  步骤三：真实 Alpine 登录 → 开启 SSH → executeDd → Debian 12
    //    → root + ROOT_PASSWORD 登录 Alpine
    //    → 写 sshd 允许密码（失败时可先 SSH 上 Alpine 排查）
    //    → wget reinstall.sh + bash reinstall.sh debian 12 --username/--password
    //    → 见「Reboot to start the reinstallation」后 reboot
    //    → 等待 Debian 横幅 / 登录验证 / 再开 SSH 密码
    // ============================================================
    private boolean reinstallSystem(OutputStream out, StringBuffer consoleBuf,
                                    byte[] downArrow, byte[] upArrow, byte[] enter,
                                    InstanceDetails instanceDetails) throws Exception {

        log.info("[重装-1] netboot 菜单导航...");
        // waitScreenQuiet 对倒计时菜单永远超时；固定等待让倒计时刷新告一段落
        sleep(5000);
        clearBuf(consoleBuf);
        sleep(2000);
        log.info("[重装-1] 高亮定位 Linux Network Installs...");

        // 主菜单结构（常见）：[0] Boot from local hdd  [1] Linux Network Installs
        // 禁止整屏 contains：所有菜单项始终可见，会导致第一步就误回车
        boolean foundLinux = selectMenuItem(
                out, consoleBuf, downArrow, upArrow, enter,
                "Linux Network Installs",
                new String[]{"linux network installs"},
                null,
                12,
                1,
                1200
        );
        if (!foundLinux) {
            log.error("[重装-1] 未找到 Linux Network Installs");
            return false;
        }

        // 进入后应出现发行版列表（含 Alpine / Debian 等）
        log.info("[重装-1] 等待发行版列表...");
        if (!waitSignalClean(consoleBuf, new String[]{"Alpine", "Debian", "Ubuntu", "Distributions"}, 30_000)) {
            log.warn("[重装-1] 未明确检测到发行版列表特征，继续尝试定位 Alpine...");
        }
        sleep(2000);

        log.info("[重装-1] 高亮定位 Alpine Linux...");
        // 发行版列表默认顶项 AlmaLinux，Alpine 为其下一项（Down×1）
        boolean foundAlpine = selectMenuItem(
                out, consoleBuf, downArrow, upArrow, enter,
                "Alpine Linux",
                new String[]{"alpine linux", "alpine"},
                null,
                20,
                1,
                1200
        );
        if (!foundAlpine) {
            log.error("[重装-1] 未找到 Alpine Linux");
            return false;
        }

        // 等待 Alpine 版本/架构子菜单，顶到顶选第一项（通常是默认 netboot）
        log.info("[重装-1] 等待 Alpine 选项列表...");
        sleep(3000);
        clearBuf(consoleBuf);
        sleep(1500);
        for (int i = 0; i < 8; i++) {
            out.write(upArrow);
            out.flush();
            sleep(150);
        }
        sleep(800);
        log.info("[重装-1] 选择第一个 Alpine 选项...");
        clearBuf(consoleBuf);
        out.write(enter);
        out.flush();

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
        log.debug("[重装-1] 成功登录 Alpine 临时系统！");

        // ── 步骤二：setup-alpine 安装真实 Alpine → reboot ──
        log.debug("[重装-2] 下载 setup-alpine.config...");
        sleep(1000);
        clearBuf(consoleBuf);
        sendLine(out, "wget --no-check-certificate -qO setup-alpine.config \"" + ALPINE_CONFIG_URL + "\"");
        if (!waitSignalClean(consoleBuf, new String[]{"#", "~#", "localhost:~"}, 60_000)) {
            log.warn("[重装-2] wget 未返回提示符，继续...");
        }

        log.debug("[重装-2] 开始 setup-alpine...");
        clearBuf(consoleBuf);
        sendLine(out, "setup-alpine -f setup-alpine.config");

        log.debug("[重装-2] 等待 root 密码提示...");
        if (!waitSignal(consoleBuf, new String[]{"New password", "password for root", "Changing password"}, 60_000)) {
            log.error("[重装-2] 未出现 root 密码提示"); return false;
        }
        sleep(500);
        log.debug("[重装-2] 输入 root 密码第 1 遍");
        sendLine(out, ROOT_PASSWORD);

        if (!waitSignal(consoleBuf, new String[]{"Retype", "again", "Re-enter"}, 15_000)) {
            log.warn("[重装-2] 未检测到第 2 遍密码提示，继续...");
        }
        sleep(500);
        log.debug("[重装-2] 输入 root 密码第 2 遍");
        sendLine(out, ROOT_PASSWORD);

        // 跳过 User 创建
        if (waitSignal(consoleBuf, new String[]{"Setup a user", "loginname"}, 20_000)) {
            sleep(500);
            log.debug("[重装-2] 跳过 User 创建（直接回车）");
            sendLine(out, "");
        }

        // 等待磁盘擦除确认
        log.debug("[重装-2] 等待磁盘擦除确认（WARNING: Erase）...");
        if (!waitSignal(consoleBuf, new String[]{"WARNING: Erase", "Erase the above disk", "continue? (y/n)"}, 120_000)) {
            log.error("[重装-2] 未出现磁盘擦除确认"); return false;
        }
        sleep(500);
        log.debug("[重装-2] 确认擦盘（y）");
        sendLine(out, "y");

        // 等待安装完成
        log.debug("[重装-2] 等待 Alpine 安装完成（最多 10 分钟）...");
        if (!waitSignal(consoleBuf,
                new String[]{"Installation is complete", "Please reboot", "reboot", "installation complete"}, 600_000)) {
            log.error("[重装-2] Alpine 安装超时"); return false;
        }
        log.debug("[重装-2] Alpine 安装完成，执行 reboot...");
        sleep(2000);
        clearBuf(consoleBuf);
        sendLine(out, "reboot");

        // 等待真实 Alpine 启动
        log.debug("[重装-2] 等待真实 Alpine 启动（最多 5 分钟）...");
        if (!waitSignalClean(consoleBuf, new String[]{"login:", "localhost login", "alpine login"}, 300_000)) {
            log.error("[重装-2] 真实 Alpine 未出现登录提示"); return false;
        }
        log.debug("[重装-2] 真实 Alpine 已启动！");

        // ── 步骤三：登录真实 Alpine → apk add bash → DD 重装 ──
        log.debug("[重装-3] 登录真实 Alpine...");
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
        log.debug("[重装-3] 登录成功！");
        sleep(1000);

        // Alpine 默认 OpenSSH：PermitRootLogin=prohibit-password → 串口能登、SSH 密码 Auth fail
        log.debug("[重装-3] 开启 root 密码 SSH 登录...");
        clearBuf(consoleBuf);
        sendLine(out, "sed -i -e 's/^#*PermitRootLogin.*/PermitRootLogin yes/' "
                + "-e 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config");
        waitSignalClean(consoleBuf, new String[]{"#", "~#", "hostname:~"}, 15_000);
        clearBuf(consoleBuf);
        sendLine(out, "grep -q '^PermitRootLogin yes' /etc/ssh/sshd_config || echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config");
        waitSignalClean(consoleBuf, new String[]{"#", "~#", "hostname:~"}, 15_000);
        clearBuf(consoleBuf);
        sendLine(out, "grep -q '^PasswordAuthentication yes' /etc/ssh/sshd_config || echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config");
        waitSignalClean(consoleBuf, new String[]{"#", "~#", "hostname:~"}, 15_000);
        // 新版 openssh 可能 Include sshd_config.d/*，drop-in 更稳
        clearBuf(consoleBuf);
        sendLine(out, "mkdir -p /etc/ssh/sshd_config.d; "
                + "printf 'PermitRootLogin yes\\nPasswordAuthentication yes\\n' > /etc/ssh/sshd_config.d/99-oci-root-pass.conf");
        waitSignalClean(consoleBuf, new String[]{"#", "~#", "hostname:~"}, 15_000);

        clearBuf(consoleBuf);
        sendLine(out, "rc-service sshd restart");
        if (!waitSignalClean(consoleBuf, new String[]{"#", "~#", "hostname:~", "ok"}, 20_000)) {
            log.warn("[重装-3] sshd restart 未看到提示符，继续...");
        }
        sleep(1500);
        log.info("[重装-3] sshd 已按 root 密码登录配置重启");

        //todo 时间太长了,注释掉 Alpine 就绪后继续 DD 成 Debian 12
        /*if (!executeDd(consoleBuf, out)) {
            log.error("[重装-3] DD 重装 Debian 失败（当前可能仍是 Alpine）");
            try {
                telegramMessageService.sendMessageTemplate(String.format(
                        "————系统重装通知————\n实例【%s】\nDD Debian 失败\n当前可能仍为 Alpine\nRoot密码：%s",
                        instanceDetails.getInstanceId(), ROOT_PASSWORD));
            } catch (Exception ignored) {}
            return false;
        }*/

        log.info("================================================");
        log.info("系统重装完成！实例: {}", instanceDetails.getInstanceId());
        log.info("================================================");

        try {
            telegramMessageService.sendMessageTemplate(String.format(
                    "————系统重装通知————\n实例【%s】\n系统：Debian 12\n重装完成！\nRoot密码：%s",
                    instanceDetails.getInstanceId(), ROOT_PASSWORD));
        } catch (Exception ignored) {}

        return true;
    }


    /**
     * 在已登录的 Alpine 上运行 bin456789/reinstall.sh，重装为 Debian 12。
     * <p>
     * 对齐官方脚本 + 项目 QuickDd：
     * <ul>
     *   <li>禁止 {@code bash <(wget ...)}：Alpine 登录 shell 是 ash，进程替换无法解析</li>
     *   <li>用 {@code --username/--password} 非交互，避免 Username/Password 提示卡住</li>
     *   <li>脚本只改引导并提示重启，不会自动 reboot</li>
     *   <li>完成标志用官方文案，禁止用裸 {@code #}/{@code reboot}/{@code Done!} 误判</li>
     * </ul>
     */
    private boolean executeDd(StringBuffer consoleBuf, OutputStream out) {
        try {
            log.info("[DD] apk update...");
            clearBuf(consoleBuf);
            sendLine(out, "apk update");
            if (!waitSignalClean(consoleBuf, new String[]{"OK:", "hostname:~", "~#"}, 90_000)) {
                log.warn("[DD] apk update 未确认，继续...");
            }
            sleep(800);

            log.info("[DD] apk add bash curl wget...");
            clearBuf(consoleBuf);
            sendLine(out, "apk add bash curl wget");
            if (!waitSignalClean(consoleBuf, new String[]{"OK:", "hostname:~", "~#"}, 120_000)) {
                log.warn("[DD] apk add 未确认，继续...");
            }
            sleep(800);

            // 先落盘再 bash 执行（ash 兼容；也对齐 JschUtils.DD_SCRIPT_PARAM）
            log.info("[DD] 下载 reinstall.sh...");
            clearBuf(consoleBuf);
            sendLine(out, "wget --no-check-certificate -qO /root/reinstall.sh \"" + DD_SCRIPT_URL + "\" "
                    + "|| curl -fsSLo /root/reinstall.sh \"" + DD_SCRIPT_URL + "\"");
            if (!waitSignalClean(consoleBuf, new String[]{"hostname:~", "~#", "localhost:~"}, 120_000)) {
                log.error("[DD] 下载 reinstall.sh 等待提示符超时");
                return false;
            }
            clearBuf(consoleBuf);
            sendLine(out, "test -s /root/reinstall.sh && echo DD_SCRIPT_OK || echo DD_SCRIPT_FAIL");
            if (!waitSignal(consoleBuf, new String[]{"DD_SCRIPT_OK"}, 30_000)) {
                log.error("[DD] reinstall.sh 不存在或为空\n{}", tail(getCleanScreen(consoleBuf), 400));
                return false;
            }
            sleep(500);

            // 官方用法: bash reinstall.sh debian 12 [--username] [--password]
            // --ci 为已废弃 cloud-image 路径，默认不用
            log.info("[DD] 运行 reinstall.sh debian 12（非交互指定 root 密码）...");
            clearBuf(consoleBuf);
            sendLine(out, "bash /root/reinstall.sh debian 12 --username root --password '"
                    + ROOT_PASSWORD + "'");

            // 官方结束语（脚本本身不会 reboot）:
            //   Reboot to start the reinstallation.
            //   重启后开始重装。
            log.info("[DD] 等待 reinstall.sh 准备完成（最多 15 分钟）...");
            if (!waitSignal(consoleBuf, new String[]{
                    "Reboot to start the reinstallation",
                    "重启后开始重装",
                    "cancel the reinstallation"
            }, 900_000)) {
                log.error("[DD] 未看到 reinstall 重启提示，可能脚本失败\n{}",
                        tail(getCleanScreen(consoleBuf), 600));
                return false;
            }
            log.info("[DD] reinstall 引导已写入，执行 reboot 进入安装...");
            sleep(2000);
            clearBuf(consoleBuf);
            sendLine(out, "reboot");

            // 安装过程可能多次重启；最终 Debian 串口横幅
            log.info("[DD] 等待 Debian 12 安装完成（最多 40 分钟）...");
            if (!waitSignalClean(consoleBuf, new String[]{
                    "Debian GNU/Linux",
                    "Debian GNU/Linux 12"
            }, 2400_000)) {
                // 兜底：只要出现 login: 也继续尝试（可能横幅被冲掉）
                if (!waitSignalClean(consoleBuf, new String[]{"login:"}, 60_000)) {
                    log.error("[DD] 超时未看到 Debian/login\n{}", tail(getCleanScreen(consoleBuf), 500));
                    return false;
                }
                log.warn("[DD] 仅看到 login:，未看到 Debian 横幅，尝试登录验证...");
            } else {
                log.info("[DD] 检测到 Debian 横幅");
                waitSignalClean(consoleBuf, new String[]{"login:"}, 120_000);
            }

            sleep(1500);
            clearBuf(consoleBuf);
            log.info("[DD] 尝试验证 root 密码登录...");
            sendLine(out, "root");
            if (!waitSignal(consoleBuf, new String[]{"Password", "password"}, 20_000)) {
                log.warn("[DD] 未出现 Password 提示，可能已在 shell 或 login 被冲掉");
            } else {
                sleep(500);
                sendLine(out, ROOT_PASSWORD);
            }
            if (!waitSignalClean(consoleBuf, new String[]{"#", "~#", "root@"}, 45_000)) {
                log.warn("[DD] root 登录未确认（密码/sshd 可能仍需手工处理），安装阶段视为完成");
                return true;
            }

            // 防止误把 reinstall 临时环境当最终系统
            clearBuf(consoleBuf);
            sendLine(out, "cat /etc/os-release 2>/dev/null | head -5; echo DD_OS_MARK");
            waitSignal(consoleBuf, new String[]{"DD_OS_MARK"}, 20_000);
            String osInfo = getCleanScreen(consoleBuf).toLowerCase();
            if (osInfo.contains("alpine") && !osInfo.contains("debian")) {
                log.warn("[DD] 当前仍是 Alpine 临时环境，继续等待真正的 Debian（最多 30 分钟）...");
                // 不主动 reboot，安装脚本会自己完成并重启
                clearBuf(consoleBuf);
                if (!waitSignalClean(consoleBuf, new String[]{"Debian GNU/Linux", "Debian GNU/Linux 12"}, 1800_000)) {
                    log.error("[DD] 二次等待仍未出现 Debian");
                    return false;
                }
                waitSignalClean(consoleBuf, new String[]{"login:"}, 120_000);
                clearBuf(consoleBuf);
                sendLine(out, "root");
                if (waitSignal(consoleBuf, new String[]{"Password", "password"}, 20_000)) {
                    sleep(500);
                    sendLine(out, ROOT_PASSWORD);
                }
                if (!waitSignalClean(consoleBuf, new String[]{"#", "~#", "root@"}, 45_000)) {
                    log.warn("[DD] Debian 二次登录未确认，安装阶段视为完成");
                    return true;
                }
            }

            log.info("[DD] Debian root 登录成功，确保 SSH 允许密码...");
            clearBuf(consoleBuf);
            sendLine(out, "sed -i -e 's/^#*PermitRootLogin.*/PermitRootLogin yes/' "
                    + "-e 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config; "
                    + "mkdir -p /etc/ssh/sshd_config.d; "
                    + "printf 'PermitRootLogin yes\\nPasswordAuthentication yes\\n' > /etc/ssh/sshd_config.d/99-oci-root-pass.conf; "
                    + "systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || service ssh restart 2>/dev/null || true; "
                    + "echo DD_SSH_OK");
            waitSignal(consoleBuf, new String[]{"DD_SSH_OK", "#", "root@"}, 30_000);
            log.info("[DD] Debian 12 重装流程完成");
            return true;
        } catch (Exception e) {
            log.error("执行 DD 脚本异常", e);
            return false;
        }
    }

    // ===================== UEFI 拦截 / 屏幕状态 =====================

    /**
     * 等待 UEFI Setup 出现；一旦命中立刻 stopEsc（关键：Setup 里再 ESC 会退出并继续启动 OS）。
     */
    private boolean waitForUefiAndStopEsc(StringBuffer consoleBuf, AtomicBoolean stopEsc, long timeoutMs) {
        long start = System.currentTimeMillis();
        while (System.currentTimeMillis() - start < timeoutMs) {
            String raw = getBuf(consoleBuf);
            if (isUefiSetupScreen(raw)) {
                stopEsc.set(true);
                log.info("检测到 UEFI Setup 特征，立即停止 ESC。片段: {}", tail(stripAnsi(raw), 200));
                // 再等一小段确认不是一闪而过 / 被 ESC 打出去
                sleep(800);
                String confirm = getBuf(consoleBuf);
                if (isOsBootedScreen(confirm) && !isUefiSetupScreen(confirm)) {
                    log.warn("停止 ESC 后屏幕变成系统启动日志，本次未稳住 Setup");
                    return false;
                }
                if (isUefiSetupScreen(confirm) || isUefiSetupScreen(raw)) {
                    return true;
                }
            }
            // 已完整进 OS 且始终没有 Setup：继续等（RESET 可能尚未反映到串口），但打日志
            if (isOsBootedScreen(raw) && raw.toLowerCase().contains("cloud-init")
                    && raw.toLowerCase().contains("finished")) {
                log.warn("串口已出现 cloud-init finished，仍未见 UEFI（可能错过 POST 窗口）");
            }
            sleep(100);
        }
        stopEsc.set(true);
        return false;
    }

    /**
     * 等待菜单重绘停稳，且安静时仍须能确认处在 UEFI（不能把 OS 启动结束后的静默当成 Setup 稳定）。
     */
    private boolean waitUefiMenuStable(StringBuffer consoleBuf, OutputStream out,
                                       byte[] upArrow, long timeoutMs) throws Exception {
        long start = System.currentTimeMillis();
        int quietCount = 0;
        String lastUefiSnap = "";
        while (System.currentTimeMillis() - start < timeoutMs) {
            String snap = getBuf(consoleBuf);
            if (isOsBootedScreen(snap) && !isUefiSetupScreen(snap)) {
                log.error("【UEFI稳定】检测到操作系统启动日志，已不在 Setup");
                return false;
            }
            if (isUefiSetupScreen(snap)) {
                lastUefiSnap = snap;
            }

            clearBuf(consoleBuf);
            sleep(2000);
            String fresh = getBuf(consoleBuf);
            int newLen = fresh.length();
            log.info("【UEFI稳定】2秒内新数据: {} 字节, uefi={}, os={}",
                    newLen, isUefiSetupScreen(fresh) || isUefiSetupScreen(lastUefiSnap),
                    isOsBootedScreen(fresh));

            if (isOsBootedScreen(fresh) && !isUefiSetupScreen(fresh)) {
                log.error("【UEFI稳定】静默等待期间掉进系统");
                return false;
            }
            if (isUefiSetupScreen(fresh)) {
                lastUefiSnap = fresh;
            }

            if (newLen < 80) {
                quietCount++;
                if (quietCount >= 2) {
                    // 用一次 Up 强制重绘，确认还在 Setup
                    clearBuf(consoleBuf);
                    out.write(upArrow);
                    out.flush();
                    sleep(1200);
                    String redraw = getBuf(consoleBuf);
                    log.info("【UEFI稳定】强制重绘尾部: {}", tail(stripAnsi(redraw), 250));
                    if (isUefiSetupScreen(redraw) || isUefiSetupScreen(lastUefiSnap)) {
                        log.info("UEFI 菜单已稳定且仍在 Setup");
                        return true;
                    }
                    if (isOsBootedScreen(redraw)) {
                        log.error("强制重绘后看到系统日志");
                        return false;
                    }
                    // 无输出也不当成功：可能根本不在菜单
                    if (redraw.length() < 8 && !isUefiSetupScreen(lastUefiSnap)) {
                        log.warn("强制重绘无输出且无历史 UEFI 特征");
                        return false;
                    }
                    if (isUefiSetupScreen(lastUefiSnap)) {
                        log.info("UEFI 菜单已稳定（依据历史特征）");
                        return true;
                    }
                    return false;
                }
            } else {
                quietCount = 0;
            }
        }
        log.warn("等待 UEFI 稳定超时, lastUefi={}", isUefiSetupScreen(lastUefiSnap));
        return isUefiSetupScreen(lastUefiSnap);
    }

    private boolean ensureStillInUefi(StringBuffer consoleBuf, OutputStream out, byte[] upArrow) throws Exception {
        clearBuf(consoleBuf);
        out.write(upArrow);
        out.flush();
        sleep(1200);
        String raw = getBuf(consoleBuf);
        // 多按一次，给串口机会吐出完整菜单
        if (raw.length() < 20) {
            out.write(upArrow);
            out.flush();
            sleep(1200);
            raw = getBuf(consoleBuf);
        }
        log.info("【UEFI确认】屏幕: {}", tail(stripAnsi(raw), 300));
        if (isOsBootedScreen(raw) && !isUefiSetupScreen(raw)) {
            return false;
        }
        if (isUefiSetupScreen(raw)) {
            return true;
        }
        // 某些固件按键只刷光标属性，缓冲很短：若无 OS 特征且缓冲非空，宽松放行
        if (raw.length() > 0 && !isOsBootedScreen(raw)) {
            log.warn("【UEFI确认】未见典型 Setup 文案，但非 OS 日志，继续尝试");
            return true;
        }
        return false;
    }

    private boolean isUefiSetupScreen(String raw) {
        if (raw == null || raw.isEmpty()) {
            return false;
        }
        String c = stripAnsi(raw);
        // 强特征：命中任一即认为在 Setup
        for (String sig : UEFI_UI_SIGNALS) {
            if (c.contains(sig) || raw.contains(sig)) {
                return true;
            }
        }
        // 组合特征
        boolean hasBootMgr = c.contains("Boot Manager") || c.contains("boot manager");
        boolean hasContinue = c.contains("Continue");
        boolean hasDevice = c.contains("Device Manager");
        return hasBootMgr && (hasContinue || hasDevice);
    }

    private boolean isOsBootedScreen(String raw) {
        if (raw == null || raw.isEmpty()) {
            return false;
        }
        String c = stripAnsi(raw);
        for (String sig : OS_BOOT_SIGNALS) {
            if (c.contains(sig)) {
                return true;
            }
        }
        String lower = c.toLowerCase();
        if (lower.contains("cloud-init") || lower.contains("datasourceoracle")) {
            return true;
        }
        // 登录提示（避免单独匹配 Boot 菜单里的 ubuntu 项）
        return lower.contains(" login:") || lower.contains("\nlogin:");
    }

    /** EFI Shell：判断 FS0 上是否存在非空 efi 文件 */
    private boolean efiFileExists(OutputStream out, StringBuffer consoleBuf, String efiFile) throws Exception {
        clearBuf(consoleBuf);
        efiCmd(out, "ls " + efiFile);
        sleep(3000);
        String ls = getCleanScreen(consoleBuf);
        String lower = ls.toLowerCase();
        log.info("【调试-ls {}】: {}", efiFile, tail(ls, 200));
        if (!ls.contains(efiFile)) {
            return false;
        }
        if (lower.contains("file not found") || lower.contains("not specified")
                || lower.contains("cannot find") || lower.contains("no file")
                || lower.contains("not found")) {
            return false;
        }
        // 0 字节视为无效
        if (ls.contains("0  " + efiFile) || lower.contains("0 bytes")) {
            return false;
        }
        return true;
    }

    private boolean hasDownloadError(String screen) {
        if (screen == null || screen.isEmpty()) {
            return true;
        }
        String lower = screen.toLowerCase();
        return lower.contains("error") || lower.contains("time out") || lower.contains("timeout")
                || lower.contains("unable") || lower.contains("not recognized")
                || lower.contains("invalid") || lower.contains("failed")
                || lower.contains("not found") || lower.contains("404");
    }

    /** Boot Manager 子菜单内等待安静（已确认在 Setup 内） */
    private boolean waitScreenQuiet(StringBuffer consoleBuf, long timeoutMs) {
        long start = System.currentTimeMillis();
        int quietCount = 0;
        while (System.currentTimeMillis() - start < timeoutMs) {
            clearBuf(consoleBuf);
            sleep(3000);
            int newLen = getBuf(consoleBuf).length();
            log.info("【重绘检测】3秒内新数据: {} 字节", newLen);
            if (newLen < 100) {
                quietCount++;
                if (quietCount >= 2) {
                    log.info("屏幕已稳定");
                    return true;
                }
            } else {
                quietCount = 0;
            }
        }
        log.warn("等待屏幕稳定超时");
        return false;
    }

    // ===================== 菜单高亮定位 =====================

    /**
     * 复位到菜单顶部后逐步 Down，根据高亮/光标判断当前选中项，命中后回车。
     *
     * @param label           日志用名称
     * @param keywords        命中关键字（小写匹配，任一命中即可）
     * @param excludeKeyword  排除关键字（如 Boot Manager 要排除 maintenance），可为 null
     * @param maxSteps        最多 Down 次数
     * @param fixedOffset     高亮检测全部失败时的 fallback：从顶 Down 固定次数后回车；null 表示不 fallback
     * @param stepDelayMs     每次按键后等待重绘的毫秒
     */
    private boolean selectMenuItem(OutputStream out, StringBuffer consoleBuf,
                                   byte[] downArrow, byte[] upArrow, byte[] enter,
                                   String label, String[] keywords, String excludeKeyword,
                                   int maxSteps, Integer fixedOffset, long stepDelayMs) throws Exception {
        log.info("[菜单] 定位「{}」: 复位顶部 → 逐步高亮匹配", label);
        resetMenuCursorToTop(out, upArrow, 12);

        // 先检查当前位置（顶部），再逐步 Down
        clearBuf(consoleBuf);
        out.write(upArrow);
        out.flush();
        sleep(stepDelayMs);

        String raw = getBuf(consoleBuf);
        logSelectedDebug(label, 0, raw);
        if (isOsBootedScreen(raw) && !isUefiSetupScreen(raw)) {
            log.error("[菜单] 定位「{}」时已在操作系统中，放弃", label);
            return false;
        }
        if (isMenuItemSelected(raw, keywords, excludeKeyword)) {
            log.info("[菜单] 「{}」已在顶部高亮，回车", label);
            clearBuf(consoleBuf);
            out.write(enter);
            out.flush();
            return true;
        }

        int emptySteps = 0;
        for (int step = 1; step <= maxSteps; step++) {
            clearBuf(consoleBuf);
            out.write(downArrow);
            out.flush();
            sleep(stepDelayMs);
            raw = getBuf(consoleBuf);
            if (raw.length() < 8) {
                sleep(stepDelayMs);
                raw = getBuf(consoleBuf);
            }
            logSelectedDebug(label, step, raw);

            if (isOsBootedScreen(raw) && !isUefiSetupScreen(raw)) {
                log.error("[菜单] 第 {} 步发现系统启动日志，放弃定位「{}」", step, label);
                return false;
            }
            if (raw.length() < 8) {
                emptySteps++;
                // 连续空屏：大概率不在 TUI 菜单
                if (emptySteps >= 3) {
                    log.error("[菜单] 连续 {} 步无串口回显，当前不在可导航菜单", emptySteps);
                    return false;
                }
            } else {
                emptySteps = 0;
            }

            if (isMenuItemSelected(raw, keywords, excludeKeyword)) {
                log.info("[菜单] 第 {} 步命中「{}」高亮，回车", step, label);
                sleep(300);
                clearBuf(consoleBuf);
                out.write(enter);
                out.flush();
                return true;
            }
        }

        if (fixedOffset != null && fixedOffset >= 0) {
            log.warn("[菜单] 「{}」高亮未命中，fallback 固定偏移 Down×{}", label, fixedOffset);
            // fallback 前再确认不是 OS
            if (isOsBootedScreen(getBuf(consoleBuf)) && !isUefiSetupScreen(getBuf(consoleBuf))) {
                log.error("[菜单] fallback 前已在 OS，取消");
                return false;
            }
            resetMenuCursorToTop(out, upArrow, 12);
            clearBuf(consoleBuf);
            for (int i = 0; i < fixedOffset; i++) {
                out.write(downArrow);
                out.flush();
                sleep(Math.max(400L, stepDelayMs / 2));
            }
            sleep(500);
            clearBuf(consoleBuf);
            out.write(enter);
            out.flush();
            return true;
        }

        log.error("[菜单] 未能定位「{}」。最后屏幕: {}", label, tail(stripAnsi(raw), 400));
        return false;
    }

    private void resetMenuCursorToTop(OutputStream out, byte[] upArrow, int times) throws Exception {
        for (int i = 0; i < times; i++) {
            out.write(upArrow);
            out.flush();
            sleep(200);
        }
        sleep(600);
    }

    /**
     * 判断 raw 串口缓冲中「当前选中项」是否匹配 keywords，且不含 excludeKeyword。
     */
    private boolean isMenuItemSelected(String raw, String[] keywords, String excludeKeyword) {
        if (raw == null || raw.isEmpty() || keywords == null || keywords.length == 0) {
            return false;
        }
        List<String> candidates = extractSelectedCandidates(raw);
        if (candidates.isEmpty()) {
            return false;
        }
        for (String candidate : candidates) {
            String lower = candidate.toLowerCase();
            if (excludeKeyword != null && lower.contains(excludeKeyword.toLowerCase())) {
                continue;
            }
            for (String kw : keywords) {
                if (kw != null && lower.contains(kw.toLowerCase())) {
                    log.info("[菜单] 选中候选命中: [{}] ← keyword [{}]", candidate, kw);
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * 从原始串口输出提取「当前选中项」候选。
     * 优先 OVMF 帮助区 / Select Entry+Device Path；其次 reverse video；
     * iPXE/netboot 在 Oracle 串口上常用「短重绘最后一项」推断（无 reverse video）。
     * 不把行首 ">" 当光标（OVMF 上它表示有子菜单）。
     */
    private List<String> extractSelectedCandidates(String raw) {
        Set<String> result = new LinkedHashSet<String>();
        if (raw == null || raw.isEmpty()) {
            return new ArrayList<String>();
        }

        String clean = stripAnsi(raw);
        extractOvmfSelected(clean, result);

        Matcher rev = REVERSE_VIDEO.matcher(raw);
        while (rev.find()) {
            addCandidate(result, stripAnsi(rev.group(1)));
        }

        Matcher bg = BG_HIGHLIGHT.matcher(raw);
        while (bg.find()) {
            addCandidate(result, stripAnsi(bg.group(1)));
        }

        // iPXE 偶发用 * 标记选中行；仅接受单独 * 行，避免误伤
        String[] lines = clean.split("\\r\\n|\\n|\\r");
        for (String line : lines) {
            String t = line.trim();
            if (t.startsWith("*") && t.length() > 2 && t.length() < 60) {
                addCandidate(result, t.substring(1));
            }
        }

        // Oracle 串口 + netboot.xyz：无可靠 reverse video 时靠重绘推断
        extractIpxeRedrawSelected(raw, result);

        return new ArrayList<String>(result);
    }

    /**
     * iPXE/netboot.xyz 菜单在串口上的选中推断。
     * <p>
     * 实测：按 Down/Up 时不会发 7m reverse video，而是用大片空格分栏重绘
     * 「刚离开的项 + 新选中项」，例如：
     * <pre>
     *   AlmaLinux                          Alpine Linux
     *   Boot from local hdd                Linux Network Installs (64-bit)
     * </pre>
     * 短重绘（1~3 段文本）时，最后一段 = 当前高亮。
     * 整页刷出一长串菜单项时不可靠，直接跳过。
     */
    private void extractIpxeRedrawSelected(String raw, Set<String> result) {
        if (raw == null || raw.isEmpty()) {
            return;
        }
        // 去 ANSI，但保留多空格边界（stripAnsi 会 collapse，这里不能用）
        String s = ANSI_CSI.matcher(raw).replaceAll("");
        s = ANSI_OTHER.matcher(s).replaceAll("");
        s = s.replace("\u001B", "");

        String[] parts = s.split("[\\t ]{2,}|\\r\\n|\\n|\\r");
        List<String> items = new ArrayList<String>();
        for (String p : parts) {
            String t = normalizeMenuText(p);
            if (t.length() < 2 || t.length() > 80) {
                continue;
            }
            // 倒计时秒数 "(293)" / 纯数字
            if (t.matches("\\(\\d+\\)") || t.matches("\\d+")) {
                continue;
            }
            // 加载噪声 / 小节标题
            if (t.endsWith(":") || t.endsWith("...") || t.contains("... ok") || t.contains(".sig")) {
                continue;
            }
            if (t.toLowerCase().contains("current arch") || t.toLowerCase().contains("linux distros")) {
                continue;
            }
            if (isMenuChromeText(t)) {
                continue;
            }
            items.add(t);
        }
        if (items.isEmpty() || items.size() > 3) {
            return;
        }
        addCandidate(result, items.get(items.size() - 1));
    }

    /**
     * Oracle OVMF Setup / Boot Manager 选中项提取（基于真实串口样本）。
     */
    private void extractOvmfSelected(String clean, Set<String> result) {
        if (clean == null || clean.isEmpty()) {
            return;
        }

        // 1) Boot Manager 子菜单：Select Entry + 项名 + Device Path
        Matcher entry = OVMF_SELECT_ENTRY.matcher(clean);
        while (entry.find()) {
            String name = normalizeMenuText(entry.group(1));
            // 去掉可能夹带的帮助栏碎片
            name = name.replaceAll("(?i)Esc\\s*=\\s*Exit", " ");
            name = name.replaceAll("(?i)\\^v\\s*=\\s*Move Highlight", " ");
            name = name.replaceAll("(?i)<Enter>\\s*=\\s*Select Entry", " ");
            name = normalizeMenuText(name);
            if (name.length() >= 2 && name.length() <= 80) {
                addCandidate(result, name);
            }
        }

        // 2) Device Path 含 EFI Shell GUID → 当前必为 EFI Internal Shell
        //    例：Device Path : Fv(...)/FvFile(7C04A583-9E3E-4F1C-AD65-E05268D0B4D1)
        if (clean.toUpperCase().contains(EFI_SHELL_FILE_GUID)) {
            addCandidate(result, "EFI Internal Shell");
        }

        // 3) 主菜单帮助文案（互斥优先级：Maintenance > Boot Manager > Device Manager > Language）
        String lower = clean.toLowerCase();
        if (lower.contains(BOOT_MAINT_HELP.toLowerCase())
                || lower.contains("boot maintenance manager")) {
            // 仅当帮助区明确指向 Maintenance 时
            if (lower.contains("take you to the boot maintenance")) {
                addCandidate(result, "Boot Maintenance Manager");
            }
        }
        if (lower.contains(BOOT_MGR_HELP.toLowerCase())
                && !lower.contains(BOOT_MAINT_HELP.toLowerCase())) {
            addCandidate(result, "Boot Manager");
        }
        if (lower.contains(DEVICE_MGR_HELP.toLowerCase())) {
            addCandidate(result, "Device Manager");
        }
        if (lower.contains(LANG_HELP) || lower.contains("adjusts to change")) {
            addCandidate(result, "Select Language");
        }
    }

    private void addCandidate(Set<String> result, String text) {
        String t = normalizeMenuText(text);
        if (t.length() < 2 || isMenuChromeText(t)) {
            return;
        }
        result.add(t);
    }

    private String normalizeMenuText(String s) {
        if (s == null) {
            return "";
        }
        return s.replaceAll("[ \\t\\r\\n]+", " ").trim();
    }

    /** 过滤标题栏/键位说明，避免被当成“当前选中菜单项” */
    private boolean isMenuChromeText(String text) {
        String l = text.toLowerCase();
        if (l.equals("boot manager menu") || l.endsWith(" manager menu")) {
            return true;
        }
        if (l.contains("move highlight") || l.contains("enter=select") || l.contains("esc=exit")) {
            return true;
        }
        if (l.startsWith("device path") || l.equals("select entry")) {
            return true;
        }
        // 过长多为未截断的帮助描述整段
        return l.length() > 90;
    }

    private void logSelectedDebug(String label, int step, String raw) {
        List<String> candidates = extractSelectedCandidates(raw);
        log.info("[菜单-调试] {} step={} 高亮候选={} 屏幕尾部={}",
                label, step, candidates, tail(stripAnsi(raw), 220));
    }

    // ===================== 工具方法 =====================
    private String stripAnsi(String raw) {
        if (raw == null || raw.isEmpty()) {
            return "";
        }
        String s = ANSI_CSI.matcher(raw).replaceAll("");
        s = ANSI_OTHER.matcher(s).replaceAll("");
        return s.replaceAll("[ \\t]+", " ");
    }

    private String getCleanScreen(StringBuffer buf) {
        return stripAnsi(getBuf(buf));
    }

    private void efiCmd(OutputStream out, String cmd) throws Exception {
        log.info("[EFI] > {}", cmd); out.write((cmd + "\r\n").getBytes()); out.flush();
    }
    private void sendLine(OutputStream out, String line) throws Exception {
        // Shell input may contain login passwords or commands with embedded credentials.
        log.debug("[Shell] 发送输入");
        out.write((line + "\n").getBytes());
        out.flush();
    }
    private boolean waitSignal(StringBuffer cb, String[] sigs, long t) throws Exception {
        long s = System.currentTimeMillis();
        while (System.currentTimeMillis() - s < t) { String c = getBuf(cb); for (String si : sigs) if (c.contains(si)) { log.info("检测到: [{}]", si); return true; } sleep(200); }
        log.warn("超时: {}", Arrays.toString(sigs)); return false;
    }
    private boolean waitSignalClean(StringBuffer cb, String[] sigs, long t) throws Exception {
        long s = System.currentTimeMillis();
        while (System.currentTimeMillis() - s < t) {
            String r = getBuf(cb);
            String c = stripAnsi(r);
            for (String si : sigs) {
                if (r.contains(si) || c.contains(si)) {
                    log.info("检测到: [{}]", si);
                    return true;
                }
            }
            sleep(200);
        }
        log.warn("超时: {}", Arrays.toString(sigs));
        return false;
    }
    private void clearBuf(StringBuffer buf) { synchronized (buf) { buf.setLength(0); } }
    private String getBuf(StringBuffer buf) { synchronized (buf) { return buf.toString(); } }
    private String tail(String s, int n) { return (s == null || s.length() <= n) ? s : "..." + s.substring(s.length() - n); }
    private void sleep(long ms) { try { Thread.sleep(ms); } catch (InterruptedException ignored) {} }

    private void startOutputReaderThread(InputStream in, StringBuffer buffer, AtomicBoolean keepReading) {
        new Thread(() -> {
            try { byte[] buf = new byte[4096]; while (keepReading.get()) { int a = in.available(); if (a > 0) { int l = in.read(buf, 0, Math.min(buf.length, a)); if (l > 0) { String ch = new String(buf, 0, l); synchronized (buffer) { buffer.append(ch); if (buffer.length() > 100_000) buffer.delete(0, 50_000); } } } else { Thread.sleep(50); } } }
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

    /**
     * 解析用户填写的 TFTP 节点。支持逗号/分号/空白分隔多个 IP 或主机名。
     * 空 / null → 空列表（跳过 TFTP，走 HTTP）。
     */
    private List<String> parseUserTftpHosts(String tftpHost) {
        List<String> ips = new ArrayList<String>();
        if (tftpHost == null) {
            return ips;
        }
        String raw = tftpHost.trim();
        if (raw.isEmpty()) {
            return ips;
        }
        String[] parts = raw.split("[,;\\s]+");
        for (String p : parts) {
            if (p == null) {
                continue;
            }
            String host = p.trim();
            if (host.isEmpty()) {
                continue;
            }
            // 去掉误填的协议/路径
            if (host.startsWith("tftp://")) {
                host = host.substring("tftp://".length());
            }
            if (host.startsWith("http://") || host.startsWith("https://")) {
                log.warn("忽略非 TFTP 地址: {}", host);
                continue;
            }
            int slash = host.indexOf('/');
            if (slash > 0) {
                host = host.substring(0, slash);
            }
            if (!ips.contains(host)) {
                ips.add(host);
            }
        }
        return ips;
    }
}

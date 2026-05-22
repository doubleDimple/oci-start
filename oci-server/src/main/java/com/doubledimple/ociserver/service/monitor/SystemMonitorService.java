package com.doubledimple.ociserver.service.monitor;

import com.doubledimple.ociserver.pojo.request.SystemInfoDTO;
import com.doubledimple.ociserver.pojo.response.SystemMetrics;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import oshi.SystemInfo;
import oshi.hardware.CentralProcessor;
import oshi.hardware.GlobalMemory;
import oshi.hardware.HardwareAbstractionLayer;
import oshi.hardware.NetworkIF;
import oshi.hardware.VirtualMemory;
import oshi.software.os.OperatingSystem;

import java.io.File;
import java.lang.management.ManagementFactory;
import java.lang.management.OperatingSystemMXBean;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * @author doubleDimple
 * @date 2024:11:28日 22:34
 */
@Service
@Slf4j
public class SystemMonitorService {

    private SystemMetrics lastMetrics;
    private final OperatingSystemMXBean osBean;
    private final SystemInfo si;
    private final Map<String, Long> lastRxBytes;
    private final Map<String, Long> lastTxBytes;
    private final SystemInfoDTO systemInfo;

    public SystemMonitorService() {
        this.osBean = ManagementFactory.getPlatformMXBean(OperatingSystemMXBean.class);
        this.lastMetrics = SystemMetrics.builder()
                .lastUploadBytes(0L)
                .lastDownloadBytes(0L)
                .lastUpdateTime(System.currentTimeMillis())
                .build();
        this.si = new SystemInfo();
        this.lastRxBytes = new HashMap<>();
        this.lastTxBytes = new HashMap<>();
        this.systemInfo = initSystemInfo();
    }

    private SystemInfoDTO initSystemInfo() {
        try {
            OperatingSystem os = si.getOperatingSystem();
            HardwareAbstractionLayer hardware = si.getHardware();
            CentralProcessor processor = hardware.getProcessor();
            GlobalMemory memory = hardware.getMemory();
            List<NetworkIF> networkIFs = hardware.getNetworkIFs();

            // 收集网络接口信息
            List<String> networkInterfacesList = new ArrayList<>();
            List<String> ipAddressesList = new ArrayList<>();

            for (NetworkIF net : networkIFs) {
                networkInterfacesList.add(net.getName() + " (" + net.getDisplayName() + ")");
                String[] ips = net.getIPv4addr();
                if (ips.length > 0) {
                    ipAddressesList.add(ips[0]);
                }
            }

            SystemInfoDTO sysInfo = SystemInfoDTO.builder()
                    .osName(os.getFamily() + " " + os.getVersionInfo().getVersion())
                    .osArch(System.getProperty("os.arch"))
                    .osVersion(os.getVersionInfo().toString())
                    .hostname(os.getNetworkParams().getHostName())
                    .cpuModel(processor.getProcessorIdentifier().getName())
                    .cpuVendor(processor.getProcessorIdentifier().getVendor())
                    .cpuPhysicalCount(processor.getPhysicalProcessorCount())
                    .cpuLogicalCount(processor.getLogicalProcessorCount())
                    .cpuFrequency(processor.getMaxFreq() / 1000000000.0)
                    .totalMemory(memory.getTotal() / (1024 * 1024 * 1024))
                    .totalSwap(memory.getVirtualMemory().getSwapTotal() / (1024 * 1024 * 1024))
                    .ipAddresses(ipAddressesList.toArray(new String[0]))
                    .networkInterfaces(networkInterfacesList.toArray(new String[0]))
                    .build();

            log.debug("System Info initialized: {}", sysInfo);
            return sysInfo;
        } catch (Exception e) {
            log.error("Failed to initialize system info", e);
            return null;
        }
    }

    @Scheduled(fixedRate = 3000)
    public SystemMetrics collectMetrics() {
        try {
            HardwareAbstractionLayer hardware = si.getHardware();
            CentralProcessor processor = hardware.getProcessor();
            GlobalMemory memory = hardware.getMemory();
            OperatingSystem os = si.getOperatingSystem();

            // CPU信息
            long[] prevTicks = processor.getSystemCpuLoadTicks();
            Thread.sleep(1000);
            long[] ticks = processor.getSystemCpuLoadTicks();
            double cpuLoad = processor.getSystemCpuLoadBetweenTicks(prevTicks) * 100;
            double cpuTemp = hardware.getSensors().getCpuTemperature();
            CentralProcessor.ProcessorIdentifier cpuInfo = processor.getProcessorIdentifier();

            // 内存信息
            long totalMemory = memory.getTotal();
            long availableMemory = memory.getAvailable();
            long usedMemory = totalMemory - availableMemory;
            double memoryUsage = ((double) usedMemory / totalMemory) * 100;

            // 交换空间信息
            VirtualMemory virtualMemory = memory.getVirtualMemory();
            long swapTotal = virtualMemory.getSwapTotal();
            long swapUsed = virtualMemory.getSwapUsed();
            double swapUsage = swapTotal > 0 ? ((double) swapUsed / swapTotal) * 100 : 0;

            // 磁盘信息
            File root = new File("/");
            long totalSpace = root.getTotalSpace();
            long usableSpace = root.getUsableSpace();
            long usedSpace = totalSpace - usableSpace;
            double diskUsage = ((double) usedSpace / totalSpace) * 100;

            // 网络信息
            double[] networkSpeeds = getNetworkUsage();

            return SystemMetrics.builder()
                    // CPU信息
                    .cpuUsage(Math.min(100, Math.round(cpuLoad * 100.0) / 100.0))
                    .cpuTemperature(cpuTemp > 0 ? cpuTemp : null)
                    .cpuPhysicalCount(processor.getPhysicalProcessorCount())
                    .cpuLogicalCount(processor.getLogicalProcessorCount())
                    .cpuModel(cpuInfo.getName())
                    .cpuFrequency(cpuInfo.getVendorFreq() / 1_000_000_000.0)

                    // 内存信息
                    .memoryUsage(Math.round(memoryUsage * 100.0) / 100.0)
                    .totalMemory(totalMemory / (1024 * 1024))
                    .availableMemory(availableMemory / (1024 * 1024))
                    .usedMemory(usedMemory / (1024 * 1024))
                    .swapUsage(Math.round(swapUsage * 100.0) / 100.0)
                    .swapTotal(swapTotal / (1024 * 1024))
                    .swapUsed(swapUsed / (1024 * 1024))

                    // 磁盘信息
                    .diskUsage(Math.round(diskUsage * 100.0) / 100.0)
                    .diskTotal(totalSpace)
                    .diskUsed(usedSpace)
                    .diskFree(usableSpace)

                    // 网络信息
                    .uploadSpeed(networkSpeeds[0])
                    .downloadSpeed(networkSpeeds[1])
                    .totalUploadBytes((long)networkSpeeds[2])    // 添加总发送字节数
                    .totalDownloadBytes((long)networkSpeeds[3])  // 添加总接收字节数
                    .lastUploadBytes(lastMetrics.getLastUploadBytes())
                    .lastDownloadBytes(lastMetrics.getLastDownloadBytes())
                    .lastUpdateTime(lastMetrics.getLastUpdateTime())

                    // 系统信息
                    .totalProcesses(os.getProcessCount())
                    .threadCount(os.getThreadCount())
                    .systemUptime(os.getSystemUptime())
                    .osName(os.getFamily() + " " + os.getVersionInfo())
                    .osArch(System.getProperty("os.arch"))
                    .hostname(os.getNetworkParams().getHostName())

                    .timestamp(LocalDateTime.now())
                    .build();

        } catch (Exception e) {
            log.error("Failed to collect system metrics:{}", e.getMessage());
            return null;
        }
    }

    private double[] getNetworkUsage() {
        try {
            HardwareAbstractionLayer hal = si.getHardware();
            long totalRxBytes = 0L;
            long totalTxBytes = 0L;
            long currentTime = System.currentTimeMillis();

            for (NetworkIF net : hal.getNetworkIFs()) {
                // 跳过禁用的网卡和本地回环接口
                if (!net.isConnectorPresent() || net.getName().equals("lo")) {
                    continue;
                }

                // 更新网络接口数据
                net.updateAttributes();

                // 获取当前总字节数
                totalRxBytes += net.getBytesRecv();
                totalTxBytes += net.getBytesSent();

                // 保存每个接口的统计数据
                lastRxBytes.put(net.getName(), net.getBytesRecv());
                lastTxBytes.put(net.getName(), net.getBytesSent());
            }

            double timeDiff = (currentTime - lastMetrics.getLastUpdateTime()) / 1000.0;

            // 计算速率 (KB/s)
            double uploadSpeed = (totalTxBytes - lastMetrics.getLastUploadBytes()) / timeDiff / 1024;
            double downloadSpeed = (totalRxBytes - lastMetrics.getLastDownloadBytes()) / timeDiff / 1024;

            // 更新统计数据
            lastMetrics.setLastUploadBytes(totalTxBytes);
            lastMetrics.setLastDownloadBytes(totalRxBytes);
            lastMetrics.setLastUpdateTime(currentTime);

            return new double[]{
                    Math.max(0, uploadSpeed),
                    Math.max(0, downloadSpeed),
                    totalTxBytes,  // 添加总发送字节数
                    totalRxBytes   // 添加总接收字节数
            };

        } catch (Exception e) {
            log.error("Failed to get network usage", e);
            return new double[]{0d, 0d, 0d, 0d};  // 返回四个0
        }
    }

    public SystemInfoDTO getSystemInfo() {
        return this.systemInfo;
    }
}

package com.doubledimple.ocicommon.param.monitor;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;

import java.io.Serializable;
import java.util.List;

/**
 * @version 1.0.0
 * @ClassName MonitorReportDTO
 * @Description TODO
 * @Author doubleDimple
 * @Date 2026-02-05 13:33
 */
@Data
public class MonitorReportDTO implements Serializable {
    /** 机器身份凭证(机器实例id也就是instanceId) */
    private String token;

    /** 上报时间戳 (可选，如果脚本没发可以用后端接收时间) */
    private Long timestamp;

    private HostInfo host;
    private CpuInfo cpu;
    private MemInfo memory;
    private DiskInfo disk;
    private NetInfo network;

    /** 对应 JSON 中的 "host" */
    @Data
    public static class HostInfo implements Serializable {
        private String name;    // Hostname
        private String os;      // 操作系统名称
        private String kernel;  // 内核版本
        private Long uptime;    // 运行时间(秒)
        private String virt;    // 虚拟化架构(可选)
    }

    /** 对应 JSON 中的 "cpu" */
    @Data
    public static class CpuInfo implements Serializable {
        private Integer cores;       // 核心数
        private Double usage;        // 使用率 %
        private String model;        // CPU 型号
        private List<Double> load;   // 负载 [1min, 5min, 15min]
    }

    /** 对应 JSON 中的 "memory" */
    @Data
    public static class MemInfo implements Serializable {
        private Long total;          // 总内存 (MB)
        private Long used;           // 已用内存 (MB)
        @JsonProperty("swap_used")   // 对应 JSON 里的下划线命名
        private Long swapUsed;       // Swap 已用 (MB)
    }

    /** 对应 JSON 中的 "disk" */
    @Data
    public static class DiskInfo implements Serializable {
        private Long total;          // 总容量 (MB)
        private Long used;           // 已用容量 (MB)
    }

    /** 对应 JSON 中的 "network" */
    @Data
    public static class NetInfo implements Serializable {
        // 因为 interface 是 Java 关键字，所以必须用注解映射 JSON 里的 "interface" 字段
        @JsonProperty("interface")
        private String interfaceName;

        @JsonProperty("rx_rate")
        private Long rxRate;         // 下载速率 (Bytes/s)

        @JsonProperty("tx_rate")
        private Long txRate;         // 上传速率 (Bytes/s)

        @JsonProperty("rx_total")
        private Long rxTotal;        // 总下载流量 (Bytes)

        @JsonProperty("tx_total")
        private Long txTotal;        // 总上传流量 (Bytes)
    }
}

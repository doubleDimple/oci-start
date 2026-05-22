package com.doubledimple.ocicommon.enums;

public enum ModelSelectionStrategy {

    ROUND_ROBIN,    // 轮询
    RANDOM,         // 随机
    LEAST_USED,     // 最少使用
    LOAD_BALANCE    // 综合负载均衡


}

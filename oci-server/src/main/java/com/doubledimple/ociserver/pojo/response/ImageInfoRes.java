package com.doubledimple.ociserver.pojo.response;

import com.doubledimple.ocicommon.enums.ProviderType;
import lombok.Data;

import java.io.Serializable;

/**
 * @version 1.0.0
 * @ClassName ImageInfoRes
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-10-29 03:47
 */
@Data
public class ImageInfoRes implements Serializable {
    private int cloudType; //云厂商类型 CloudTypeEnum
    private String imageId;
    private String operatingSystem;      // 操作系统名称，如 Canonical Ubuntu
    private String operatingSystemVersion; // 系统版本，如 20.04
    private String architecture;         // CPU 架构：AMD / ARM
    private boolean alwaysFreeEligible;  // 是否 Always Free 可用
}

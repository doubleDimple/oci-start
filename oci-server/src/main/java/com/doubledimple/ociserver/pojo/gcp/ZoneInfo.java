package com.doubledimple.ociserver.pojo.gcp;

/**
 * @version 1.0.0
 * @ClassName ZoneInfo
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-06-22 14:40
 */

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.Data;
import lombok.ToString;

/**
 * 区域信息
 */
@JsonIgnoreProperties(ignoreUnknown = true)
@Data
@ToString
public class ZoneInfo {
    private String id;
    private String name;
    private String description;
    private String status;
    private String region;


}

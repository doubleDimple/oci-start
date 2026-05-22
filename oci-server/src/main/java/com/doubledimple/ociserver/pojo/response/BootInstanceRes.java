package com.doubledimple.ociserver.pojo.response;

import com.doubledimple.dao.entity.BootInstance;
import lombok.Data;

/**
 * @author doubleDimple
 * @date 2024:10:08日 22:11
 */
@Data
public class BootInstanceRes extends BootInstance {

    private String userName;
    private String createAtStr;

    private String tenancyName;
    private String regionName;

    private String defName;

    private Boolean openBootFlag;

    private Long recordCount = 0L;

    private Long executingCount = 0L;
}

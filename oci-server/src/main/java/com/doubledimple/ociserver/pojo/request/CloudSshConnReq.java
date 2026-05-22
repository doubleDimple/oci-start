package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

import javax.persistence.Column;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;

/**
 * @version 1.0.0
 * @ClassName CloudSshConnReq
 * @Description TODO
 * @Author renyx
 * @Date 2025-11-07 22:47
 */
@Data
public class CloudSshConnReq {

    private String instanceId;


    /**
     * 用户名
     */
    private String name;

    /**
     * 备注
     */
    private String remark;

    /**
     * ssh连接的用户名
     */
    private String username;

    /**
     * host域名
     */
    private String host;

    /**
     * ssh连接的端口
     */
    private Integer port;

    private String password;

    private int cloudType = 1;

    /** 文件夹ID */
    private Long folderId;
}

package com.doubledimple.ociserver.pojo.request;

import com.doubledimple.dao.entity.InstanceCloudNetWork;
import com.doubledimple.ociserver.pojo.enums.AccountTypeEnum;
import com.oracle.bmc.identity.model.RegionSubscription;
import lombok.Data;

import java.util.List;

/**
 * @version 1.0.0
 * @ClassName TenancyDetail
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-03-06 14:13
 */
@Data
public class TenancyDetail {

    //区域
    List<RegionSubscription> regionSubscriptions;

    // 租户名
    String tenancyName;

    //租户描述
    String description;

    //账号类型
    AccountTypeEnum accountTypeEnum;

    List<InstanceCloudNetWork> instanceCloudNetWorkList;
}

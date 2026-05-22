package com.doubledimple.ociserver.service;

import com.doubledimple.ociserver.pojo.response.OciIpRange;

import java.util.List;

public interface OciIpRangeService {

    /**
     * 更新IP范围数据（从远程API获取）
     */
    List<OciIpRange> updateIpRangesFromRemote();

    /**
     * 获取所有IP范围（三级查询：缓存->数据库->远程API）
     * @return IP范围列表
     */
    List<OciIpRange> getAllIpRanges();

    /**
     * 清除缓存
     */
    void clearCache();

    List<String> findCidrsByRegionAndCidrIn(String region, List<String> cidrList);
}

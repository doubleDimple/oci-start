package com.doubledimple.ociserver.service;

import com.doubledimple.dao.entity.VpnProxyRecord;
import com.doubledimple.ociserver.pojo.request.VpnProxyRecordRequest;
import org.springframework.data.domain.Page;

import java.util.List;
import java.util.Map;

public interface VpnProxyRecordService {


    Page<VpnProxyRecord> listPage(VpnProxyRecordRequest vpnProxyRecordRequest);

    /**
    * save or update
    */
    void saveOrUpdate(VpnProxyRecordRequest vpnProxyRecordRequest);

    List<VpnProxyRecord> queryListEnable();

    void delete(VpnProxyRecordRequest vpnProxyRecordRequest);

    /**
     * 测试单条代理连通性，结果写入 availableStatus（1=通，0=不通）
     */
    Map<String, Object> testConnection(Long id);

    /**
     * 测试全部代理连通性，逐条探测并落库
     */
    Map<String, Object> testAll();

    /**
     * 租户快捷绑定：将父租户绑定到指定代理；proxyId 为空则解绑。
     * 同一租户只会保留一条绑定。
     */
    void bindTenant(Long tenantId, Long proxyId);

    /**
     * 查询租户当前绑定的代理（含子区域继承父账号）；无则 null。
     */
    VpnProxyRecord findBoundByTenantId(Long tenantId);
}

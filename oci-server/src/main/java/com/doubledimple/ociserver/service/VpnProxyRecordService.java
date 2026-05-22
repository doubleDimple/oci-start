package com.doubledimple.ociserver.service;

import com.doubledimple.dao.entity.VpnProxyRecord;
import com.doubledimple.ociserver.pojo.request.VpnProxyRecordRequest;
import org.springframework.data.domain.Page;

import java.util.List;

public interface VpnProxyRecordService {


    Page<VpnProxyRecord> listPage(VpnProxyRecordRequest vpnProxyRecordRequest);

    /**
    * save or update
    */
    void saveOrUpdate(VpnProxyRecordRequest vpnProxyRecordRequest);

    List<VpnProxyRecord> queryListEnable();

    void delete(VpnProxyRecordRequest vpnProxyRecordRequest);
}
